<script lang='ts'>
  // ── Imports ──────────────────────────────────────────────────────────────────────────
  import '/node_modules/m3-svelte/package/etc/recommended-styles.css';

  import '$lib/theme/light.css';
  import '$lib/theme/dark.css';
  import '$lib/theme/dark-hc.css';
  import '$lib/theme/light-hc.css';
  import '$lib/theme/dark-mc.css';
  import '$lib/theme/light-mc.css';

  import '../app.css'; // This applies the styles to the entire app
  import { browser } from '$app/environment'
  import { themeStore } from '$lib/stores/theme.svelte.js';

  // ── Props ────────────────────────────────────────────────────────────────────────────
  const { data, children } = $props();

  // ── Theme ────────────────────────────────────────────────────────────────────────────
  type Contrast = 'standard' | 'medium' | 'high';
  let contrast = $state<Contrast>('standard');

  // ── Theme Choice ─────────────────────────────────────────────────────────────────────

  /**
   * Resolves the initial dark mode value.
   * - Authenticated: use the theme stored in the DB.
   * - Unauthenticated: fall back to the system preference.
   */
  function resolveInitialDark(): boolean {
      if (data.settings?.theme) return data.settings.theme === 'dark';
      if (browser) return window.matchMedia('(prefers-color-scheme: dark)').matches;
      return false;
  }

  // Initialize store so settings page can update it
  themeStore.dark = resolveInitialDark();

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
</script>

{@render children()}