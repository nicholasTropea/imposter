<script lang='ts'>
    import NavBar from '$components/ui/NavBar.svelte';

    import HomeIcon from '~icons/mdi/home';
    import CheckIcon from '~icons/mdi/check-circle';
    import UserIcon from '~icons/mdi/account';

    import { Button } from 'm3-svelte';

    const navItems = [
        { label: 'HOME', icon: HomeIcon },
        { label: 'CHECK', icon: CheckIcon },
        { label: 'PROFILE', icon: UserIcon }
    ];

    const { data } = $props(); // From (protected) layout file
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <main>
        <span>User: {data.nickname}</span>

        <Button variant='filled'> Play Ranked Game </Button>

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

    .ranked { color: yellow; }

    .auxButtons {
        width: 100%;

        display: flex;
        flex-direction: row;
        justify-content: space-around;
        align-items: center;
    }

    .nav {
        width: 100%;
    }
</style>