import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';


export const load: PageServerLoad = async ({ locals: { supabase }, parent }) => {
    const { userId } = await parent();
    if (!userId) redirect(303, '/login');

    const [topPlayers, userRankResult, userEloResult] = await Promise.all([
        supabase
            .from('players')
            .select('id, nickname, elo')
            .order('elo', { ascending: false })
            .limit(100),

        supabase.rpc('get_player_rank', { p_user_id: userId }),

        supabase
            .from('players')
            .select('elo')
            .eq('id', userId)
            .single()
    ]);

    const userInTop100 = (topPlayers.data ?? []).some(p => p.id === userId);

    return {
        players: topPlayers.data ?? [],
        userRank: userRankResult.data ?? null,
        userElo: userInTop100 ? null : (userEloResult.data!.elo)
    };
};