import { redirect, error as svelteError } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

type Player = { user_id: string; nickname: string };


/**
 * Verifies that the current user belongs to the requested ranked game.
 * 
 * @param gameId - The UUID of the ranked game.
 * @param userId - The authenticated user's UUID.
 * @param locals - SvelteKit locals containing the Supabase client.
 * @returns `true` if the user is a member of the game lobby.
 * @throws {Error} 500 if the membership query fails unexpectedly.
 */

async function ensureMembership(
    gameId: string,
    userId: string,
    locals: App.Locals
): Promise<boolean> {
    const { data, error } = await locals.supabase
        .from('ranked_game_players')
        .select('user_id')
        .eq('game_id', gameId)
        .eq('user_id', userId)
        .maybeSingle();

    if (error) throw svelteError(500, 'Could not validate lobby membership.');

    return !!data;
}

/**
 * Fetches all players in a game with their nicknames.
 *
 * @param gameId - The UUID of the ranked game.
 * @param locals - SvelteKit locals containing the Supabase client.
 * @returns Array of players with their user IDs and nicknames.
 * @throws {Error} 500 if the database query fails.
 */
async function getNicknames(gameId: string, locals: App.Locals): Promise<Player[]> {
    const { data, error } = await locals.supabase
            .from('ranked_game_players')
            .select('user_id, players!inner(id, nickname)')
            .eq('game_id', gameId);

    if (error || !data) throw svelteError(500, 'Could not load lobby players.');

    return data.map(row => ({
        user_id: row.user_id,
        nickname: row.players.nickname
    }));
}


/**
 * Load function for the ranked game lobby page.
 *
 * Fetches the current list of players in the lobby so the page can display
 * them immediately on first render, before any Realtime updates arrive.
 *
 * @throws {redirect} 303 to `/login` if the user is not authenticated.
 * @throws {redirect} 303 to `/home` if the user does not belong to this lobby.
 * 
 * @returns `gameId` — the UUID of the lobby from the URL.
 * @returns `players` — array of `{ user_id, nickname }` for each
 *          player currently in the game.
 */
export const load: PageServerLoad = async ({ params, locals, parent }) => {
    const { userId } = await parent();
    if (!userId) throw redirect(303, '/login');
    
    const { gameId } = params;  // UUID from the URL

    const isMember = await ensureMembership(gameId, userId, locals);
    if (!isMember) throw redirect(303, '/home');

    const players = await getNicknames(gameId, locals);

    return { gameId, players };
};