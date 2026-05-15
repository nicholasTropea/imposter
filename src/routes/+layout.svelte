<script lang='ts'>
  // ── Imports ──────────────────────────────────────────────────────────────────────────
  import '$lib/theme/light.css';
  import '$lib/theme/dark.css';
  import '$lib/theme/dark-hc.css';
  import '$lib/theme/light-hc.css';
  import '$lib/theme/dark-mc.css';
  import '$lib/theme/light-mc.css';
  import '../app.css'; // This applies the styles to the entire app

  import { themeStore } from '$lib/stores/theme.svelte.js';
  import { auth } from '$lib/stores/auth';
  import { onMount } from 'svelte';
  import { Snackbar } from 'm3-svelte';
  import OfflinePill from '$components/ui/OfflinePill.svelte';

  // ── Props ────────────────────────────────────────────────────────────────────────────
  const { children } = $props();

  // ── Theme ────────────────────────────────────────────────────────────────────────────
  type Contrast = 'standard' | 'medium' | 'high';
  let contrast = $state<Contrast>('standard');

  themeStore.init();

  const classMap: Record<string, string> = {
    'false-standard': 'light',
    'true-standard':  'dark',
    'false-medium':   'light-medium-contrast',
    'true-medium':    'dark-medium-contrast',
    'false-high':     'light-high-contrast',
    'true-high':      'dark-high-contrast',
  }

  // This will re-run whenever themeStore or contrast change
  $effect(() => {
    const all = Object.values(classMap);
    document.documentElement.classList.remove(...all);
    document.documentElement.classList.add(classMap[`${themeStore.dark}-${contrast}`]);
  });

  // ── Service Worker and Auth ──────────────────────────────────────────────────────────
  onMount(async () => {
    if ('serviceWorker' in  navigator) {
      const { registerSW } = await import('virtual:pwa-register');
      registerSW({ immediate: true });
    }

    auth.init();
  }); 
</script>

<OfflinePill />
{@render children()}
<Snackbar />