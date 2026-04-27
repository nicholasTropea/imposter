import { redirect } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';


/**
 * Layout load function for all routes under `(protected)`.
 *
 * Runs before any child page load in this group. Validates the session
 * via `safeGetSession() from parent` and redirects unauthenticated users to `/login`.
 *
 * @throws {redirect} 303 to `/login` if the user is not authenticated.
 */
export const load: LayoutServerLoad = async ({ parent }) => {
    const { userId } = await parent();
    if (!userId) redirect(303, '/login');
};