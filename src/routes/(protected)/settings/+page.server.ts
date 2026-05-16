import { fail, redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { Actions } from '@sveltejs/kit';

type Theme = 'light' | 'dark';

/**
 * Page load function for the settings route.
 *
 * Fetches the current user's settings row from `public.settings`.
 * The settings row is guaranteed to exist since it is created automatically
 * by the `on_auth_user_created` trigger when the user signs up.
 *
 * Authentication is already enforced by the parent `(protected)/+layout.server.ts`,
 * but `safeGetSession()` is called again here to obtain the user id
 * needed for the DB query.
 *
 * @throws {redirect} 303 to `/login` if the session is invalid or expired.
 */
export const load: PageServerLoad = async ({ locals: { supabase }, parent }) => {
	const { userId } = await parent();

	if (!userId) throw redirect(303, '/login');

	const { data: settings, error } = await supabase
		.from('settings')
		.select('*')
		.eq('user_id', userId)
		.single();

	if (error || !settings) throw redirect(303, '/home');

	return { settings };
};


export const actions: Actions = {
    /**
     * Persists the current user's settings to `public.settings`.
     *
     * Uses `upsert` to handle the rare edge case where the settings row does
     * not yet exist, though under normal circumstances the row is created
     * automatically at signup by the `on_auth_user_created` database trigger.
     *
     * The user identity is always resolved server-side via `safeGetSession()`
     * rather than trusting a `user_id` from the request body, preventing
     * a malicious client from overwriting another user's settings.
     *
     * Called automatically 500ms after any setting change via a debounced
     * `fetch` in the client — no save button required.
     *
     * @param request - The incoming POST request containing form-encoded settings.
     * @param locals.supabase - The request-scoped Supabase server client.
     * @param locals.safeGetSession - Verified session getter (JWT + `getUser()`).
     *
     * @returns {fail(401)} If the session is missing or invalid.
     */
	saveSettings: async ({ request, locals: { supabase, safeGetSession } }) => {
		const { user } = await safeGetSession();
		if (!user) return fail(401, { error: 'Unauthorized' });

		const form = await request.formData();

		const rawTheme = form.get('theme');
		const masterVolume = Number(form.get('master_volume'));
		const musicVolume = Number(form.get('music_volume'));
		const soundEffects = form.get('sound_effects') === 'true';
		const gameInvites = form.get('game_invites') === 'true';
		const dailyRewards = form.get('daily_rewards') === 'true';

		if (rawTheme !== 'dark' && rawTheme !== 'light') {
			return fail(400, { error: 'Invalid theme value' });
		}

		const theme: Theme = rawTheme;

		if (!Number.isFinite(masterVolume) || masterVolume < 0 || masterVolume > 100) {
			return fail(400, { error: 'Invalid master volume' });
		}

		if (!Number.isFinite(musicVolume) || musicVolume < 0 || musicVolume > 100) {
			return fail(400, { error: 'Invalid music volume' });
		}

		const payload = {
			user_id: user.id,
			theme,
			master_volume: masterVolume,
			music_volume: musicVolume,
			sound_effects: soundEffects,
			game_invites: gameInvites,
			daily_rewards: dailyRewards
		};

		const { error } = await supabase.from('settings').upsert(payload);

		if (error) {
			return fail(500, { error: 'Could not save settings' });
		}

		return { success: true };
	}
};