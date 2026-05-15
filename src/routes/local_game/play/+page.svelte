<script lang='ts'>
    // ── Imports ────────────────────────────────────────────────────────────────────────
    import { untrack } from "svelte";
    import { Button } from "m3-svelte";
    import { goto } from "$app/navigation";

    // ── Props ──────────────────────────────────────────────────────────────────────────
    let { data } = $props();
    
    // ── Types ──────────────────────────────────────────────────────────────────────────
    type Phase = 'role_show' | 'word_input' | 'elimination' | 'results' | 'end';
    type RoleNums = { civilians: number, imposters: number, spies: number };
    type Role = 'spy' | 'imposter' | 'civilian';
    type Pair = { civilian_word: string, imposter_word: string };
    type Player = { nickname: string, role: Role, word: string | null };

    // ── Mutable State ──────────────────────────────────────────────────────────────────
    let players: Player[] = $state(assignRoles(
        untrack(() => data.players!), untrack(() => data.pair!)
    ));
    let phase: Phase = $state<Phase>('role_show');
    let playerIndex: number = $state<number>(0);
    let showRole: boolean = $state<boolean>(false); 
    let votedFor: string | null = $state(null);
    let eliminatedNickname: string | null = $state(null);
    let eliminatedRole: Role | null = $state(null);
    let winner: Role | null = $state<Role | null>(null);

    // ── Constants ──────────────────────────────────────────────────────────────────────
    const SKIP_UUID = crypto.randomUUID();

    const rolePlurals = {
        'spy': 'Spies',
        'imposter': 'Imposters',
        'civilian': 'Civilians'
    };
    
    const roleColors: Record<Role, string> = {
        spy:      'var(--m3c-tertiary)',
        imposter: 'var(--m3c-error)',
        civilian: 'var(--m3c-primary)'
    };

    const roleEmojis: Record<Role, string> = {
        spy: '🕵️', imposter: '🎭', civilian: '👤'
    };

    // ── Auxiliary Functions ────────────────────────────────────────────────────────────
    function increaseIndex(): void {
        playerIndex = (playerIndex + 1) % players.length;
    }

    function calculateRoles(playerCount: number): RoleNums {
        const imposters = Math.max(1, Math.floor(playerCount / 3));
        const spies = Math.max(1, Math.min(Math.floor(playerCount / 4), imposters));
        const civilians = playerCount - imposters - spies;

        return { civilians, imposters, spies };
    }

    function assignRoles(players: string[], pair: Pair): Player[] {
        const { civilians, imposters, spies } = calculateRoles(players.length);

        // Build role pool
        const roles: Role[] = [
            ...Array(civilians).fill('civilian'),
            ...Array(imposters).fill('imposter'),
            ...Array(spies).fill('spy'),
        ];

        // Shuffle roles
        roles.sort(() => Math.random() - 0.5);

        return players.map((nickname, i) => ({
            nickname,
            role: roles[i],
            word: roles[i] === 'imposter' ? pair.imposter_word
                : roles[i] === 'spy'      ? null
                : pair.civilian_word
        }));
    }

    function handlePhaseClick(): void {
        if (playerIndex === players.length - 1) {
            if (phase === 'role_show') phase = 'word_input';
            else if (phase === 'word_input') phase = 'elimination';
        }

        showRole = false;
        increaseIndex();
    }

    function confirmElimination(): void {
        // no elimination
        if (votedFor === null || votedFor === SKIP_UUID) {
            eliminatedNickname = null;
            eliminatedRole = null;
            phase = 'results';
            return;
        }

        // eliminate target
        const target = players.find(p => p.nickname === votedFor)!;
        eliminatedNickname = target.nickname;
        eliminatedRole = target.role;
        players = players.filter(p => p.nickname !== votedFor);

        votedFor = null;

        // check for game end
        winner = checkGameEnd(players);
        
        if (winner === null) phase = 'results';
        else phase = 'end';
    }

    function checkGameEnd(players: Player[]): Role | null {
        const spies = players.filter(p => p.role === 'spy').length;
        const imposters = players.filter(p => p.role === 'imposter').length;
        const civilians = players.filter(p => p.role === 'civilian').length;

        // only spies left or a spy survives to a 2-player endgame
        if (
            (spies > 0 && imposters === 0 && civilians === 0) ||
            (spies > 0 && players.length === 2)
        ) return 'spy';

        // only imposters left or an imposter survives to a 2 player endgame
        if (
            (imposters > 0 && spies === 0 && civilians === 0) ||
            (imposters > 0 && spies === 0 && players.length === 2) 
        ) return 'imposter';

        // only civilians remain
        if (civilians > 0 && spies === 0 && imposters === 0) return 'civilian';

        // game continues
        return null;
    }

    async function handleHomeClick() {
        localStorage.removeItem('local_players');
        await goto('/home');
    }
</script>


<!-- HTML -->
<div class = 'page'>
    {#if phase === 'role_show'}
        {@const activePlayer = players[playerIndex]}

        <div class = 'centerCard'>
            {#if showRole}
                <div class = 'roleReveal'>
                    <p class = 'roleHint'>
                        {#if activePlayer.role === 'spy'}
                            You are a <strong> Spy </strong>
                            <br>
                            <span class = 'roleSub'> Find the civilian's word! </span>
                        {:else}
                            <span class = 'roleSub'> Your word is: </span>
                            <span class = 'wordBig'> { activePlayer.word } </span>
                        {/if}
                    </p>
                </div>

                <Button variant = 'filled' onclick = { handlePhaseClick }>
                    { playerIndex === players.length - 1 ? 'Start Game 🚀' : 'Next →' }
                </Button>
            {:else}
                <div class = 'passCard'>
                    <div class = 'passAvatar'>
                        { activePlayer.nickname[0].toUpperCase() }
                    </div>

                    <p class = 'passLabel'> Pass the device to </p>
                    <p class = 'passName'> { activePlayer.nickname } </p>
                </div>

                <Button variant = 'filled' onclick = { () => showRole = true } >
                    Show My Role 👁
                </Button>
            {/if}
        </div>

    {:else if phase === 'word_input'}
        {@const activePlayer = players[playerIndex]}

        <div class = 'centerCard'>
            <div class = 'turnIndicator'>
                <div class = 'turnAvatar'>
                    {activePlayer.nickname[0].toUpperCase() }
                </div>

                <div>
                    <p class = 'turnName'> { activePlayer.nickname } </p>
                    <p class = 'turnSub'> Say your word out loud </p>
                </div>
            </div>

            <div class = 'roundInfo'>
                Round — { Math.floor(playerIndex / players.length) + 1 }
            </div>

            <Button variant = 'filled' onclick = { handlePhaseClick } >
                { playerIndex === players.length - 1 ? 'Go to Vote 🗳' : 'Next →' }
            </Button>
        </div>

    {:else if phase === 'elimination'}
        <div class = 'votingWrapper'>
            <p class = 'voteTitle'> Vote to Eliminate </p>

            <div class = 'playerGrid'>
                {#each players as player}
                    {@const isVoted = votedFor === player.nickname}

                    <button
                        class = 'playerCard'
                        class:voted = { isVoted }
                        class:dimmed = { votedFor !== null && !isVoted }
                        onclick = { () => votedFor = player.nickname }
                    >
                        <div class = 'avatar'> {player.nickname[0].toUpperCase() } </div>
                        <span class = 'playerNick'> { player.nickname } </span>
                    </button>
                {/each}

                <button
                    class = 'playerCard skipCard'
                    class:voted = { votedFor === SKIP_UUID }
                    class:dimmed = { votedFor !== null && votedFor !== SKIP_UUID }
                    onclick = { () => votedFor = SKIP_UUID }
                >
                    <span class = 'skipEmoji'> ⏭ </span>
                    <span class = 'playerNick'> Skip </span>
                </button>
            </div>

            <Button
                variant = 'filled'
                onclick = { confirmElimination }
                disabled = { votedFor === null }
            >
                Confirm Vote ✓
            </Button>
        </div>

    {:else if phase === 'results'}
        <div class = 'centerCard resultsCard'>
            {#if eliminatedNickname !== null}
                <p class = 'resultsLabel'> Eliminated </p>

                <div
                    class = 'eliminatedAvatar'
                    style = 'background: { roleColors[eliminatedRole!] }'
                >
                    { eliminatedNickname[0].toUpperCase() }
                </div>
                
                <p class = 'eliminatedName'> { eliminatedNickname } </p>

                <div
                    class = 'rolePill'
                    style ='
                        background: { roleColors[eliminatedRole!] }20;
                        color: { roleColors[eliminatedRole!] }
                    '
                >
                    { roleEmojis[eliminatedRole!] } { eliminatedRole }
                </div>
            {:else}
                <p class = 'skipEmoji' style = 'font-size: 3rem'> ⏭ </p>
                <p class = 'eliminatedName'> No one eliminated </p>
                <p class = 'turnSub'> The vote was skipped </p>
            {/if}

            <Button variant = 'filled' onclick = { () => phase = 'word_input' } >
                Next Round →
            </Button>
        </div>

    {:else if phase === 'end'}
        <div class = 'centerCard endCard'>
            <p class = 'winEmoji'> { roleEmojis[winner!] } </p>
            <p class = 'winLabel'> { rolePlurals[winner!] } Win! </p>
            <div
                class = 'rolePill'
                style = '
                    background: { roleColors[winner!] }20;
                    color: { roleColors[winner!] }
                '
            >
                { winner }
            </div>

            <div class = 'endButtons'>
                <Button
                    variant = 'filled'
                    onclick = { () => goto('/local_game/settings') }
                >
                    Play Again 🔄
                </Button>

                <Button variant = 'outlined' onclick = { handleHomeClick } >
                    Home
                </Button>
            </div>
        </div>
    {/if}
</div>


<style>
    .page {
        width: 100%; height: 100%;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 1.5rem;
        box-sizing: border-box;
    }

    /* ── Center Card ── */
    .centerCard {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 1.5rem;
        width: 100%;
        max-width: 360px;
        text-align: center;
    }

    /* ── Role Show Phase ── */
    .passCard {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.5rem;
        padding: 2rem;
        background: var(--m3c-surface-container);
        border-radius: 1.5rem;
        width: 100%;
    }
    .passAvatar {
        width: 4.5rem; height: 4.5rem;
        border-radius: 50%;
        background: var(--m3c-primary);
        color: var(--m3c-on-primary);
        font-size: 2rem; font-weight: 700;
        display: flex; align-items: center; justify-content: center;
        margin-bottom: 0.5rem;
    }
    .passLabel { font-size: 0.85rem; color: var(--m3c-on-surface-variant); margin: 0; }
    .passName  { font-size: 1.5rem; font-weight: 700; margin: 0; }

    .roleReveal {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.75rem;
        padding: 2rem;
        background: var(--m3c-surface-container);
        border-radius: 1.5rem;
        width: 100%;
    }
    .roleHint   { font-size: 1.1rem; line-height: 1.6; margin: 0; }
    .roleSub    { font-size: 0.85rem; color: var(--m3c-on-surface-variant); }
    .wordBig {
        display: block;
        font-size: 2rem; font-weight: 800;
        color: var(--m3c-primary);
        margin-top: 0.25rem;
        letter-spacing: 0.02em;
    }

    /* ── Word Input Phase ── */
    .turnIndicator {
        display: flex;
        align-items: center;
        gap: 1rem;
        padding: 1.5rem;
        background: var(--m3c-surface-container);
        border-radius: 1.5rem;
        width: 100%;
        text-align: left;
    }
    .turnAvatar {
        width: 3.5rem; height: 3.5rem;
        border-radius: 50%;
        background: var(--m3c-primary);
        color: var(--m3c-on-primary);
        font-size: 1.5rem; font-weight: 700;
        display: flex; align-items: center; justify-content: center;
        flex-shrink: 0;
    }
    .turnName { font-size: 1.15rem; font-weight: 700; margin: 0; }
    .turnSub  { font-size: 0.8rem; color: var(--m3c-on-surface-variant); margin: 0.2rem 0 0; }

    .roundInfo {
        font-size: 0.8rem;
        color: var(--m3c-on-surface-variant);
        background: var(--m3c-surface-container);
        padding: 0.3rem 0.9rem;
        border-radius: 999px;
    }

    /* ── Voting Phase ── */
    .votingWrapper {
        width: 100%;
        max-width: 420px;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 1.25rem;
    }
    .voteTitle {
        font-size: 1.1rem; font-weight: 700;
        margin: 0;
    }
    .playerGrid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 0.75rem;
        width: 100%;
    }
    .playerCard {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.4rem;
        padding: 1rem 0.5rem;
        background: var(--m3c-surface-container);
        border: 2px solid var(--m3c-outline-variant);
        border-radius: 1rem;
        cursor: pointer;
        transition: border-color 200ms, opacity 200ms, transform 100ms;
    }
    .playerCard:active { transform: scale(0.97); }
    .playerCard.voted  { border-color: var(--m3c-primary); background: color-mix(in oklab, var(--m3c-primary) 8%, transparent); }
    .playerCard.dimmed { opacity: 0.35; }
    .skipCard { border-style: dashed; }
    .skipEmoji { font-size: 1.5rem; }

    .avatar {
        width: 3rem; height: 3rem;
        border-radius: 50%;
        background: var(--m3c-primary);
        color: var(--m3c-on-primary);
        font-size: 1.4rem; font-weight: 700;
        display: flex; align-items: center; justify-content: center;
    }
    .playerNick { font-size: 0.85rem; font-weight: 600; }

    /* ── Results Phase ── */
    .resultsCard { gap: 1rem; }
    .resultsLabel {
        font-size: 0.8rem; font-weight: 700;
        text-transform: uppercase; letter-spacing: 0.1em;
        color: var(--m3c-on-surface-variant);
        margin: 0;
    }
    .eliminatedAvatar {
        width: 5rem; height: 5rem;
        border-radius: 50%;
        color: white;
        font-size: 2.2rem; font-weight: 700;
        display: flex; align-items: center; justify-content: center;
    }
    .eliminatedName { font-size: 1.5rem; font-weight: 700; margin: 0; }
    .rolePill {
        padding: 0.3rem 0.9rem;
        border-radius: 999px;
        font-size: 0.85rem; font-weight: 600;
        text-transform: capitalize;
    }

    /* ── End Phase ── */
    .endCard { gap: 1rem; }
    .winEmoji { font-size: 4rem; margin: 0; }
    .winLabel { font-size: 2rem; font-weight: 800; margin: 0; }
    .endButtons {
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
        width: 100%;
        align-items: center;
        margin-top: 0.5rem;
    }
</style>