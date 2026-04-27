<script lang='ts'>
    // ── Imports ────────────────────────────────────────────────────────────────────────    
    import { goto } from '$app/navigation';
    import { onMount, untrack } from 'svelte';
    import { startHeartbeat } from '$lib/utils/heartbeat';
    import { supabase } from '$lib/supabase';

    import type { RealtimePostgresChangesPayload } from '@supabase/supabase-js';

    // ── Types ──────────────────────────────────────────────────────────────────────────
    type Player = { user_id: string; nickname: string; };

    // ── Props ──────────────────────────────────────────────────────────────────────────
    const { data } = $props();

    /**
     * Reactive list of players currently in the lobby.
     * Seeded once from server-rendered `data.players` and kept in sync via Realtime.
     * `untrack` prevents `data` from being tracked as a reactive dependency.
     */
    let players = $state<Player[]>(untrack(() => data.players ?? []));

    onMount(() => {
        // Start the heartbeat
        const stopHeartbeat = startHeartbeat(data.gameId);

        // Guard: if the game already started before the subscription was ready
        // Used since the last player wasnt getting redirected because of the
        // race-condition between client and database
        supabase
            .from('ranked_games')
            .select('status')
            .eq('id', data.gameId)
            .single()
            .then(({ data: game }) => {
                if (game?.status === 'in_progress') {
                    goto(`/game/${data.gameId}`);
                }
        });
        
        
        /**
         * Realtime channel scoped to this specific game lobby.
         * Listens for two event streams:
         * 1. Any change on `ranked_game_players` filtered by `game_id`:
         *           refetches player list.
         * 2. UPDATE on `ranked_games` filtered by `id` →:
         *           navigates to game when status becomes `in_progress`.
         */
        const channel = supabase
            .channel(`game_lobby:${data.gameId}`)
            .on(
                'postgres_changes',
                {
                    event: '*',  // INSERT (player joins) or DELETE (player leaves)
                    schema: 'public',
                    table: 'ranked_game_players',
                    filter: `game_id=eq.${data.gameId}`
                },
                () => {
                    /**
                     * Refetch the full player list instead of patching from the payload,
                     * because the payload only contains `ranked_game_players` columns —
                     * not the joined `nickname` from the `players` table.
                     */
                    supabase
                        .from('ranked_game_players')
                        .select('user_id, players!inner(id, nickname)')
                        .eq('game_id', data.gameId)
                        .then(({ data: updated }) => {
                            if (updated) {
                                players = updated.map(row => ({
                                    user_id: row.user_id,
                                    nickname: row.players.nickname
                                }));
                            }
                        });
                }
            )
            .on(
                'postgres_changes',
                {
                    event: 'UPDATE',
                    schema: 'public',
                    table: 'ranked_games',
                    filter: `id=eq.${data.gameId}`
                },
                (payload: RealtimePostgresChangesPayload<{ status: string }>) => {
                    /**
                     * Navigates all players in the lobby to the game page
                     * when the host starts the game and `status` transitions
                     * to `in_progress`.
                     */
                    if (
                        typeof payload.new === 'object' &&
                        payload.new !== null &&
                        'status' in payload.new &&
                        payload.new.status === 'in_progress'
                    ) {
                        goto(`/game/${data.gameId}`);
                    }
                }
            )
            .subscribe();
        
        /** Unsubscribe and clean up the channel when the component is destroyed. */
        return () => {
            supabase.removeChannel(channel);
            stopHeartbeat();
        };
    });
</script>


<!-- HTML -->
<div class='wrapper'>
    <span>Game: {data.gameId}</span>

    <ul>
        {#each players as player}
            <li>{player.nickname}</li>
        {/each}
    </ul>
</div>


<style>
    .wrapper {
        width: 100%;
        height: 100%;

        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 1rem;
    }
</style>