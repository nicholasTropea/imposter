<script lang='ts'>
	import { Button } from 'm3-svelte';
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth';

	let installed = $state(false);
	let mounted = $state(false);

	const loggedIn = $derived(!!$auth.user);

	onMount(() => {
		installed =
			('standalone' in window.navigator &&
				(window.navigator as Navigator & { standalone?: boolean }).standalone === true) ||
			window.matchMedia('(display-mode: standalone)').matches;

		mounted = true;
	});

	$effect(() => {
		if (!mounted) return;

		if (installed || loggedIn) {
			goto('/home');
		}
	});
</script>


<!-- HTML -->
<div class = 'wrapper'>
	<h1> Imposter Words </h1>
	<p> A social deduction word game. </p>

	<Button variant = 'filled' onclick = { () => goto('/signup') } >
		Sign up
	</Button>

	<Button variant = 'outlined' onclick = { () => goto('/login') } >
		Login
	</Button>

	<Button variant = 'text' onclick = { () => goto('/local_game/settings') } >
		Play local
	</Button>
</div>


<style>
	.wrapper {
		width: 100%;
		height: 100%;
		display: flex;
		flex-direction: column;
		justify-content: center;
		align-items: center;
		gap: 1rem;
		padding: 1rem;
		text-align: center;
	}
</style>