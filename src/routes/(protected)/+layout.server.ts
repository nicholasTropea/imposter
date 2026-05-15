import { redirect } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';


/**
 * Layout load function for all routes under `(protected)`.
 *
 * Runs before any child page load in this group. Validates the session
 * via `safeGetSession()` and redirects unauthenticated users to `/login`.
 *
 * @throws {redirect} 303 to `/login` if the user is not authenticated.
 */
export const load: LayoutServerLoad = async ({ locals: { safeGetSession, supabase } }) => {
    const { user } = await safeGetSession();
    if (!user) throw redirect(303, '/login');

    const { data: settings } = await supabase
        .from('settings')
        .select('theme')
        .eq('user_id', user.id)
        .single();

    return {
        userId: user.id,
        userEmail: user.email ?? null,
        userNickname: user.user_metadata?.nickname ?? null,
        settings: settings ?? null
    };
};