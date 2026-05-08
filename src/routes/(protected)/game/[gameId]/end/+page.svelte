<script lang='ts'>
    // ── Imports ────────────────────────────────────────────────────────────────────────    
    import { onMount, untrack } from 'svelte';
    import { goto } from '$app/navigation';

    import type { PageData } from './$types';

    // ── Types ──────────────────────────────────────────────────────────────────────────

    // ── Props ──────────────────────────────────────────────────────────────────────────
    const { data }: { data: PageData } = $props();

    let displayElo = $state(untrack(() => data.previousElo));
    
    const winnerLabel: Record<string, string> = {
        spy:      'Spies Win!',
        imposter: 'Imposters Win!',
        civilian: 'Civilians Win!'
    };

    onMount(() => {
        setTimeout(() => {
            const start = data.previousElo;
            const end = data.currentElo;
            const duration = 1500;
            const startTime = performance.now();

            function step(now: number) {
                const t = Math.min((now - startTime) / duration, 1);
                // ease out cubic for a natural deceleration
                const eased = 1 - Math.pow(1 - t, 3);
                displayElo = Math.round(start + (end - start) * eased);
                if (t < 1) requestAnimationFrame(step);
            }

            requestAnimationFrame(step);
        }, 800);
    });
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <p class = 'outcome' class:victory = { data.won } class:defeat = { !data.won }>
        { data.won ? 'Victory' : 'Defeat' }
    </p>

    <h1 class = 'winnerLabel'> {winnerLabel[data.winner] } </h1>

    <p class = 'roleLabel'>
        You were the <strong> { data.role } </strong>
    </p>

    <div
        class = 'eloBox'
        class:positive = { data.delta > 0 }
        class:negative = { data.delta < 0 }
    >
        <span class = 'eloLabel'> ELO </span>
        <span class = 'eloValue'> { displayElo } </span>
        <span class = 'eloDelta'>
            { data.delta > 0 ? '▲' : '▼' } { Math.abs(data.delta) }
        </span>
    </div>

    <button onclick = { () => goto('/home') }>
        Back to Home
    </button>
</div>


<style>
    .wrapper {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        height: 100%;
        gap: 1rem;
        padding: 2rem;
    }

    .outcome {
        font-size: 0.85rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.12em;
    }
    .outcome.victory { color: var(--color-success, green); }
    .outcome.defeat  { color: var(--color-error, red); }

    .winnerLabel {
        font-size: 2rem;
        font-weight: 800;
        text-align: center;
    }

    .roleLabel {
        font-size: 0.95rem;
        color: var(--color-text-muted, gray);
    }

    .eloBox {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.25rem;
        margin-top: 1.5rem;
    }

    .eloLabel {
        font-size: 0.75rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        color: var(--color-text-muted, gray);
    }

    .eloValue {
        font-size: 3.5rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1;
    }

    .eloDelta {
        font-size: 1.1rem;
        font-weight: 600;
        font-variant-numeric: tabular-nums;
    }

    .eloBox.positive .eloValue,
    .eloBox.positive .eloDelta { color: var(--color-success, green); }

    .eloBox.negative .eloValue,
    .eloBox.negative .eloDelta { color: var(--color-error, red); }

    button {
        margin-top: 2rem;
        padding: 0.6rem 2rem;
        background: var(--color-primary, teal);
        color: white;
        border-radius: 0.5rem;
        font-size: 1rem;
        cursor: pointer;
    }
</style>