import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

type PushSubscriptionPayload = {
	endpoint?: unknown;
	p256dh?: unknown;
	auth?: unknown;
	userAgent?: unknown;
};

/**
 * Stores or refreshes the current authenticated player's Web Push subscription.
 *
 * The endpoint expects a JSON body containing:
 * - `endpoint`: the unique Push Service endpoint URL
 * - `p256dh`: the client public encryption key
 * - `auth`: the client authentication secret
 * - `userAgent` (optional): the current browser user agent string
 *
 * If the subscription endpoint already exists, the row is updated and marked active.
 * If the user is not authenticated or the payload is invalid, the request is rejected.
 */
export const POST: RequestHandler = async (
	{ request, locals: { safeGetSession, supabase } }
) => {
	const { user } = await safeGetSession();
	if (!user) return json({ error: 'Unauthorized' }, { status: 401 });

	const body: PushSubscriptionPayload = await request.json();
	const { endpoint, p256dh, auth, userAgent } = body ?? {};

	if (
		typeof endpoint !== 'string' ||
		typeof p256dh !== 'string' ||
		typeof auth !== 'string'
	) {
		return json({ error: 'Invalid payload' }, { status: 400 });
	}

	const { error } = await supabase
		.from('push_subscriptions')
		.upsert(
			{
				player_id: user.id,
				endpoint,
				p256dh,
				auth,
				user_agent: typeof userAgent === 'string' ? userAgent : null,
				last_used_at: new Date().toISOString(),
				is_active: true
			},
			{ onConflict: 'endpoint' } // if same endpoint exists -> replace it
		);

	if (error) return json({ error: error.message }, { status: 500 });

	return json({ ok: true });
};