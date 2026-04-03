import { redirect } from '@sveltejs/kit';
import type { Actions } from '@sveltejs/kit';


/**
 * Logs out the current user by invalidating the session
 * and clearing the Supabase auth cookies.
 *
 * Available on all routes via the action '/logout'.
 *
 * @throws {redirect} 303 to `/login` after successful sign out.
 */
export const actions: Actions = {
    logout: async ({ locals: { supabase } }) => {
        await supabase.auth.signOut()
        redirect(303, '/login')
    }
};