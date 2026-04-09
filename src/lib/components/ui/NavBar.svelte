<script lang='ts'>
    // ── Imports ────────────────────────────────────────────────────────────────────────
    import type { Component } from 'svelte';
    import type { MouseEventHandler } from 'svelte/elements';

    // ── Props ──────────────────────────────────────────────────────────────────────────
    let { items }: { items: NavItem[] } = $props();

    // ── Types ──────────────────────────────────────────────────────────────────────────
    interface NavItem {
        label: string;
        icon: Component;
        handleClick?: MouseEventHandler<HTMLButtonElement>;
        active?: boolean;
    }
</script>


{#snippet NavBarItem(
    label: string,
    Icon: Component,
    handleClick: MouseEventHandler<HTMLButtonElement>,
    active: boolean
)}
    <button
        class = "navBarItem {active ? 'active' : ''}"
        onclick = { handleClick }
        type = 'button'
    >
        <Icon class="w-6 h-6" />
        <span>{label}</span>
    </button>
{/snippet}


<div class = 'navbar'>
    {#each items as item}
        {@render NavBarItem(
            item.label,
            item.icon,
            item.handleClick ?? (() => {}),
            item.active ?? false)
        }
    {/each}
</div>


<style>
    .navbar {
        width: 100%;
        height: 10vh;
        
        display: flex;
        flex-direction: row;
        justify-content: space-around;
        align-items: center;
        background-color: var(--m3c-surface-variant);
    }

    .navBarItem {
        height: 100%;
        width: 20vw;
        
        /* Reset button defaults */
        border: none;
        cursor: pointer;
        font: inherit;
        color: var(--m3c-on-surface-variant);
        background-color: transparent;

        display: flex;
        flex-direction: column;
        justify-content: space-around;
        align-items: center;
    }

    .active { color: var(--m3c-primary); }
</style>