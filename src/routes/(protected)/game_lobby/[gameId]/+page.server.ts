import { redirect } from '@sveltejs/kit';

import type { PageServerLoad } from './$types';

type Player = { user_id: string; nickname: string };

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
    const { user } = await parent();
    if (!user) redirect(303, '/login');
    
    const { gameId } = params;  // UUID from the URL

    // Define the query shape so QueryData can infer the correct types
    const { data, error } = await locals.supabase
            .from('ranked_game_players')
            .select('user_id, players!inner(id, nickname)')
            .eq('game_id', gameId)
            .overrideTypes<Array<{ // Used because TS couldnt infer the correct type
                    user_id: string;
                    players: { id: string; nickname: string };
            }>>();

    if (error) throw error;

    const players: Player[] = data.map(row => ({
        user_id: row.user_id,
        nickname: row.players.nickname
    }))

    return { gameId, players };
}