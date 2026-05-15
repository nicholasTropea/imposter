<script lang="ts">
	// ── Imports ────────────────────────────────────────────────────────────────────────
	import NavBar from '$components/ui/NavBar.svelte';

	import HomeIcon from '~icons/mdi/home';
	import PodiumIcon from '~icons/mdi/podium';
	import SettingsIcon from '~icons/mdi/gear';
	import LoginIcon from '~icons/mdi/login';

	import { Button } from 'm3-svelte';
	import { goto } from '$app/navigation';
	import { offline } from '$lib/stores/network';
	import { auth } from '$lib/stores/auth';
	import { gotoIfOnline } from '$lib/utils/onlineGuard';

	// ── Derived state ──────────────────────────────────────────────────────────────────
	const loggedIn = $derived(!!$auth.user);
	const nickname = $derived(
        $auth.user?.user_metadata?.nickname ?? $auth.user?.email ?? null
    );

	// ── Navbar ─────────────────────────────────────────────────────────────────────────
	/*
	 * The navbar is now derived from the current client auth state.
	 *
	 * Why:
	 * - /home is now a public page, so it must work for both guests and logged-in users
	 * - guests should not see app-only navigation like Settings
	 * - authenticated users should still see the normal in-app navigation
	 *
	 * Result:
	 * - logged-in user   -> HOME, LEADERBOARD, SETTINGS
	 * - guest user       -> HOME, LOGIN
	 *
	 * LEADERBOARD and SETTINGS still use gotoIfOnline because they depend on
	 * online/server-backed app behavior. LOGIN uses plain goto so the user can
	 * still open the login page even while offline.
	 */
	const navItems = $derived(
		loggedIn
			? [
					{
						label: 'HOME',
						icon: HomeIcon,
						active: true
					},
					{
						label: 'LEADERBOARD',
						icon: PodiumIcon,
						handleClick: () => gotoIfOnline('/leaderboard')
					},
					{
						label: 'SETTINGS',
						icon: SettingsIcon,
						handleClick: () => gotoIfOnline('/settings')
					}
				]
			: [
					{
						label: 'HOME',
						icon: HomeIcon,
						active: true
					},
					{
						label: 'LOGIN',
						icon: LoginIcon,
						handleClick: () => goto('/login')
					}
				]
	);
</script>

<div class = 'wrapper'>
	<main>
		{#if !$auth.ready}
			<span> Loading user state... </span>
		{:else if loggedIn}
			<span> User: { nickname } </span>

			<Button
				variant = 'filled'
				onclick = { () => gotoIfOnline('/loading_lobby') }
				disabled={ $offline }
			>
				Play Ranked Game
			</Button>
		{:else}
			<span> You are not logged in. </span>

			<Button variant = 'filled' onclick = { () => goto('/login') } >
				Log In
			</Button>
		{/if}

        <Button variant = 'filled' onclick = { () => goto('/local_game/settings') } >
            Play Local Game
        </Button>
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
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 10vh;
	}
</style>