<script lang='ts'>
    // ── Imports ────────────────────────────────────────────────────────────────────────
    import SettingsSlider from '$components/ui/SettingsSlider.svelte';
    import SettingsSwitch from '$components/ui/SettingsSwitch.svelte';
    import { Card, ConnectedButtons, Button } from 'm3-svelte';

    import { untrack } from 'svelte';
    import { browser } from '$app/environment';
    import { themeStore } from '$lib/stores/theme.svelte.js';

    // ── Props ──────────────────────────────────────────────────────────────────────────
    const { data } = $props(); // From (protected) layout file

    // ── State ──────────────────────────────────────────────────────────────────────────
    // Fetched from database (Untrack explicitly says not to track for rendering,
    // used to get rid of compiler warnings)
    let theme = $state<'dark' | 'light'>(untrack(() => data.settings.theme));
    let masterVolume = $state<number>(untrack(() => data.settings.master_volume));
    let musicVolume = $state<number>(untrack(() => data.settings.music_volume));
    let soundEffects = $state<boolean>(untrack(() => data.settings.sound_effects));
    let gameInvites  = $state<boolean>(untrack(() => data.settings.game_invites));
    let dailyRewards = $state<boolean>(untrack(() => data.settings.daily_rewards));

    // ── Theme ──────────────────────────────────────────────────────────────────────────
    function setTheme(value: 'light' | 'dark') {
        theme = value; // Local value (highlights the correct button)
        themeStore.dark = value === 'dark'; // Shared value
    }

    // ── Autosave ───────────────────────────────────────────────────────────────────────
    let saveTimeout: ReturnType<typeof setTimeout>;

    function scheduleAutoSave() {
        clearTimeout(saveTimeout);

        /**
         * Schedules a debounced POST to the `saveSettings` action.
         *
         * Resets the timer on every call, so the request is only sent 800ms after
         * the *last* change — preventing redundant DB writes while the user is
         * actively dragging a slider or toggling multiple switches in quick succession.
         *
         * Builds the request body manually as `application/x-www-form-urlencoded`
         * to match what SvelteKit's `request.formData()` expects server-side,
         * without needing an actual `<form>` element in the DOM.
         */
        saveTimeout = setTimeout(async () => {
            await fetch('?/saveSettings', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({
                    theme,
                    master_volume: String(masterVolume),
                    music_volume:  String(musicVolume),
                    sound_effects: String(soundEffects),
                    game_invites:  String(gameInvites),
                    daily_rewards: String(dailyRewards),
                })
            });
        }, 800);
    }

    /**
     * Watches all settings state and triggers a debounced autosave on any change.
     * Runs in the browser only — skipped during SSR since `fetch` and the DOM
     * are unavailable server-side.
     */
    $effect(() => {
        const _ = [
            theme,
            masterVolume,
            musicVolume,
            soundEffects,
            gameInvites,
            dailyRewards
        ];

        if (browser) scheduleAutoSave();
    });
</script>


<!-- HTML -->
<div class = 'wrapper'>
    <Card variant = 'filled'>
        <SettingsSlider label = 'Master Volume' bind:initial = {masterVolume} />
        <SettingsSlider label = 'Music Volume' bind:initial = {musicVolume} />
        <SettingsSwitch label = 'Sound Effects' bind:active = {soundEffects}/>
    </Card>

    <Card variant = 'filled'>
        <SettingsSwitch
            label = 'Game Invites'
            meaning = 'When friends want you to play'
            bind:active = {gameInvites}
        />

        <SettingsSwitch
            label = 'Daily Rewards'
            meaning = 'Reminders for free coins'
            bind:active = {dailyRewards}
        />
    </Card>

    <ConnectedButtons >
        <Button
            onclick={() => setTheme('dark')}
            variant = {theme === 'dark' ? 'filled' : 'outlined'}
        > 
            Dark
        </Button>

        <Button
            onclick={() => setTheme('light')}
            variant = {theme === 'light' ? 'filled' : 'outlined'}
        >
            Light
        </Button>
    </ConnectedButtons>
</div>


<style>
    .wrapper {
        width: 100%;
        height: 100%;

        display: flex;
        flex-direction: column;
        justify-content: space-around;
        align-items: center;
    }
</style>