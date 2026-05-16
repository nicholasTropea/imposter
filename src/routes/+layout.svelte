<script lang="ts">
	// ── Imports ────────────────────────────────────────────────────────────────────────
	import '$lib/theme/light.css';
	import '$lib/theme/dark.css';
	import '$lib/theme/dark-hc.css';
	import '$lib/theme/light-hc.css';
	import '$lib/theme/dark-mc.css';
	import '$lib/theme/light-mc.css';
	import '../app.css';

	import { initThemeStore } from '$lib/stores/theme.svelte';
	import { auth } from '$lib/stores/auth';
	import { onMount } from 'svelte';
	import { Snackbar } from 'm3-svelte';
	import OfflinePill from '$components/ui/OfflinePill.svelte';

	// ── Props ──────────────────────────────────────────────────────────────────────────
	const { children } = $props();

	// ── Theme ──────────────────────────────────────────────────────────────────────────
	initThemeStore();

	// ── Service Worker & Auth ──────────────────────────────────────────────────────────
	onMount(async () => {
		if ('serviceWorker' in navigator) {
			const { registerSW } = await import('virtual:pwa-register');
			registerSW({ immediate: true });
		}

		auth.init();
	});
</script>

<OfflinePill />
{@render children()}
<Snackbar />