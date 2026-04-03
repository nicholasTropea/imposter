import type { Actions } from'@sveltejs/kit';
import { fail, redirect } from '@sveltejs/kit';


/**
 * Handles the login form submission.
 *
 * Authenticates an existing user via email and password using Supabase Auth.
 * The session cookie is automatically set by the Supabase server client
 * configured in `hooks.server.ts`.
 *
 * On success, redirects to `/home`.
 * On failure, returns a 400 with the Supabase error message.
 *
 * @throws {redirect} 303 to `/home` on successful login.
 */
export const actions: Actions = {
    login: async ({ request, locals: { supabase } }) => {
        const form = await request.formData();
        const email = form.get('email') as string;
        const password = form.get('password') as string;

        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) return fail(400, { error: error.message });

        redirect(303, '/home');
    }
};