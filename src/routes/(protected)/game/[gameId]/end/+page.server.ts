import { error, redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

type Role = 'spy' | 'civilian' | 'imposter';

export const load: PageServerLoad = async (
    { params, url, parent, locals: { supabase } }
) => {
    const { userId } = await parent();
    if (!userId) throw redirect(303, '/login');

    const { gameId } = params;  // UUID from the URL

    const winner = url.searchParams.get('winner') as Role | null;
    if (!winner) error(400, 'Missing winner');

    
    // fetch game data to verify the player belongs to it and check turn_order
    const { data: gameData } = await supabase
        .from('ranked_games')
        .select('turn_order, status')
        .eq('id', gameId)
        .single();

    // guard: game not found or not finished
    if (!gameData || gameData.status !== 'finished') error(403, 'Forbidden');

    // fetch player's role in this game (also proves player participated in the game)
    const { data: playerData } = await supabase
        .from('ranked_game_players')
        .select('role')
        .eq('game_id', gameId)
        .eq('user_id', userId)
        .single();

    if (!playerData) error(403, 'Forbidden');

    // fetch player's current elo
    const { data: playerElo } = await supabase
        .from('players')
        .select('elo')
        .eq('id', userId)
        .single();

    const role = playerData.role as Role;
    const currentElo = playerElo?.elo ?? null;
    if (currentElo === null) error(500, 'Inconsistent state.');

    // reconstruct elo delta
    const won = role === winner;
    const survived = gameData.turn_order?.includes(userId) ?? false;

    const delta = survived
        ? (won ? 25 : -5) // 25 = won, -5 = survived but lost
        : -10; // eliminated by vote

    return {
        winner,
        role,
        currentElo,
        previousElo: currentElo - delta,
        delta,
        won
    };
};