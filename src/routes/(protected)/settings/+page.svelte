<script lang='ts'>
	// ── Imports ────────────────────────────────────────────────────────────────────────
	import SettingsSlider from '$components/ui/SettingsSlider.svelte';
	import SettingsSwitch from '$components/ui/SettingsSwitch.svelte';
	import { Card, ConnectedButtons, Button, Switch } from 'm3-svelte';

	import NavBar from '$components/ui/NavBar.svelte';

	import HomeIcon from '~icons/mdi/home';
	import PodiumIcon from '~icons/mdi/podium';
	import SettingsIcon from '~icons/mdi/gear';

	import { untrack } from 'svelte';
	import { browser } from '$app/environment';
	import { themeStore, setTheme as setGlobalTheme } from '$lib/stores/theme.svelte.js';
	import { offline } from '$lib/stores/network.js';
	import { gotoIfOnline } from '$lib/utils/onlineGuard.js';
	import { goto } from '$app/navigation';
	import {
		subscribeToPush,
		unsubscribeFromPush,
		getPushSubscription
	} from '$lib/utils/push';

	// ── Types ──────────────────────────────────────────────────────────────────────────
	type Theme = 'dark' | 'light';

	type SettingsDraft = {
		theme: Theme;
		master_volume: number;
		music_volume: number;
		sound_effects: boolean;
		game_invites: boolean;
		daily_rewards: boolean;
	};

	// ── Props ──────────────────────────────────────────────────────────────────────────
	const { data } = $props();

	// ── Localstorage Keys ──────────────────────────────────────────────────────────────
	/*
	 * Stores the most recent full settings snapshot for this page.
	 *
	 * This is used so the current UI state can survive refreshes or temporary
	 * connectivity loss after the page has already been opened.
	 */
	const LOCAL_DRAFT_KEY = 'settings_local_draft';

	/*
	 * Stores a settings snapshot that still needs to be sent to the backend.
	 *
	 * When the user makes changes while offline, this key keeps the pending
	 * payload so it can be retried automatically once the network is available.
	 */
	const PENDING_SYNC_KEY = 'settings_pending_sync';

	// ── Helpers ────────────────────────────────────────────────────────────────────────
	/**
	 * Builds a complete settings payload from the current local UI state.
	 *
	 * This gives one normalized object shape that can be:
	 * - persisted locally,
	 * - queued for later sync,
	 * - or sent directly to the server action.
	 *
	 * @returns The current settings snapshot.
	 */
	function buildCurrentSettings(): SettingsDraft {
		return {
			theme,
			master_volume: masterVolume,
			music_volume: musicVolume,
			sound_effects: soundEffects,
			game_invites: gameInvites,
			daily_rewards: dailyRewards
		};
	}

	/**
	 * Saves the latest local settings draft into `localStorage`.
	 *
	 * This lets the page keep the user's latest edits even if the page refreshes
	 * or the network disappears before the changes are synced to the backend.
	 *
	 * @param value - The settings snapshot to persist locally.
	 */
	function persistLocalDraft(value: SettingsDraft) {
		if (!browser) return;
		localStorage.setItem(LOCAL_DRAFT_KEY, JSON.stringify(value));
	}

	/**
	 * Writes or clears the pending offline sync payload in `localStorage`.
	 *
	 * A non-null value means there are settings changes that still need to be
	 * sent to the backend. Passing `null` clears the queue after a successful save.
	 *
	 * @param value - The pending payload to store, or `null` to clear it.
	 */
	function persistPendingSync(value: SettingsDraft | null) {
		if (!browser) return;

		if (value === null) {
			localStorage.removeItem(PENDING_SYNC_KEY);
			return;
		}

		localStorage.setItem(PENDING_SYNC_KEY, JSON.stringify(value));
	}

	/**
	 * Reads and parses a JSON value from `localStorage`.
	 *
	 * If the key is missing, invalid, or unreadable, the function safely returns
	 * `null` instead of throwing.
	 *
	 * @typeParam T - Expected parsed shape.
	 * @param key - The localStorage key to read.
	 * @returns The parsed value, or `null` if unavailable/invalid.
	 */
	function readJson<T>(key: string): T | null {
		if (!browser) return null;

		try {
			const raw = localStorage.getItem(key);
			return raw ? JSON.parse(raw) as T : null;
		}
		catch { return null; }
	}

	// ── Initial State ──────────────────────────────────────────────────────────────────
	/**
	 * Resolves the initial settings shown by the page.
	 *
	 * Priority:
	 * 1. a locally saved draft, if one exists in the browser
	 * 2. the server-provided settings from the protected page load
	 *
	 * `untrack` is used because this is only meant to initialize local page state,
	 * not stay reactively tied to `data.settings`.
	 */
	const initialSettings = untrack(() => {
		const serverSettings = data.settings satisfies SettingsDraft;

		if (!browser) return serverSettings;

		return readJson<SettingsDraft>(LOCAL_DRAFT_KEY) ?? serverSettings;
	});

	let theme = $state<Theme>(initialSettings.theme ?? (themeStore.dark ? 'dark' : 'light'));
	let masterVolume = $state<number>(initialSettings.master_volume);
	let musicVolume = $state<number>(initialSettings.music_volume);
	let soundEffects = $state<boolean>(initialSettings.sound_effects);
	let gameInvites = $state<boolean>(initialSettings.game_invites);
	let dailyRewards = $state<boolean>(initialSettings.daily_rewards);

	let pushEnabled = $state<boolean>(false);
	let pushPermission = $state<NotificationPermission | 'loading'>('loading');
	let pushInitialized = false;
	let pushProcessing = $state<boolean>(false);
	let pushPendingSync: boolean | null = null;
	let showPushHelp = $state<boolean>(false);

	// ── Theme ──────────────────────────────────────────────────────────────────────────
	/**
	 * Updates the local theme selection for this page and immediately applies the
	 * global app theme through the shared theme manager.
	 *
	 * The local `theme` value controls which button appears selected, while the
	 * shared theme store updates the root document class and persists the choice.
	 *
	 * @param value - The selected theme mode.
	 */
	function setTheme(value: Theme) {
		theme = value;
		setGlobalTheme(value === 'dark');
	}

	// ── Autosave State ─────────────────────────────────────────────────────────────────
	let saveTimeout: ReturnType<typeof setTimeout> | null = null;
	let saveError = $state<string | null>(null);
	let savePending = $state<boolean>(false);
	let initialized = false;

	// ── Autosave Helpers ───────────────────────────────────────────────────────────────
	/**
	 * Sends the provided settings snapshot to the `saveSettings` server action.
	 *
	 * On success:
	 * - the pending offline payload is cleared
	 *
	 * On failure:
	 * - an error message is shown
	 * - the payload is kept in localStorage for retry when connectivity returns
	 *
	 * @param payload - The settings snapshot to save remotely.
	 * @returns `true` when the save succeeds, otherwise `false`.
	 */
	async function saveSettingsToServer(payload: SettingsDraft): Promise<boolean> {
		try {
			savePending = true;
			saveError = null;

			const res = await fetch('?/saveSettings', {
				method: 'POST',
				headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
				body: new URLSearchParams({
					theme: payload.theme,
					master_volume: String(payload.master_volume),
					music_volume: String(payload.music_volume),
					sound_effects: String(payload.sound_effects),
					game_invites: String(payload.game_invites),
					daily_rewards: String(payload.daily_rewards)
				})
			});

			if (!res.ok) {
				saveError = 'Could not save settings.';
				return false;
			}

			persistPendingSync(null);
			return true;
		}
		catch {
			saveError = 'You are offline. Changes are saved locally for now.';
			persistPendingSync(payload);
			return false;
		}
		finally { savePending = false; }
	}

	/**
	 * Debounces automatic saving of the current settings state.
	 *
	 * Behavior:
	 * - always persists the latest snapshot locally first
	 * - if offline, stores the payload for later retry instead of sending it
	 * - if online, waits 800ms after the latest change before sending one request
	 *
	 * This avoids excessive writes while sliders are dragged or several settings
	 * are changed quickly in sequence.
	 */
	function scheduleAutoSave() {
		if (saveTimeout) clearTimeout(saveTimeout);

		const payload = buildCurrentSettings();
		persistLocalDraft(payload);

		if (!browser) return;

		if ($offline) {
			persistPendingSync(payload);
			saveError = 'You are offline. Changes are saved locally for now.';
			return;
		}

		saveTimeout = setTimeout(async () => {
			await saveSettingsToServer(payload);
		}, 800);
	}

	/**
	 * Retries the latest pending offline settings payload, if one exists.
	 *
	 * This is called when the app detects that connectivity has returned.
	 * If there is no queued payload, the function does nothing.
	 */
	async function flushPendingSettings() {
		if (!browser || $offline) return;

		const pending = readJson<SettingsDraft>(PENDING_SYNC_KEY);
		if (!pending) return;

		await saveSettingsToServer(pending);
	}

	// ── Push Notifications ─────────────────────────────────────────────────────────────
	/**
	 * Synchronizes the local push subscription state with the browser and server.
	 *
	 * If the user enables the switch, it requests permission and registers the
	 * device. If they disable it, it unsubscribes from the browser and removes
	 * the record from the database.
	 *
	 * @param enabled - The target subscription state.
	 */
	async function syncPush(enabled: boolean) {
		if (pushProcessing) {
			pushPendingSync = enabled;
			return;
		}

		pushProcessing = true;

		try {
			if (enabled) await subscribeToPush();
			else await unsubscribeFromPush();

			// Update permission state after attempt
			if (browser) pushPermission = Notification.permission;

			// If a new request came in while we were processing, handle it next
			if (pushPendingSync !== null && pushPendingSync !== enabled) {
				const next = pushPendingSync;
				pushPendingSync = null;
				pushProcessing = false; // reset to allow next call
				await syncPush(next);
				return;
			}
		}
		catch (err) {
			console.error('Push sync failed:', err);
			saveError = err instanceof Error
				? err.message
				: 'Could not update push settings.';

			// Revert the switch if it failed
			const sub = await getPushSubscription();
			pushEnabled = !!sub;
			pushPendingSync = null;
			if (browser) pushPermission = Notification.permission;
		}
		finally { pushProcessing = false; }
	}

	function handlePushToggle() {
		if (!pushInitialized || pushProcessing) return;
		pushEnabled = !pushEnabled;
	}

	// ── Effects ────────────────────────────────────────────────────────────────────────
	/**
	 * Checks the current browser push subscription and permission on mount.
	 */
	$effect(() => {
		if (!browser) return;

		pushPermission = Notification.permission;
		getPushSubscription().then((sub) => {
			pushEnabled = !!sub;
			pushInitialized = true;
		});
	});

	/**
	 * Watches the pushEnabled state and triggers synchronization when changed by the user.
	 */
	$effect(() => {
		const enabled = pushEnabled;
		if (!browser || !pushInitialized) return;

		untrack(() => syncPush(enabled));
	});

	/**
	 * Watches the local settings state and schedules autosave after changes.
	 *
	 * The first run is treated as initialization only:
	 * - it syncs the server/local initial theme into the shared global theme manager
	 * - it does not trigger an autosave immediately on page load
	 *
	 * Cleanup clears the active debounce timer when the effect reruns or the
	 * component is destroyed.
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

		if (!browser) return;

		if (!initialized) {
			initialized = true;
			setGlobalTheme(theme === 'dark');
			return;
		}

		scheduleAutoSave();

		return () => {
			if (saveTimeout) clearTimeout(saveTimeout);
		};
	});

	/**
	 * Watches network state and retries any pending queued settings once the app
	 * is back online.
	 */
	$effect(() => {
		if (!browser) return;

		const isOffline = $offline;
		if (isOffline) return;

		flushPendingSettings();
	});

	// ── Navbar ─────────────────────────────────────────────────────────────────────────
	const navItems = [
		{
			label: 'HOME',
			icon: HomeIcon,
			handleClick: () => goto('/home')
		},
		{
			label: 'LEADERBOARD',
			icon: PodiumIcon,
			handleClick: () => gotoIfOnline('/leaderboard')
		},
		{
			label: 'SETTINGS',
			icon: SettingsIcon,
			active: true
		}
	];
</script>


<!-- HTML -->
<div class = 'wrapper'>
	<div class = 'settingsWrapper'>
		<Card variant = 'filled'>
			<SettingsSlider label = 'Master Volume' bind:initial = { masterVolume } />
			<SettingsSlider label = 'Music Volume' bind:initial = { musicVolume } />
			<SettingsSwitch label = 'Sound Effects' bind:active = { soundEffects } />
		</Card>

		<Card variant = 'filled'>
			<div class = 'push-setting'>
				<div class = 'textContainer'>
					<span> Push Notifications </span>
					{#if pushPermission === 'denied'}
						<span class = 'error-text'> Blocked by browser </span>
					{:else if pushPermission === 'granted'}
						<span> Enable on this device </span>
					{:else}
						<span> Receive game updates </span>
					{/if}
				</div>

				<div class = 'action-container'>
					{#if pushPermission === 'denied'}
						<Button
							variant = 'text'
							onclick = { () => showPushHelp = !showPushHelp }
						>
							How to reset?
						</Button>
					{:else if pushPermission === 'granted'}
						<Button
							variant = 'tonal'
							disabled = { true }
						>
							Enabled
						</Button>
					{:else}
						<Button 
							variant = 'tonal' 
							onclick = { handlePushToggle } 
							disabled = { pushProcessing }
						>
							{ pushProcessing ? 'Enabling...' : 'Enable' }
						</Button>
					{/if}
				</div>
			</div>

			{#if showPushHelp}
				<div class = 'help-box'>
					<p> To enable notifications: </p>
					<ol>
						<li> Click the <strong>lock</strong> or <strong>info</strong> icon in your browser address bar. </li>
						<li> Look for <strong>Notifications</strong> and change it to <strong>Allow</strong>. </li>
						<li> <strong>Refresh</strong> this page to apply changes. </li>
					</ol>
				</div>
			{/if}

			<SettingsSwitch
				label = 'Game Invites'
				meaning = 'When friends want you to play'
				bind:active = { gameInvites }
			/>

			<SettingsSwitch
				label = 'Daily Rewards'
				meaning = 'Reminders for free coins'
				bind:active = { dailyRewards }
			/>
		</Card>

		<ConnectedButtons>
			<Button
				onclick = { () => setTheme('dark') }
				variant = { theme === 'dark' ? 'filled' : 'outlined' }
			>
				Dark
			</Button>

			<Button
				onclick = { () => setTheme('light') }
				variant = { theme === 'light' ? 'filled' : 'outlined' }
			>
				Light
			</Button>
		</ConnectedButtons>

		{#if savePending}
			<p class = 'statusText'> Saving… </p>
		{:else if saveError}
			<p class = 'statusText error'> { saveError } </p>
		{/if}
	</div>

	<NavBar items = { navItems } />
</div>


<style>
	.wrapper {
		width: 100%;
		height: 100%;

		display: flex;
		flex-direction: column;
		justify-content: space-between;
		align-items: center;
	}

	.settingsWrapper {
		width: 100%;

		display: flex;
		flex: 1;
		flex-direction: column;
		justify-content: space-around;
		align-items: center;
		gap: 1rem;
		padding: 1rem;
	}

	.push-setting {
		width: 100%;
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 0.5rem 0;
	}

	.push-setting .textContainer {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}

	.push-setting .textContainer span:first-child {
		font-weight: 500;
	}

	.push-setting .textContainer span:last-child {
		font-size: 0.85rem;
		color: var(--m3c-on-surface-variant);
	}

	.push-setting .textContainer .error-text {
		color: var(--m3c-error);
	}

	.help-box {
		margin-top: 1rem;
		padding: 1rem;
		background: var(--m3c-surface-container-high);
		border-radius: 0.5rem;
		font-size: 0.85rem;
		color: var(--m3c-on-surface);
	}

	.help-box p {
		margin-bottom: 0.5rem;
		font-weight: 500;
	}

	.help-box ol {
		padding-left: 1.25rem;
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}

	.statusText {
		font-size: 0.85rem;
		color: var(--m3c-on-surface-variant);
		margin-top: 0.5rem;
	}

	.statusText.error {
		color: var(--m3c-error);
	}
</style>