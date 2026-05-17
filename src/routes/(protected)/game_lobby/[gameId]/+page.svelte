<script lang='ts'>
    // ── Imports ────────────────────────────────────────────────────────────────────────    
    import { goto } from '$app/navigation';
    import { onMount, untrack } from 'svelte';
    import { startHeartbeat } from '$lib/utils/heartbeat';
    import { supabase } from '$lib/supabase';
    import { offline } from '$lib/stores/network';
    import { Button } from 'm3-svelte';

    import type {
        RealtimePostgresChangesPayload,
        RealtimeChannel
    } from '@supabase/supabase-js';

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
    let mounted = false;
    let leaving = $state(false);

    // ── Realtime State ─────────────────────────────────────────────────────────────────
    let channel: RealtimeChannel | null = null; 
    let resubscribeTimeout: ReturnType<typeof setTimeout> | null = null;
    let resubscribing = false;
    let destroyed = false;
    let reconnecting = $state(false);
    let connectionMessage = $state<string | null>(null);
    
    // ── Queries ────────────────────────────────────────────────────────────────────────
    async function leaveLobby() {
        if (leaving || destroyed) return;

        leaving = true;
        destroyed = true;

        try {
            await removeLobbyChannel();

            const { error } = await supabase
                .from('ranked_game_players')
                .delete()
                .eq('game_id', data.gameId)
                .eq('user_id', data.userId);

            if (error) {
                console.error('Could not leave lobby:', error);
                leaving = false;
                destroyed = false;
                return;
            }

            goto('/home');
        }
        catch (err) {
            console.error('Could not leave lobby:', err);
            leaving = false;
            destroyed = false;
        }
    }
    
	/**
	 * Verifies that the current client still belongs to this lobby.
	 *
	 * This is especially important after reconnect, because the backend may have
	 * removed the player while heartbeat updates were not reaching the server.
	 * If membership is gone, the user is sent back home.
	 *
	 * @returns `true` if the player still belongs to the lobby, otherwise `false`.
	 */
    async function refreshMembership(): Promise<boolean> {
        if (leaving) return false;
        
        const { data: membership } = await supabase
            .from('ranked_game_players')
            .select('user_id')
            .eq('game_id', data.gameId)
            .eq('user_id', data.userId)
            .maybeSingle();

        if (!membership) {
            goto('/home');
            return false;
        }

        return true;
    }
    
    /**
     * Refetches the full player list for the current lobby.
     * 
     * The query joins `ranked_game_players` with `players` so the UI receives
     * nicknames in addition to the raw player ids. This is used both for realtime
     * updates and reconnect recovery.
     */
    async function refreshPlayers() {
        const { data: updated } = await supabase
            .from('ranked_game_players')
            .select('user_id, players!inner(id, nickname)')
            .eq('game_id', data.gameId);

        if (!updated) return;

        players = updated.map(row => ({
            user_id: row.user_id,
            nickname: row.players.nickname
        }));
    }

	/**
	 * Refetches the current game status.
	 *
	 * This is used as a race-condition guard on mount and again after reconnect,
	 * so the client can still navigate to the game page even if a realtime status
	 * update was missed while the connection was down.
	 */
	async function refreshGameStatus() {
		const { data: game } = await supabase
			.from('ranked_games')
			.select('status')
			.eq('id', data.gameId)
			.single();

		if (game?.status === 'in_progress') {
			goto(`/game/${data.gameId}`);
		}
	}

    // ── Realtime Helpers ───────────────────────────────────────────────────────────────
    /**
     * Clears the pending resubscribe timer, if one exists. 
     */
    function clearResubscribeTimeout() {
        if (resubscribeTimeout) {
            clearTimeout(resubscribeTimeout);
            resubscribeTimeout = null;
        }
    }

    /**
     * Removes the current lobby channel, if one exists. 
     */
    async function removeLobbyChannel() {
        if (!channel) return;

        await supabase.removeChannel(channel);
        channel = null;
    }

    /**
     * Recreates the realtime subscription after channel failure.
     * 
     * Guards against duplicate reconnect attempts and avoids trying to resubscribe
     * while the page is offline or already destroyed.
     */
    async function resubscribeLobbyChannel() {
        if (resubscribing || destroyed || $offline) return;

        resubscribing = true;
        reconnecting = true;
        connectionMessage = 'Reconnecting to lobby...';
        clearResubscribeTimeout();

        await removeLobbyChannel();

        resubscribeTimeout = setTimeout(() => {
            if (destroyed || $offline) {
                resubscribing = false;
                return;
            }

            setupLobbyChannel();
            resubscribing = false;
        }, 1000);
    }

    async function retryNow() {
        if (destroyed) return;

        const stillMember = await refreshMembership();
        if (!stillMember) return;

        await resubscribeLobbyChannel();
    }

    // ── Channel ────────────────────────────────────────────────────────────────────────
	/**
	 * Creates the realtime channel for this lobby.
	 *
	 * The channel listens for:
	 * - player join/leave changes on `ranked_game_players`
	 * - status updates on `ranked_games`
	 *
	 * Player changes trigger a full player refetch because the realtime payload
	 * does not contain the joined nickname from `players`.
	 *
	 * The subscription also listens to channel lifecycle events so it can recover
	 * from disconnects, timeouts, and closed channels.
	 */
	function setupLobbyChannel() {
		channel = supabase
			.channel(`game_lobby:${data.gameId}`)
			.on(
				'postgres_changes',
				{
					event: '*',
					schema: 'public',
					table: 'ranked_game_players',
					filter: `game_id=eq.${data.gameId}`
				},
				async () => {
					const stillMember = await refreshMembership();
					if (!stillMember) return;

					await refreshPlayers();
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
			.subscribe(async (status, err) => {
				if (status === 'SUBSCRIBED') {
                    reconnecting = false;
                    connectionMessage = null;
                    
					const stillMember = await refreshMembership();
					if (!stillMember) return;

					await refreshPlayers();
					await refreshGameStatus();
					return;
				}

				if (
					status === 'CHANNEL_ERROR' ||
					status === 'TIMED_OUT' ||
					status === 'CLOSED'
				) {
					console.error('Lobby realtime channel issue:', status, err);
					await resubscribeLobbyChannel();
				}
			});
	}

    onMount(() => {
        mounted = true;

		const stopHeartbeat = startHeartbeat(data.gameId);

        refreshMembership().then((stillMember) => {
            if (destroyed || !stillMember) return;

            refreshPlayers();
            refreshGameStatus();
            setupLobbyChannel();
        });

		return () => {
			destroyed = true;
            clearResubscribeTimeout();
            removeLobbyChannel();
            stopHeartbeat();
		};
	});

    // ── Reconnect Recovery ─────────────────────────────────────────────────────────────
    /**
	 * When the client comes back online, refetch both the player list and the
	 * game status. Realtime connections can miss events during disconnect windows,
	 * so reconnect recovery should always re-read the latest authoritative state.
	 */
	$effect(() => {
		const isOffline = $offline;
        if (!mounted) return;

		if (isOffline) {
            reconnecting = true;
            connectionMessage = 'You are offline. Trying to reconnect...';
            
            return;
        }

        refreshMembership().then((stillMember) => {
            if (destroyed || !stillMember) return;

            refreshPlayers();
            refreshGameStatus();

            if (!channel && !destroyed) setupLobbyChannel();
        });
	});
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <span> Game: { data.gameId } </span>

    <Button variant = 'text' onclick = { leaveLobby } disabled = { leaving } >
	    { leaving ? 'Leaving...' : 'Leave Lobby' }
    </Button>

    {#if connectionMessage}
        <p class = 'connectionStatus'> { connectionMessage } </p>
    {/if}
        
    {#if reconnecting}
        <div class = 'actions'>
            <Button variant = 'filled' onclick = { retryNow } >
                Retry Now
            </Button>

            <Button variant = 'outlined' onclick = { () => goto('/home') } >
                Back Home
            </Button>
        </div>
    {/if}

    <ul>
        {#each players as player}
            <li> { player.nickname } </li>
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

    .connectionStatus {
        font-size: 0.9rem;
        color: var(--m3c-on-surface-variant);
        text-align: center;
    }

    .actions {
        width: 100%;
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
        max-width: 16rem;
    }

    @media (min-width: 640px) {
        .actions {
            flex-direction: row;
            justify-content: center;
            max-width: none;
        }
    }
</style>