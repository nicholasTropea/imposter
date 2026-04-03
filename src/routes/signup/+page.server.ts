import type { Actions } from '@sveltejs/kit';
import { fail, redirect } from '@sveltejs/kit';

/**
 * Handles the signup form submission.
 *
 * Registers a new user with Supabase Auth using email and password,
 * passing the nickname as user metadata. The database trigger
 * `on_auth_user_created` will automatically insert a matching row
 * in `public.profiles` with the user's id and nickname.
 *
 * On success, redirects to `/home`.
 * On failure, returns a 400 with the Supabase error message.
 *
 * @throws {redirect} 303 to `/home` on successful signup.
 *
 */
export const actions: Actions = {
    signup: async ({ request, locals: { supabase } }) => {
        const form = await request.formData();
        const email = form.get('email') as string;
        const password = form.get('password') as string;
        const nickname = form.get('nickname') as string;

        const { error } = await supabase.auth.signUp({
            email,
            password,
            options: {
                data: {
                    nickname
                }
            }
        });
        
        if (error) return fail(400, { error: error.message });

        redirect(303, '/home');
    }
}