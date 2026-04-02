<script lang='ts'>
  import '/node_modules/m3-svelte/package/etc/recommended-styles.css';

  import '$lib/theme/light.css';
  import '$lib/theme/dark.css';
  import '$lib/theme/dark-hc.css';
  import '$lib/theme/light-hc.css';
  import '$lib/theme/dark-mc.css';
  import '$lib/theme/light-mc.css';

  import '../app.css'; // This applies the styles to the entire app

  type Contrast = 'standard' | 'medium' | 'high';
  let contrast = $state<Contrast>('standard');

  let dark = $state(
    typeof window !== 'undefined'
      ? window.matchMedia('(prefers-color-scheme: dark)').matches
      : false
  );

  const classMap: Record<string, string> = {
    'false-standard': 'light',
    'true-standard':  'dark',
    'false-medium':   'light-medium-contrast',
    'true-medium':    'dark-medium-contrast',
    'false-high':     'light-high-contrast',
    'true-high':      'dark-high-contrast',
  }

  $effect(() => {
    const all = Object.values(classMap);
    document.documentElement.classList.remove(...all);
    document.documentElement.classList.add(classMap[`${dark}-${contrast}`]);
  });

  let { children } = $props();
</script>

{@render children()}