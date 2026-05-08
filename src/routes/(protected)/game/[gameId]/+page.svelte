<script lang='ts'>
    // ── Imports ────────────────────────────────────────────────────────────────────────    
    import { untrack, onMount } from 'svelte';
    import { enhance } from '$app/forms';
    import { startHeartbeat } from '$lib/utils/heartbeat';
    import { supabase } from '$lib/supabase';
    import { dev } from '$app/environment';
    import { goto } from '$app/navigation';

    import { BottomSheet } from 'm3-svelte';

    import type { PageData, ActionData } from './$types';
    import type { Database } from '$lib/types/supabase';

    // ── Types ──────────────────────────────────────────────────────────────────────────
    type Player = { user_id: string; nickname: string; };
    type GamePhase = Database['public']['Enums']['game_phase'];
    type Sheet = { type: 'chat' } | { type: 'words'; userId: string } | null;
    type ChatMessage = { nickname: string; text: string; };
    type WordEntry = { round: number; word: string; };
    type Role = 'spy' | 'civilian' | 'imposter';

    // ── Props ──────────────────────────────────────────────────────────────────────────
    const { data, form }: { data: PageData, form: ActionData} = $props();

    // ── Mutable state ──────────────────────────────────────────────────────────────────
    let players = $state<Player[]>(untrack(() => data.players ?? []));
    let activeId = $state<string | null>(untrack(() => data.game.active_player_id));
    let deadline = $state<Date | null>(untrack(() => (
        data.game.phase_deadline
        ? new Date(data.game.phase_deadline)
        : null
    )));
    let progress = $state(1); // 1 = full bar, 0 = empty
    let wordInput = $state<string>('');  
    let phase = $state<GamePhase>(untrack(() => data.game.phase));
    let round = $state<number>(untrack(() => data.game.round_number));
    let eliminatedRole = $state<Role | null>(null);
    let eliminatedNickname = $state<string | null>(null);
    let winner = $state<Role | null>(null);
    
    // Voting states
    let votedFor = $state<string | null> (null);
    let voteCounts = $state<Record<string, number>>(({}));
    let sheet = $state<Sheet>(null);

    // Chat states
    let messages = $state<ChatMessage[]>([]);
    let chatInput = $state<string>('');

    // Words state
    let wordHistory = $state<Record<string, WordEntry[]>>({});

    // Channel
    let channel: ReturnType<typeof supabase.channel> | null = $state(null);

    // ── Derived ────────────────────────────────────────────────────────────────────────
    const isMyTurn = $derived(activeId === data.userId && activeId !== null);
    const activeNick = $derived(players.find(p => p.user_id === activeId)?.nickname ?? '...');
    const eliminated = $derived(players.every(p => p.user_id !== data.userId));

    // ── Effects (game end) ─────────────────────────────────────────────────────────────
    // game ended during results phase -> wait for timer, then redirect
    $effect(() => {
        if (phase === 'results' && progress === 0 && winner !== null) {
            goto(`/game/${data.gameId}/end?winner=${winner}`);
        }
    });

    // game ended during any other phase -> redirect immediately
    $effect(() => {
        if (winner !== null && phase !== 'results') {
            goto(`/game/${data.gameId}/end?winner=${winner}`);
        }
    });

    // ── Timer ──────────────────────────────────────────────────────────────────────────
    function updateProgress() {
        if (!deadline) {
            progress = 0;
            return;
        }

        const durations = {
            'voting': 60_000,
            'word_input': 15_000,
            'results': 10_000,
            'reveal': 5_000
        };
   
        const remaining = deadline.getTime() - Date.now();
        progress = Math.max(0, Math.min(1, remaining / durations[phase]));
    }

    // ── Chat Helpers ───────────────────────────────────────────────────────────────────
    function sendMessage() {
        // guard: sent before onMount ran, shouldn't happen
        if (!channel) return;
        
        const text = chatInput.trim();
        if (!text ) return;

        // guard: sent outside voting phase, shouldn't happen
        if (phase !== 'voting') {
            chatInput = '';
            return;
        }

        const msg: ChatMessage = { nickname: data.userNickname, text: text };

        channel.send({ type: 'broadcast', event: 'chat', payload: msg });

        // record own's message
        messages = [...messages, msg];

        // clear input
        chatInput = '';
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────────────
    onMount(() => {
        if (dev) {
            supabase.auth.getSession().then(r => console.log('session:', r.data.session));
        }
        
        // Timer interval
        const timerInterval = setInterval(updateProgress, 100);
        updateProgress();

        // Heartbeat
        const stopHeartbeat = startHeartbeat(data.gameId);

        // Realtime
        channel = supabase.channel(`game:${data.gameId}`)
            // turn/phase/status changed
            .on('postgres_changes', {
                event: 'UPDATE',
                schema: 'public',
                table: 'ranked_games',
                filter: `id=eq.${data.gameId}`
            },
            (payload) => {
                const updatedGame = payload.new;
                activeId = updatedGame.active_player_id ?? null;
                phase = updatedGame.phase;
                deadline = updatedGame.phase_deadline
                    ? new Date(updatedGame.phase_deadline)
                    : null;
                wordInput = '';
                round = updatedGame.round_number;
                eliminatedRole = updatedGame.eliminated_role;

                // remove the eliminated player from the local list
                if (
                    updatedGame.phase === 'results' &&
                    updatedGame.active_player_id !== null
                ) {
                    const found = players.find(p =>
                        p.user_id === updatedGame.active_player_id
                    );

                    // only update when player is in the list
                    // (first event in case of game end)
                    if (found) {
                        eliminatedNickname = found?.nickname ?? '?';

                        players = players.filter((p) =>
                            p.user_id !== updatedGame.active_player_id
                        );
                    }
                }

                // if the game ends store the winner
                if (updatedGame.status === 'finished') winner = updatedGame.winner;

                // when the phase changes (to any state) votes must be reset
                votedFor = null;
                voteCounts = {};

                // close open bottom sheets
                sheet = null;

                updateProgress();
            })

            // player leaves
            .on('postgres_changes', {
                event: 'DELETE',
                schema: 'public',
                table: 'ranked_game_players',
                filter: `game_id=eq.${data.gameId}`
            },
            (payload) => {
                players = players.filter(p => p.user_id !== payload.old.user_id);

                // When a player leaves, the voting phase resets
                votedFor = null;
                voteCounts = {};
            })

            // word submitted
            .on('postgres_changes', {
                event: 'INSERT',
                schema: 'public',
                table: 'game_rounds',
                filter: `game_id=eq.${data.gameId}`
            }, (payload) => {
                const newRow = payload.new;
                const player = players.find(p => p.user_id === newRow.player_id);
                
                // guard: player not found, shouldn't happen
                if (!player) return;

                const round = newRow.round_number;
                const word = newRow.submitted_word !== null
                    ? newRow.submitted_word
                    : 'NOT SUBMITTED';

                const newEntry: WordEntry = { round, word }; 

                // add new word record
                wordHistory[player.user_id] = [
                    ...(wordHistory[player.user_id] ?? []),
                    newEntry
                ];
            })

            // new vote
            // (game_rounds has REPLICA IDENTITY FULL on, so payload.old is meaningful)
            .on('postgres_changes', {
                event: 'UPDATE',
                schema: 'public',
                table: 'game_rounds',
                filter: `game_id=eq.${data.gameId}`
            },
            (payload) => {
                const updatedRow = payload.new;

                // skip updates that aren't vote-related or are not from the current round
                if (
                    !updatedRow.voted ||
                    updatedRow.target_player_id === undefined ||
                    updatedRow.round_number !== round
                ) {
                    return;
                }

                const previousRow = payload.old;
                const newTarget: string = updatedRow.target_player_id === null
                    ? 'skip'
                    : updatedRow.target_player_id;

                // if the player had already voted, delete the old vote
                if (previousRow.voted && previousRow.target_player_id) {
                    voteCounts[previousRow.target_player_id] = Math.max(
                        0,
                        (voteCounts[previousRow.target_player_id] ?? 0) - 1
                    );
                }

                // add the new vote
                voteCounts[newTarget] = (voteCounts[newTarget] ?? 0) + 1;
            })

            // chat
            .on('broadcast', { event: 'chat' }, (payload) => {
                messages = [...messages, payload.payload as ChatMessage];
            })

            .subscribe();
        
        if (dev) {
            channel.on('system', {}, (payload) => {
                console.log('system message:', payload);
            });
        }

        return () => {
            clearInterval(timerInterval);
            supabase.removeChannel(channel!); // channel is surely defined here
            stopHeartbeat();
        }
    });
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <!-- Timer Bar -->
    <div class="timerTrack">
        <div class = "timerBar" style = 'width: {progress * 100}%'></div>
    </div>
    
    {#if phase === 'word_input'}
        <!-- Active Player -->
        <p class = 'turnLabel'>
            {#if isMyTurn}
                Your Turn
            {:else}
                {activeNick}'s turn
            {/if}
        </p>

        <!-- Word -->
        {#if data.word}
            <p class = 'wordLabel'>
                Your word: <strong> {data.word} </strong>
            </p>
        {:else}
            <p class = 'wordLabel'>
                You are the <strong> Spy </strong> - no word assigned.
            </p>
        {/if}

        <!-- Word Input only shown on owns turn -->
        {#if isMyTurn}
            <form
                method = 'POST'
                action = '?/submitWord'
                use:enhance = { () => {
                    return ({ update }) => update({ reset: false });
                }}
            >
                <input type = 'hidden' name = 'assignedWord' value = {data.word ?? ''} />
                <input
                    type = 'text'
                    name = 'word'
                    bind:value={wordInput}
                    placeholder = 'Enter a word...'
                    autocomplete = 'off'
                    maxlength = {50}
                />

                {#if form?.error}
                    <p class = 'error'>{form.error}</p>
                {/if}

                <button type = 'submit' disabled = {!wordInput.trim()}>
                    Submit Word
                </button>
            </form>
        {/if}
    {:else if phase === 'voting'}
        <div class = 'votingWrapper'>
            <!-- Player Grid -->
            <div class = 'playerGrid'>
                {#each players as player}
                    {@const isVoted = votedFor === player.user_id}
                    {@const isMe = player.user_id === data.userId}

                    <div class = 'playerCardWrapper'>
                        <form 
                            method = 'POST'
                            action = '?/castVote'
                            style = 'display: contents'
                            use:enhance = {() => {
                                votedFor = player.user_id;
                                return ({ update }) => update(
                                    { reset: false, invalidateAll: false }
                                );
                            }}
                        >
                            <input
                                type = 'hidden'
                                name = 'targetId'
                                value = { player.user_id }
                            />
                            
                            <button
                                class = 'playerCard'
                                type = 'submit'
                                class:voted = { isVoted }
                                class:dimmed = { (votedFor !== null && !isVoted) || isMe }
                                class:isMe
                                disabled = { isMe || eliminated }
                            >
                                <span class = 'voteBadge'>
                                    { voteCounts[player.user_id] ?? 0 }
                                </span>
        
                                <div class = 'avatar'>
                                    { player.nickname.slice(0, 1).toUpperCase() }
                                </div>
        
                                <span class = 'playerNick'>
                                    { player.nickname }
                                </span>
        
                                {#if isMe}
                                    <span class = 'youLabel'> You </span>
                                {/if}

                            
                            </button>
                        </form>

                        <button
                            class = 'wordHistoryButton'
                            type = 'button'
                            onclick = { () => {
                                sheet = { type: 'words', userId: player.user_id };
                            }}
                        >
                            📋
                        </button>
                    </div>
                {/each}

                <!-- Skip Vote -->
                <form
                    method = 'POST'
                    action = '?/castVote'
                    style = 'display: contents'
                    use:enhance = {() => {
                        votedFor = 'skip';
                        return ({ update }) => update({ reset: false });
                    }}
                >
                    <input type = 'hidden' name = 'targetId' value = 'skip' />
                    
                    <button
                        class = 'playerCard'
                        type = 'submit'
                        class:voted = { votedFor === 'skip'}
                        class:dimmed = { votedFor !== null && votedFor !== 'skip' }
                        disabled = { eliminated }
                    >
                        <span class = 'voteBadge'>
                            { voteCounts['skip'] ?? 0 }
                        </span>

                        <span class = 'playerNick'>
                            Skip
                        </span>
                    </button>
                </form>
            </div>

            <!-- FAB Buttons -->
            <div class = 'fabs'>
                <button
                    class = 'fab'
                    class:fabActive = {sheet?.type === 'chat'}
                    onclick = {
                        () => sheet = sheet?.type === 'chat' ? null : { type: 'chat' }
                    }
                    aria-label = 'Chat'
                >
                    💬
                </button>
            </div>
        </div>
    {:else if phase === 'reveal'}
        {@const revealWords = wordHistory[activeId ?? ''] ?? []}
        {@const revealEntry = revealWords.find(e => e.round === round)}
        {@const revealPlayer = players.find(p => p.user_id === activeId)}

        {#if revealEntry && revealEntry.word !== 'NOT SUBMITTED'}
            <p class = 'revealNick'> { revealPlayer?.nickname ?? '?' } said: </p>
            <p class = 'revealWord'> { revealEntry.word } </p>
        {:else}
            <p class = 'revealNick'>
                { revealPlayer?.nickname ?? '?' } didn't say anything.
            </p>
        {/if}
    {:else if phase === 'results'}
        <div class = 'resultsWrapper'>
            {#if activeId !== null}
                <p class = 'resultsLabel'> Eliminated </p>

                <div class = 'eliminatedAvatar'>
                    { (eliminatedNickname ?? '?').slice(0, 1).toUpperCase() }
                </div>
                
                <p class = 'eliminatedNick'> { eliminatedNickname } </p>
                <p class = 'eliminatedRole'> { eliminatedRole } </p>
            {:else}
                <p class = 'resultsLabel'> No one was eliminated </p>
                <p class = 'resultsHint'> The vote was skipped. </p>
            {/if}
        </div>
    {/if}
</div>

<!-- Bottom Sheet (custom styles are in app.css) -->
{#if sheet !== null}
    <BottomSheet close={() => (sheet = null)}>
        {#if sheet.type === 'chat'}
            <h3 class = 'sheetTitle'> Chat </h3>

            <div class = 'chatMessages'>
                {#each messages as msg}
                    <div
                        class = 'chatMsg'
                        class:mine = {msg.nickname === data.userNickname}
                    >
                        <span class = 'chatNick'> {msg.nickname} </span>
                        <span class = 'chatText'> {msg.text} </span>
                    </div>
                {/each}

                {#if messages.length === 0}
                    <p class = 'emptyHint'> No messages yet. Say something! </p>
                {/if}
            </div>

            {#if !eliminated}
                <div class = 'chatInputRow'>
                    <input
                        type = 'text'
                        bind:value={chatInput}
                        placeholder = 'Say something...'
                        maxlength = {200}
                        onkeydown = {(e) => e.key === 'Enter' && sendMessage()}
                    />

                    <button onclick = {sendMessage} disabled = {!chatInput.trim()}>
                        Send
                    </button>
                </div>
            {/if}
        {:else if sheet.type === 'words'}
            {@const wordsSheet = sheet as { type: 'words'; userId: string }}
            {@const sheetPlayer = players.find(p => p.user_id === wordsSheet.userId)}
            <h3 class = 'sheetTitle'>
                { sheetPlayer?.nickname ?? '?' }'s submitted Words
            </h3>

            <div class = 'wordList'>
                {#each (wordHistory[wordsSheet.userId] ?? []) as entry}
                    <div class = 'wordEntry'>
                        <span class = 'wordRound'> Round {entry.round} </span>
                        <span class = 'wordBubble'> {entry.word} </span>
                    </div>
                {/each}

                {#if (wordHistory[wordsSheet.userId] ?? []).length === 0}
                    <p class = 'emptyHint'> No words submitted yet. </p>
                {/if}
            </div>
        {/if}
    </BottomSheet>
{/if}


<style>
    /* ── Timer ──────────────────────────────────────────────────────────────────────── */
    .timerTrack {
        position: fixed;
        top: 0; left: 0;
        width: 100%; height: 6px;
        background: color-mix(in oklab, currentColor 15%, transparent);
        z-index: 100;
    }
    .timerBar {
        height: 100%;
        background: var(--color-primary, teal);
        transition: width 100ms linear;
    }

    /* ── Word Input Phase ───────────────────────────────────────────────────────────── */
    .wrapper {
        width: 100%; height: 100%;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 1rem;
    }
    .turnLabel  { font-size: 1.25rem; font-weight: 600; }
    .wordLabel  { font-size: 0.95rem; color: var(--color-text-muted, gray); }

    form {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.5rem;
    }
    input[type='text'] {
        padding: 0.5rem 1rem;
        border: 1px solid var(--color-border, #ccc);
        border-radius: 0.5rem;
        font-size: 1rem;
        width: 260px;
    }
    button[type='submit'] {
        padding: 0.5rem 1.5rem;
        background: var(--color-primary, teal);
        color: white;
        border-radius: 0.5rem;
        font-size: 1rem;
        cursor: pointer;
    }
    button[type='submit']:disabled {
        opacity: 0.4;
        cursor: not-allowed;
    }
    .error { color: var(--color-error, red); font-size: 0.875rem; }

    /* ── Reveal Phase ───────────────────────────────────────────────────────────────── */
    .revealNick {
        font-size: 1rem;
        color: var(--color-text-muted, gray);
    }
    .revealWord {
        font-size: 2rem;
        font-weight: 700;
    }

    /* ── Voting Phase ───────────────────────────────────────────────────────────────── */
    .votingWrapper {
        width: 100%; height: 100%;
        display: flex;
        flex-direction: column;
        align-items: center;
        padding: 1.5rem 1rem 1rem;
        box-sizing: border-box;
    }

    /* Player Grid */
    .playerGrid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 0.75rem;
        width: 100%;
        max-width: 400px;
    }

    .playerCardWrapper {
        position: relative;
    }

    .wordHistoryButton {
        position: absolute;
        bottom: 0.4rem; left: 0.5rem;
        font-size: 0.9rem;
        background: none;
        border: none;
        cursor: pointer;
        padding: 0;
        line-height: 1;
        z-index: 1;
    }
    
    .playerCard {
        position: relative;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.4rem;
        padding: 1rem 0.5rem;
        background: var(--color-surface, #1e1e2e);
        border: 2px solid var(--color-border, #333);
        border-radius: 1rem;
        cursor: pointer;
        transition: border-color 200ms, opacity 200ms, transform 100ms;
    }
    .playerCard:active { transform: scale(0.97); }
    .playerCard.voted  { border-color: var(--color-primary, teal); }
    .playerCard.dimmed { opacity: 0.4; }
    .playerCard.isMe   { cursor: default; }
    .playerCard:disabled { cursor: not-allowed; }

    .voteBadge {
        position: absolute;
        top: 0.4rem; right: 0.5rem;
        background: var(--color-warning, #f0b429);
        color: #111;
        font-size: 0.75rem;
        font-weight: 700;
        border-radius: 999px;
        min-width: 1.4rem;
        height: 1.4rem;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 0 0.3rem;
    }
    .avatar {
        width: 3rem; height: 3rem;
        border-radius: 50%;
        background: var(--color-primary, teal);
        color: white;
        font-size: 1.4rem;
        font-weight: 700;
        display: flex;
        align-items: center;
        justify-content: center;
    }
    .playerNick { font-size: 0.85rem; font-weight: 600; }
    .youLabel {
        font-size: 0.7rem;
        color: var(--color-text-muted, gray);
    }

    /* FABs */
    .fabs {
        position: fixed;
        bottom: 1.5rem; right: 1.25rem;
        display: flex;
        flex-direction: column;
        gap: 0.6rem;
        z-index: 50;
    }
    .fab {
        width: 3rem; height: 3rem;
        border-radius: 50%;
        background: var(--color-surface, #1e1e2e);
        border: 1.5px solid var(--color-border, #333);
        font-size: 1.3rem;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        transition: background 150ms, border-color 150ms;
        box-shadow: 0 2px 8px rgba(0,0,0,0.4);
    }
    .fab.fabActive {
        background: var(--color-primary, teal);
        border-color: var(--color-primary, teal);
    }

    /* Bottom Sheet */
    .sheetTitle {
        font-size: 1rem;
        font-weight: 600;
        margin: 0 0 0.75rem;
        flex-shrink: 0;
    }

    /* Chat */
    .chatMessages {
        flex: 1;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        gap: 0.4rem;
        margin-bottom: 0.75rem;
    }
    .chatMsg {
        display: flex;
        flex-direction: column;
        max-width: 80%;
        align-self: flex-start;
    }
    .chatMsg.mine { align-self: flex-end; }
    .chatNick { font-size: 0.7rem; color: var(--color-text-muted, gray); margin-bottom: 2px; }
    .chatText {
        background: var(--color-border, #2a2a3e);
        padding: 0.4rem 0.75rem;
        border-radius: 1rem;
        font-size: 0.9rem;
    }
    .chatMsg.mine .chatText {
        background: var(--color-primary, teal);
        color: white;
    }
    .chatInputRow {
        display: flex;
        gap: 0.5rem;
        flex-shrink: 0;
    }
    .chatInputRow input {
        flex: 1;
        padding: 0.5rem 0.75rem;
        border: 1px solid var(--color-border, #ccc);
        border-radius: 0.5rem;
        font-size: 0.9rem;
        background: var(--color-bg, #111);
        color: var(--color-text, white);
    }
    .chatInputRow button {
        padding: 0.5rem 1rem;
        background: var(--color-primary, teal);
        color: white;
        border-radius: 0.5rem;
        font-size: 0.9rem;
        cursor: pointer;
    }
    .chatInputRow button:disabled { opacity: 0.4; cursor: not-allowed; }

    /* Word List */
    .wordList {
        flex: 1;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        gap: 0.6rem;
    }
    .wordEntry {
        display: flex;
        align-items: center;
        gap: 0.75rem;
    }
    .wordRound {
        font-size: 0.8rem;
        font-weight: 600;
        min-width: 80px;
        color: var(--color-text-muted, gray);
    }
    .wordBubble {
        background: var(--color-border, #2a2a3e);
        padding: 0.35rem 0.75rem;
        border-radius: 0.75rem;
        font-size: 0.9rem;
    }

    .emptyHint {
        font-size: 0.85rem;
        color: var(--color-text-muted, gray);
        text-align: center;
        margin-top: 1rem;
    }

    /* ── Results Phase ─────────────────────────────────────────────────────────────── */
    .resultsWrapper {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.75rem;
        height: 100%;
    }

    .resultsLabel {
        font-size: 0.9rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--color-text-muted, gray);
    }

    .eliminatedAvatar {
        width: 5rem; height: 5rem;
        border-radius: 50%;
        background: var(--color-error, #a12c7b);
        color: white;
        font-size: 2.2rem;
        font-weight: 700;
        display: flex;
        align-items: center;
        justify-content: center;
    }

    .eliminatedNick {
        font-size: 1.4rem;
        font-weight: 700;
    }

    .resultsHint {
        font-size: 0.85rem;
        color: var(--color-text-muted, gray);
    }
</style>