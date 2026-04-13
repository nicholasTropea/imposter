import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

/**
 * Load function for the ranked game matchmaking page.
 *
 * Retrieves the authenticated user from the parent layout, then calls the
 * `join_or_create_ranked_game` database function to atomically assign the
 * user to an existing waiting game or create a new one if none is available.
 *
 * When the game is found/created, the player gets redirected to the game lobby page.
 *
 * @throws {redirect} 303 to '/login' if the user is not authenticated.
 * @throws {redirect} 303 to '/game_lobby/gameId if a game is found.
 * @throws {error} If the database RPC call fails.
 *
 * @returns The UUID of the ranked game the user has been assigned to.
 */
export const load: PageServerLoad = async ({ locals, parent }) => {
    const { user } = await parent();
    if (!user) redirect(303, '/login');

    const { data: gameId, error } = await locals.supabase
        .rpc('join_or_create_ranked_game', { p_user_id: user.id });

    if (error) throw error;

    // Game found/created
    redirect(303, `/game_lobby/${gameId}`);
}