import { browser } from '$app/environment';
import { get, writable } from 'svelte/store';
import type { AuthChangeEvent, Session, User } from '@supabase/supabase-js';
import { supabase } from '$lib/supabase';

/*
 * Shape of the public auth state exposed by this store.
 *
 * - ready === false:
 *   the store has not finished reading the initial browser session yet
 *
 * - ready === true and user === null:
 *   no authenticated user is currently known in the browser
 *
 * - ready === true and user !== null:
 *   the browser currently has a logged-in Supabase user
 */
type AuthState = {
	ready: boolean;
	user: User | null;
};

function createAuthStore() {
	/* Initially not ready since the current browser session needs to be fetched. */
	const store = writable<AuthState>({
		ready: false,
		user: null
	});

	const { subscribe, set } = store;

	/* Tracks whether the auth listener has already been attached. */
	let started = false;

	/* Reference to the Supabase auth subscription so it can clean it up later. */
	let authSubscription: { unsubscribe: () => void } | null = null;

	/*
	 * Reads the current auth session from the browser-side Supabase client.
	 *
	 * Important:
	 * - this is for UI state only
	 * - protected routes must still be enforced server-side
	 */
	async function syncFromSession(): Promise<User | null> {
		if (!browser) {
			/*
			 * On the server there is no browser session to inspect.
			 * Mark the store as ready with no user.
			 */
			set({ ready: true, user: null });
			return null;
		}

		const { data: { session } } = await supabase.auth.getSession();

		const user = session?.user ?? null;

		set({ ready: true, user });

		return user;
	}

	/*
	 * Starts the store:
	 * 1. performs an initial read of the current browser session
	 * 2. subscribes to future auth changes from Supabase
	 *
	 * Safe to call multiple times; it only starts once.
	 */
	function start(): void {
		if (!browser || started) return;
		started = true;

		/*
		 * Initial sync so components get the current auth state
		 * even before any sign-in/sign-out event happens.
		 */
		void syncFromSession();

		/*
		 * Keep the store updated when auth changes in this tab,
		 * for example after sign in, sign out, token refresh, or user update.
		 */
		const { data } = supabase.auth.onAuthStateChange(
			(_event: AuthChangeEvent, session: Session | null) => {
				set({
					ready: true,
					user: session?.user ?? null
				});
			}
		);

		authSubscription = data.subscription;
	}

	/* Stops the store by unsubscribing from Supabase auth events. */
	function stop(): void {
		if (!started) return;
		started = false;

		authSubscription?.unsubscribe();
		authSubscription = null;
	}

	return {
		/*
		 * Standard Svelte store API.
		 *
		 * This allows:
		 * - import { auth } from '$lib/stores/auth'
		 * - use $auth in components
		 */
		subscribe,

		/* Public method to initialize the auth store. */
		init(): void { start(); },

		/* Public cleanup method. */
		destroy(): void { stop(); },

		/*
		 * Forces a fresh read of the current browser session.
		 *
		 * Return value:
		 * - the current User if authenticated
		 * - null otherwise
		 */
		async refresh(): Promise<User | null> {
			start();
			return await syncFromSession();
		},

		/*
		 * Returns the latest cached auth state synchronously,
		 * without triggering a new Supabase call.
		 */
		getSnapshot(): AuthState { return get(store); }
	};
}

/*
 * Exported auth store/service.
 *
 * In components:
 *   $auth.ready
 *   $auth.user
 *
 * In code:
 *   auth.init()
 *   await auth.refresh()
 *   auth.getSnapshot()
 */
export const auth = createAuthStore();