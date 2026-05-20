import 'dotenv/config';
import webpush from 'web-push';
import ws from 'ws';
import { createClient } from '@supabase/supabase-js';

const {
  PUBLIC_SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
  PUBLIC_VAPID_KEY,
  PRIVATE_VAPID_KEY,
  VAPID_SUBJECT,
  PUSH_SUBSCRIPTION_ID
} = process.env;

if (!PUBLIC_SUPABASE_URL) throw new Error('Missing PUBLIC_SUPABASE_URL');
if (!SUPABASE_SERVICE_ROLE_KEY) throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY');
if (!PUBLIC_VAPID_KEY) throw new Error('Missing PUBLIC_VAPID_KEY');
if (!PRIVATE_VAPID_KEY) throw new Error('Missing PRIVATE_VAPID_KEY');
if (!VAPID_SUBJECT) throw new Error('Missing VAPID_SUBJECT');
if (!PUSH_SUBSCRIPTION_ID) throw new Error('Missing PUSH_SUBSCRIPTION_ID');

const supabase = createClient(PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    persistSession: false,
    autoRefreshToken: false
  },
  realtime: {
    transport: ws
  }
});

webpush.setVapidDetails(
  VAPID_SUBJECT,
  PUBLIC_VAPID_KEY,
  PRIVATE_VAPID_KEY
);

const { data, error } = await supabase
  .from('push_subscriptions')
  .select('*')
  .eq('id', PUSH_SUBSCRIPTION_ID)
  .single();

if (error) {
  throw new Error(`Failed to load subscription: ${error.message}`);
}

const subscription =
  data.subscription ??
  {
    endpoint: data.endpoint,
    keys: {
      p256dh: data.p256dh,
      auth: data.auth
    }
  };

const payload = JSON.stringify({
  title: 'Game invite',
  body: 'Tap to open local settings.',
  data: {
    url: '/local_game/settings'
  }
});

try {
  const response = await webpush.sendNotification(subscription, payload);
  console.log('Push sent successfully');
  console.log('Status code:', response.statusCode);
  console.log('Headers:', response.headers);
} catch (err) {
  console.error('Push failed');

  if (err.statusCode) console.error('Status code:', err.statusCode);
  if (err.body) console.error('Body:', err.body);

  if (err.statusCode === 404 || err.statusCode === 410) {
    console.error('Subscription is no longer valid. You should delete it from the DB.');
  }

  throw err;
}