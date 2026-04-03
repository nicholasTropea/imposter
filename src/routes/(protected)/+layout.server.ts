import { redirect } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';


/**
 * Layout load function for all routes under `(protected)`.
 *
 * Runs before any child page load in this group. Validates the session
 * via `safeGetSession()` and redirects unauthenticated users to `/login`.
 *
 * Returns the user's basic info, which is automatically merged into `data`
 * in all child `+page.svelte` files — no need to re-fetch the user
 * in individual page load functions.
 *
 * @throws {redirect} 303 to `/login` if the user is not authenticated.
 */
export const load: LayoutServerLoad = async ({ locals: { safeGetSession} }) => {
    const { user } = await safeGetSession();
    if (!user) redirect(303, '/login');

    return {
        nickname: user.user_metadata.nickname,
        email: user.email,
        id: user.id
    };
};