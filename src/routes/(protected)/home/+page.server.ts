import type { PageServerLoad } from './$types';


/**
 * Page load function for the home route.
 *
 * User data (nickname, email, id) is inherited from the parent
 * `(protected)/+layout.server.ts` load and automatically merged
 * into `data` in the `.svelte` file — no need to re-fetch it here.
 *
 */
export const load: PageServerLoad = async () => { return {} };