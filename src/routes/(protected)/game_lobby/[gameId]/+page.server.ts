import { redirect } from '@sveltejs/kit';

import type { PageServerLoad } from './$types';

type Player = { user_id: string; nickname: string };


/**
 * Fetches all players in a game with their nicknames.
 *
 * @param gameId - The UUID of the ranked game.
 * @param locals - SvelteKit locals containing the Supabase client.
 * @returns Array of players with their user IDs and nicknames.
 * @throws If the database query fails.
 */
async function getNicknames(gameId: string, locals: App.Locals): Promise<Player[]> {
    const { data, error } = await locals.supabase
            .from('ranked_game_players')
            .select('user_id, players!inner(id, nickname)')
            .eq('game_id', gameId);

    if (error) throw error;

    return data.map(row => ({
        user_id: row.user_id,
        nickname: row.players.nickname
    }))
}


/**
 * Load function for the ranked game lobby page.
 *
 * Fetches the current list of players in the lobby so the page can display
 * them immediately on first render, before any Realtime updates arrive.
 *
 * @throws {redirect} 303 to `/login` if the user is not authenticated.
 *
 * @returns `gameId` — the UUID of the lobby from the URL.
 * @returns `players` — array of `{ user_id, nickname }` for each
 *          player currently in the game.
 */
export const load: PageServerLoad = async ({ params, locals, parent }) => {
    const { userId } = await parent();
    if (!userId) redirect(303, '/login');
    
    const { gameId } = params;  // UUID from the URL

    const players = await getNicknames(gameId, locals);

    return { gameId, players };
}