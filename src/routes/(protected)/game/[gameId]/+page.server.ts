import { redirect, fail } from '@sveltejs/kit';

import type { PageServerLoad, Actions } from './$types';
import type { CastVoteArgs } from '$lib/types/overrides';

type Player = { user_id: string; nickname: string };


/**
 * Fetches a ranked game by its ID.
 *
 * @param gameId - The UUID of the ranked game.
 * @param locals - SvelteKit locals containing the Supabase client.
 * @returns The ranked game row.
 * @throws If the game is not found or the query fails.
 */
async function getGame(gameId: string, locals: App.Locals) {
    const { data, error } = await locals.supabase
        .from('ranked_games')
        .select('*')
        .eq('id', gameId)
        .single();

    if (error) throw error;
    return data;
}


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
 * Fetches the role and word assigned to the current player in a game.
 * Word is null if the player is the spy.
 *
 * @param gameId - The UUID of the ranked game.
 * @param locals - SvelteKit locals containing the Supabase client.
 * @param userId - The UUID of the current authenticated user.
 * @returns The player's assigned role and word.
 * @throws If the database query fails.
 */
async function getSelfData(
    gameId: string,
    locals: App.Locals,
    userId: string
): Promise<{ role: string | null; word: string | null }> {
  const { data, error } = await locals.supabase
    .from('ranked_game_players')
    .select('role, word')
    .eq('game_id', gameId)
    .eq('user_id', userId)
    .single();

  if (error) throw error;

  return { role: data.role, word: data.word };
}


/**
 * Load function for the ranked game page.
 *
 * Fetches all data needed for the initial render: the game state, full player
 * list with nicknames, the current player's role and word, and the latest round.
 *
 * Runs the player list, self data, and round queries in parallel after the
 * initial game fetch, to minimize server response time.
 *
 * @throws {redirect} 303 to `/login` if the user is not authenticated.
 * @throws {redirect} 307 to `/game_lobby/[gameId]` if the game is not in progress.
 *
 * @returns `gameId`      — UUID of the game from the URL params.
 * @returns `game`        — Full game row including `turn_order` and `status`.
 * @returns `players`     — Array of `{ user_id, nickname }` for all players.
 * @returns `currentRound`— Latest round row, or null if none started yet.
 * @returns `role`        — The current player's role (e.g. `'citizen'`, `'spy'`).
 * @returns `word`        — The current player's secret word, or null if spy.
 */
export const load: PageServerLoad = async ({ params, locals, parent }) => {
    const { userId } = await parent();
    if (!userId) throw redirect(303, '/login');
    
    const { gameId } = params;  // UUID from the URL
    const game = await getGame(gameId, locals);

    if (!game) throw redirect(307, '/home');

    // Redirect to lobby if game isn't running
    if (game.status !== 'in_progress') throw redirect(307, `/game_lobby/${gameId}`);

    const [players, selfInfo] = await Promise.all([
        getNicknames(gameId, locals),
        getSelfData(gameId, locals, userId)
    ]);

    // Redirect to home if user is not part of the game
    if (!players.some(p => p.user_id === userId)) throw redirect(307, '/home');

    return { gameId, game, players, role: selfInfo.role, word: selfInfo.word };
}


export const actions: Actions = {
    submitWord: async ({ request, params, locals: { safeGetSession, supabase } }) => {
        const { user } = await safeGetSession()
        if (!user) throw redirect(303, '/login');

        const { gameId } = params;
        const formData = await request.formData();
        const word = (formData.get('word') as string)?.trim();
        const assignedWord = formData.get('assignedWord') as string | null;

        // Validate turn
        const { data: game } = await supabase
            .from('ranked_games')
            .select('active_player_id, round_number')
            .eq('id', gameId)
            .single();

        if (game?.active_player_id !== user.id) {
            return fail(403, { error: 'Not your turn' });        
        }

        if (!word) return fail(400, { error: 'Word cannot be empty' });

        if (assignedWord && word.toLowerCase() === assignedWord.toLowerCase()) {
            return fail(400, { error: 'You cannot submit your assigned word' });
        }

        const { error } = await supabase
            .from('game_rounds')
            .insert({
                game_id: gameId,
                player_id: user.id,
                round_number: game?.round_number ?? 1,
                submitted_word: word,
                target_player_id: null,
                voted: false
            });

        if (error) return fail(500, { error: 'Failed to submit word' });

        return { success: true };
    },

    castVote: async ({ request, params, locals: { safeGetSession, supabase } }) => {
        const { user } = await safeGetSession();
        if (!user) throw redirect(303, '/login');

        const { gameId } = params;
        const formData = await request.formData();
        let targetId: string | null = formData.get('targetId') as string;
        if (targetId === 'skip') targetId = null; // Skip vote

        if (user.id === targetId) {
            return fail(400, { error: 'You cannot vote for yourself' });
        }

        const { error } = await (supabase.rpc as any)('cast_vote', {
            p_game_id: gameId,
            p_voter_id: user.id,
            p_target_id: targetId
        } satisfies CastVoteArgs); // p_target_id can also be NULL

        if (error) return fail(500, { error: error.message });

        return { success: true };
    }
};