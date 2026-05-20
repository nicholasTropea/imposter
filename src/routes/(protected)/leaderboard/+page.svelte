<script lang='ts'>
    // ── Imports ────────────────────────────────────────────────────────────────────────
    import NavBar from '$components/ui/NavBar.svelte';

    import HomeIcon from '~icons/mdi/home';
    import PodiumIcon from '~icons/mdi/podium';
    import SettingsIcon from '~icons/mdi/gear';

    import { untrack } from 'svelte';
    import { gotoIfOnline } from '$lib/utils/onlineGuard';
    import { goto } from '$app/navigation';

    import type { PageData } from './$types';

    // ── Props ──────────────────────────────────────────────────────────────────────────
    const { data }: { data: PageData } = $props(); // From (protected) layout file

    // ── Navbar ─────────────────────────────────────────────────────────────────────────    
    const navItems = [
        {
            label: 'HOME',
            icon: HomeIcon,
            handleClick: () => goto('/home')
        },
        {
            label: 'LEADERBOARD',
            icon: PodiumIcon,
            active: true
        },
        {
            label: 'SETTINGS',
            icon: SettingsIcon,
            handleClick: () => gotoIfOnline('/settings')
        }
    ];

    // ── Other ──────────────────────────────────────────────────────────────────────────
    const userInTop100 = untrack(() => data.userElo === null);
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <main>
        <div class = 'leaderboard'>
            <h1> Leaderboard </h1>

            <div class = 'table-wrapper'>
                <table>
                    <thead>
                        <tr>
                            <th class = 'col-rank'> Rank </th>
                            <th class = 'col-name'> Player </th>
                            <th class = 'col-elo'> Elo </th>
                        </tr>
                    </thead>
                    <tbody>
                        {#each data.players as player, i}
                            <tr class:is-you = { player.id === data.userId }>
                                <td class = 'col-rank'>
                                    {#if i === 0}
                                        <span class = 'medal'> 🥇 </span>
                                    {:else if i === 1}
                                        <span class = 'medal'> 🥈 </span>
                                    {:else if i === 2}
                                        <span class = 'medal'> 🥉 </span>
                                    {:else}
                                        <span class = 'rank-num'> # {i + 1} </span>
                                    {/if}
                                </td>
                                <td class = 'col-name'>
                                    { player.nickname }

                                    {#if player.id === data.userId}
                                        <span class = 'you-badge'> you </span>
                                    {/if}
                                </td>
                                <td class = 'col-elo'> { player.elo } </td>
                            </tr>
                        {/each}
                    </tbody>
                </table>
            </div>

            {#if !userInTop100 && data.userRank !== null}
                <div class = 'user-footer'>
                    <span class = 'col-rank rank-num'> # { data.userRank } </span>

                    <span class = 'col-name'>
                        { data.userNickname } <span class = 'you-badge'> you </span>
                    </span>
                    
                    <span class = 'col-elo'> { data.userElo ?? '—' } </span>
                </div>
            {/if}
        </div>
    </main>

    <NavBar items = { navItems } />
</div>


<style>
    .wrapper {
        width: 100%;
        height: 100%;

        display: flex;
        flex-direction: column;
    }

    main {
        width: 100%;
        
        flex: 1;
        min-height: 0; /* prevents flex child from overflowing */

        display: flex;
        flex-direction: column;
        align-items: center;
    }

    .leaderboard {
        width: 100%;
        max-width: 640px;
        min-height: 0; /* same reason */
        margin-inline: auto;
        display: flex;
        flex-direction: column;
        flex: 1;
    }

    h1 {
        font-size: 1.5rem;
        font-weight: 700;
        margin-bottom: 1.5rem;
    }

    .table-wrapper {
        border: 1px solid hsl(0 0% 0% / 0.08);
        border-radius: 0.75rem;
        overflow-y: auto; /* scroll lives here */
        flex: 1;
        min-height: 0;
    }

    table {
        width: 100%;
        border-collapse: collapse;
    }

    thead tr {
        background: hsl(0 0% 0% / 0.03);
        border-bottom: 1px solid hsl(0 0% 0% / 0.08);
    }

    th {
        padding: 0.625rem 1rem;
        font-size: 0.75rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: hsl(0 0% 0% / 0.45);
        text-align: left;
    }

    td {
        padding: 0.75rem 1rem;
        font-size: 0.9375rem;
        border-bottom: 1px solid hsl(0 0% 0% / 0.05);
        font-variant-numeric: tabular-nums;
    }

    tbody tr:last-child td {
        border-bottom: none;
    }

    tbody tr:hover {
        background: hsl(0 0% 0% / 0.02);
    }

    tr.is-you {
        background: hsl(175 90% 30% / 0.06);
    }

    tr.is-you td {
        font-weight: 500;
    }

    .col-rank { width: 64px; }
    .col-elo  { text-align: right; }

    .rank-num {
        color: hsl(0 0% 0% / 0.4);
        font-size: 0.875rem;
    }

    .medal { font-size: 1.125rem; }

    .you-badge {
        display: inline-block;
        margin-left: 0.4rem;
        padding: 0.1em 0.45em;
        font-size: 0.6875rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        background: hsl(175 90% 30% / 0.12);
        color: hsl(175 80% 25%);
        border-radius: 999px;
    }

    /* Sticky footer row for out-of-top-100 user */
    .user-footer {
        display: flex;
        align-items: center;
        padding: 0.75rem 1rem;
        margin-top: 0.5rem;
        border: 1px solid hsl(175 90% 30% / 0.2);
        border-radius: 0.75rem;
        background: hsl(175 90% 30% / 0.05);
        font-size: 0.9375rem;
        font-weight: 500;
        font-variant-numeric: tabular-nums;
        gap: 0;
    }

    .user-footer .col-rank { min-width: 64px; }
    .user-footer .col-name { flex: 1; }
    .user-footer .col-elo  { margin-left: auto; }
</style>