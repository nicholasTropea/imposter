<script lang='ts'>
    // ── Imports ────────────────────────────────────────────────────────────────────────
    import NavBar from '$components/ui/NavBar.svelte';

    import HomeIcon from '~icons/mdi/home';
    import CheckIcon from '~icons/mdi/check-circle';
    import SettingsIcon from '~icons/mdi/gear';

    import { Button } from 'm3-svelte';
    import { goto } from '$app/navigation';

    // ── Props ──────────────────────────────────────────────────────────────────────────
    const { data } = $props(); // From (protected) layout file

    // ── Navbar ─────────────────────────────────────────────────────────────────────────    
    const navItems = [
        { label: 'HOME', icon: HomeIcon, active: true },
        { label: 'CHECK', icon: CheckIcon },
        { label: 'SETTINGS', icon: SettingsIcon, handleClick: (() => goto('/settings')) }
    ]; 

    // ── Navigation ─────────────────────────────────────────────────────────────────────
    function handleRankedClick(): void {
        goto('/loading_lobby');
    }
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <main>
        <span>User: {data.nickname}</span>

        <Button variant = 'filled' onclick = {handleRankedClick} >
            Play Ranked Game
        </Button>

        <div class = 'auxButtons'>
            <Button> Create Game </Button>
            <Button> Join Game </Button>
        </div>
    </main>

    <NavBar items = {navItems} />
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

        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 10vh;
    }

    .auxButtons {
        width: 100%;

        display: flex;
        flex-direction: row;
        justify-content: space-around;
        align-items: center;
    }
</style>