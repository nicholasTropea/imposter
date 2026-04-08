import { fail, redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { Actions } from '@sveltejs/kit';


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
export const load: PageServerLoad = async ({ locals: { safeGetSession, supabase } }) => {
    const { user } = await safeGetSession();
    if (!user) redirect(303, '/login');

    const { data: settings, error } = await supabase
        .from('settings')
        .select('*')
        .eq('user_id', user.id)
        .single();

    if (error) console.error(error);

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
        if (!user) return fail(401);

        const form = await request.formData();

        await supabase.from('settings').upsert({
            user_id:       user.id,
            theme:         form.get('theme'),
            master_volume: Number(form.get('master_volume')),
            music_volume:  Number(form.get('music_volume')),
            sound_effects: form.get('sound_effects') === 'true',
            game_invites:  form.get('game_invites')  === 'true',
            daily_rewards: form.get('daily_rewards') === 'true',
        });
    }
};