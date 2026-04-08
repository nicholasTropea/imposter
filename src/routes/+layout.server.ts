import type { LayoutServerLoad } from './$types';

/**
 * Root layout load function — runs on every request, authenticated or not.
 *
 * Resolves the current session and, if the user is authenticated, fetches
 * their theme preference from the database. This makes the theme available
 * to the root layout on all pages — both protected and public — so the
 * correct theme is applied regardless of which route the user is on.
 *
 * Only `theme` is selected (not the full settings row) to keep the query
 * lightweight, since this runs on every single page load.
 *
 * @returns `session` and `user` for auth state, `settings` with the user's
 * theme if authenticated, or `null` if unauthenticated.
 */
export const load: LayoutServerLoad = async ({ locals: { safeGetSession, supabase } }) => {
    const { session, user } = await safeGetSession();

    let settings = null;
    if (user) {
        const { data } = await supabase
            .from('settings')
            .select('theme')
            .eq('user_id', user.id)
            .single();
        
        settings = data;
    }
    
    return { session, user, settings };
};