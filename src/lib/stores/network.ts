import { browser } from "$app/environment";
import { get, writable } from "svelte/store";
import { isEffectivelyOffline } from "$lib/utils/checkConnection";

const POLL_MS = 1000 * 15; // 15 seconds

function createOfflineStore() {
	/*
	 * Internal writable store that actually holds the boolean:
	 * - true  => app should behave as offline
	 * - false => app can behave as online
	 */
	const store = writable(true);
	const { subscribe, set } = store;

	/*
	 * Tracks whether the store has started its listeners / polling.
	 * We only want to attach browser listeners once.
	 */
	let started = false;

	/*
	 * Number of active subscribers.
	 * When it drops to 0, we can stop polling and remove listeners.
	 */
	let subscribers = 0;

	/*
	 * ID of the polling interval so it can be cleared later.
	 * Using window.setInterval keeps the type as number in the browser.
	 */
	let interval: number | undefined;

	/*
	 * Holds the currently running connectivity check, if any.
	 *
	 * Why:
	 * If multiple callers trigger a refresh at the same time
	 * (initial startup, online event, button click, route guard, poll tick),
	 * they should all await the same request instead of creating duplicates.
	 */
	let inFlight: Promise<boolean> | null = null;

	/*
	 * Runs the real connectivity check, updates the store,
	 * and returns the fresh offline value.
	 *
	 * Return value:
	 * - true  => offline
	 * - false => online
	 */
	async function verifyConnection(): Promise<boolean> {
		if (!browser) return true;

		/*
		 * If a check is already running, reuse it.
		 * This avoids overlapping network probes.
		 */
		if (inFlight) return inFlight;

		inFlight = (async () => {
			try {
				const offline = await isEffectivelyOffline();
				set(offline);
				return offline;
			}
            catch {
				/*
				 * Defensive fallback:
				 * if the check itself throws unexpectedly,
				 * treat the app as offline.
				 */
				set(true);
				return true;
			}
            finally { inFlight = null; }
		})();

		return inFlight;
	}

	/*
	 * Native browser "offline" event:
	 * the browser already knows network connectivity is gone,
	 * so immediately mark the app as offline.
	 */
	function handleOffline(): void { set(true); }

	/*
	 * Native browser "online" event:
	 * do NOT blindly set offline = false.
	 *
	 * Instead, do a real verification because navigator.onLine / "online"
	 * can be optimistic and does not guarantee your backend is reachable.
	 */
	function handleOnline(): void { void verifyConnection(); }

	/*
	 * Starts background behavior for this store:
	 * - immediate initial check
	 * - browser online/offline listeners
	 * - periodic polling
	 *
	 * Safe to call multiple times; it only starts once.
	 */
	function start() {
		if (!browser || started) return;
		started = true;

		void verifyConnection();

		window.addEventListener("online", handleOnline);
		window.addEventListener("offline", handleOffline);

		interval = window.setInterval(() => {
			void verifyConnection();
		}, POLL_MS);
	}

	/*
	 * Stops background behavior when nobody is subscribed anymore.
	 */
	function stop() {
		if (!browser || !started || subscribers > 0) return;
		started = false;

		window.removeEventListener("online", handleOnline);
		window.removeEventListener("offline", handleOffline);

		if (interval !== undefined) {
			window.clearInterval(interval);
			interval = undefined;
		}
	}

	return {
		/*
		 * Standard Svelte store API.
		 *
		 * This is what allows:
		 * - import { offline } from '$lib/stores/network'
		 * - use $offline in components
		 *
		 * On first subscriber, the store starts its listeners/polling.
		 * On last unsubscribe, it cleans them up.
		 */
		subscribe(run: (value: boolean) => void) {
			subscribers += 1;
			start();

			const unsubscribe = subscribe(run);

			return () => {
				subscribers -= 1;
				unsubscribe();
				stop();
			};
		},

		/*
		 * Force an immediate connectivity check.
		 *
		 * Important:
		 * - updates the store immediately
		 * - returns the fresh offline value
		 *
		 * Return value:
		 * - true  => offline
		 * - false => online
		 */
		async refresh(): Promise<boolean> {
			start();
			return await verifyConnection();
		},

		/*
		 * Convenience method for online-only actions.
		 *
		 * It performs a fresh check, updates the store,
		 * and returns:
		 * - true  => online
		 * - false => offline
		 */
		async assertOnline(): Promise<boolean> {
			const offline = await verifyConnection();
			return !offline;
		},

		/*
		 * Synchronous snapshot of the current cached value.
		 *
		 * Useful when you only need the latest known state
		 * without forcing a new network request.
		 */
		getSnapshot(): boolean {
			return get(store);
		}
	};
}

/*
 * Exported store/service.
 *
 * In templates:
 *   $offline
 *
 * In code:
 *   await offline.refresh()
 *   await offline.assertOnline()
 *   offline.getSnapshot()
 */
export const offline = createOfflineStore();