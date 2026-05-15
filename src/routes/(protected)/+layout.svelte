<script lang='ts'>
    import { themeStore } from "$lib/stores/theme.svelte";

    const  { data, children } = $props();

    $effect(() => {
        if (data.settings?.theme) {
            const dbDark = data.settings.theme === 'dark';

            if (themeStore.dark !== dbDark) themeStore.dark = dbDark;            
        }
    });
</script>

{@render children()}