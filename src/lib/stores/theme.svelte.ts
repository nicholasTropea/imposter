import { browser } from '$app/environment';

type Contrast = 'standard' | 'medium' | 'high';

/**
 * Shared global theme state for the currently running app instance.
 *
 * This module acts as a small theme manager:
 * - it stores the current dark/light mode
 * - it stores the selected contrast level
 * - it remembers whether the first browser initialization already happened
 * - it applies the correct theme class to `document.documentElement`
 */
export const themeStore = $state({
	dark: true,
	initialized: false,
	contrast: 'standard' as Contrast
});

/**
 * Maps the current `(dark, contrast)` combination to the CSS class
 * that should be present on the root `<html>` element.
 *
 * The imported theme CSS files define these classes globally.
 */
const classMap: Record<string, string> = {
	'false-standard': 'light',
	'true-standard': 'dark',
	'false-medium': 'light-medium-contrast',
	'true-medium': 'dark-medium-contrast',
	'false-high': 'light-high-contrast',
	'true-high': 'dark-high-contrast'
};

/**
 * Resolves the best initial dark/light mode from the browser.
 *
 * Priority:
 * 1. previously saved user choice from `localStorage`
 * 2. system preference via `prefers-color-scheme`
 * 3. fallback to dark mode when browser APIs are unavailable
 *
 * This function must be browser-guarded because `localStorage`
 * and `window.matchMedia` do not exist during SSR.
 *
 * @returns `true` when dark mode should be used initially, otherwise `false`.
 */
function getInitialTheme(): boolean {
	if (!browser) return true;

	const saved = localStorage.getItem('theme');
	if (saved === 'dark') return true;
	if (saved === 'light') return false;

	return window.matchMedia('(prefers-color-scheme: dark)').matches;
}

/**
 * Persists the user's dark/light preference in `localStorage`
 * so it survives reloads and future visits.
 *
 * @param value - `true` for dark mode, `false` for light mode.
 */
function persistTheme(value: boolean): void {
	if (!browser) return;
	localStorage.setItem('theme', value ? 'dark' : 'light');
}

/**
 * Applies the currently selected theme class to the root `<html>` element.
 *
 * This function is the bridge between reactive state and global DOM styling.
 * It first removes all known theme classes, then adds the single class that
 * matches the current `themeStore.dark` and `themeStore.contrast` values.
 *
 * It is intentionally centralized here so that theme changes always follow
 * the same code path, avoiding scattered DOM class manipulation in layouts
 * or individual pages.
 */
function applyThemeClass(): void {
	if (!browser) return;

	const all = Object.values(classMap);
	document.documentElement.classList.remove(...all);
	document.documentElement.classList.add(
		classMap[`${themeStore.dark}-${themeStore.contrast}`]
	);
}

/**
 * Performs one-time browser initialization of the theme store.
 *
 * Called once in routes/+layout.svelte.
 * 
 * On first run it:
 * - resolves the initial dark/light mode from browser state
 * - marks the store as initialized
 * - applies the matching theme class to `<html>`
 *
 * Repeated calls are safe; after initialization they do nothing.
 */
export function initThemeStore(): void {
	if (themeStore.initialized || !browser) return;

	themeStore.dark = getInitialTheme();
	themeStore.initialized = true;
	applyThemeClass();
}

/**
 * Updates the current dark/light mode, persists it locally,
 * and immediately reapplies the root document theme class.
 *
 * This should be the main public entry point for user-triggered
 * theme changes from settings pages, toggles, or startup sync.
 *
 * @param value - `true` for dark mode, `false` for light mode.
 */
export function setTheme(value: boolean): void {
	themeStore.dark = value;
	persistTheme(value);
	applyThemeClass();
}

/**
 * Updates the current contrast level and immediately reapplies
 * the root document theme class.
 *
 * Contrast is kept separate from dark/light mode so the app can support
 * combinations such as dark-high-contrast or light-medium-contrast.
 *
 * @param value - The new contrast mode to apply.
 */
export function setContrast(value: Contrast): void {
	themeStore.contrast = value;
	applyThemeClass();
}