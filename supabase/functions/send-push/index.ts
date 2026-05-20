import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import WebPush from 'https://esm.sh/web-push@3.6.7';

Deno.serve(async (req) => {
  console.log("Push function started...");

  try {
    // 1. Get secrets
    const VAPID_PUBLIC_KEY = Deno.env.get('PUBLIC_VAPID_KEY')
    const VAPID_PRIVATE_KEY = Deno.env.get('PRIVATE_VAPID_KEY')
    const VAPID_SUBJECT = Deno.env.get('VAPID_SUBJECT')

    if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY || !VAPID_SUBJECT) {
      throw new Error("Missing VAPID secrets. Check 'supabase secrets list'.");
    }

    WebPush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

    // 2. Parse payload
    const payload = await req.json();
    console.log("Processing payload:", JSON.stringify(payload));
    const { record } = payload;

    if (!record || !record.game_id) {
      return new Response(
        JSON.stringify({ error: "No record or game_id found" }),
        { status: 400 }
      );
    }

    // 3. Initialize Supabase
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    // 4. Get player IDs for the game
    const { data: players, error: playerError } = await supabase
      .from('ranked_game_players')
      .select('user_id')
      .eq('game_id', record.game_id);

    if (playerError) throw playerError;

    if (!players || players.length === 0) {
      console.log("No players found in game:", record.game_id);

      return new Response(JSON.stringify({ success: true, message: "No players" }));
    }

    const playerIds = players.map(p => p.user_id);

    // 5. Get subscriptions for these players
    const { data: subscriptions, error: subError } = await supabase
      .from('push_subscriptions')
      .select('endpoint, p256dh, auth, player_id')
      .in('player_id', playerIds);

    if (subError) throw subError;
    
    if (!subscriptions || subscriptions.length === 0) {
      console.log("No active push subscriptions for players in game:", record.game_id);
      
      return new Response(JSON.stringify({ success: true, message: "No subscriptions" }));
    }

    console.log(`Sending push to ${subscriptions.length} devices...`);

    // 6. Send notifications
    const pushPromises = subscriptions.map(async (sub) => {
      try {
        await WebPush.sendNotification(
          {
            endpoint: sub.endpoint,
            keys: { p256dh: sub.p256dh, auth: sub.auth },
          },
          JSON.stringify({
            title: 'Imposter Words',
            body: record.payload.message || 'The game has started!',
            data: { url: `/game/${record.game_id}` }
          })
        );

        return { success: true, endpoint: sub.endpoint };
      }
      catch (err: any) {
        if (err.statusCode === 410 || err.statusCode === 404) {
          console.log(`Removing expired subscription: ${sub.endpoint}`);

          await supabase
            .from('push_subscriptions')
            .delete()
            .eq('endpoint', sub.endpoint);
        }

        return { success: false, endpoint: sub.endpoint, error: err.message };
      }
    });

    const results = await Promise.all(pushPromises);

    console.log("Push results:", JSON.stringify(results));

    // 7. Mark outbox item as processed
    const { error: updateError } = await supabase
      .from('notification_outbox')
      .update({ processed_at: new Date().toISOString() })
      .eq('id', record.id);

    if (updateError) throw updateError;

    return new Response(
      JSON.stringify({ success:true, results }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  }
  catch (err: any) {
    console.error("Critical error in Edge Function:", err.message);

    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});