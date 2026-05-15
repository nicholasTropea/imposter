import { browser } from "$app/environment";

/*
 * Shared in-memory theme state for the current running app.
 *
 * Important:
 * - This variable starts as `true` by default.
 * - It is just a temporary default until the store initializes in the browser.
 */
let dark = $state(true);

/*
 * Says whether the first initialization has already been performed
 * from browser data (localStorage / system preference).
 *
 * Makes it so that initialization happens only once.
 */
let initialized = false;

/*
 * Reads the "best" initial theme from the browser.
 *
 * Priority:
 * 1. localStorage, if the user already chose a theme before
 * 2. system/browser preference (prefers-color-scheme)
 * 3. fallback to false/light
 *
 * Why the `browser` check?
 * In SvelteKit, code can run on the server too, and server code does not
 * have access to `window` or `localStorage`.
 */
function getInitialTheme(): boolean {
    if (!browser) return false;

    /*
	 * If the user previously chose a theme, it's stored in localStorage.
	 * That value should win over system preference.
	 */
    const saved = localStorage.getItem('theme');
    if (saved === 'dark') return true;
    if (saved === 'light') return false;

    /*
	 * If nothing was saved yet, use the operating system / browser preference.
	 */
    return window.matchMedia('(prefers-color-scheme: dark)').matches;
}

/*
 * Performs the first initialization of the store.
 *
 * This is "lazy initialization":
 * the store is NOT fully initialized as soon as this file is imported.
 * Instead, it is initialized only the first time someone actually uses it.
 *
 * Doing it lazily:
 * - avoids touching browser-only APIs too early
 * - keeps the code safe in SvelteKit
 * - ensures initialization happens only when needed
 */
function ensureInitialized(): void {
    /*
	 * If it has been initialized, do nothing.
	 * If not in the browser, also do nothing.
	 */
    if (initialized || !browser) return;

    /* Initialize */
    dark = getInitialTheme();

    /*
	 * Mark as initialized so this block never runs again in this app session.
	 */
    initialized = true;
}

/*
 * Saves the current theme choice in localStorage.
 *
 * This makes the choice survive:
 * - refreshes
 * - closing and reopening the browser
 * - app restarts
 */
function persist(value: boolean): void {
    if (!browser) return;
    localStorage.setItem('theme', value ? 'dark' : 'light');
}

/*
 * The object the rest of the app imports and uses.
 *
 * It exposes:
 * - init()      -> force initialization manually
 * - get dark()  -> read the current theme
 * - set dark()  -> update the theme
 */
export const themeStore = {
    /*
	 * Optional manual initialization.
	 *
	 * Called once in the root layout, so the theme is resolved
	 * as soon as the app starts in the browser.
	 *
	 * If init() has not been called, the getter will still initialize
	 * automatically the first time `themeStore.dark` is read.
	 */
    init() {
        ensureInitialized();
    },

    /*
	 * Getter for the current theme.
	 *
	 * Important:
	 * The FIRST time this getter is read in the browser, it automatically
	 * triggers initialization if it has not happened yet.
	 */
    get dark() {
        ensureInitialized();
        return dark;
    },
    
    /*
	 * Setter for the current theme.
	 *
	 * When the user changes theme:
	 * 1. update in-memory state immediately
	 * 2. save it to localStorage
	 *
	 * This means the UI updates right away, and the preference is remembered
	 * for future visits.
	 */
    set dark(v: boolean) {
        dark = v;
        persist(v);
    }
};