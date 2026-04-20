import type { RequestHandler } from './$types';

/**
 * POST /api/heartbeat
 *
 * Updates the `last_seen` timestamp for the current player in a game,
 * signalling that they are still active. Called every 5 seconds by the
 * client via `sendBeacon`.
 *
 * Players whose `last_seen` falls behind by more than 15 seconds are
 * automatically removed by a `pg_cron` job running on the database.
 *
 * @returns 204 on success.
 * @returns 401 if the user is not authenticated.
 * @returns 500 if the database update fails.
 */
export const POST: RequestHandler = async ({ request, locals }) => {
    const { user } = await locals.safeGetSession();
    if (!user) return new Response(null, { status: 401 });

    const { gameId } = await request.json();

    const { error } = await locals.supabase
        .from('ranked_game_players')
        .update({ last_seen: new Date().toISOString() })
        .eq('game_id', gameId)
        .eq('user_id', user.id);

    if (error) return new Response(null, { status: 500 });

    return new Response(null, { status: 204 });
};