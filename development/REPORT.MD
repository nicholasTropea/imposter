# Imposter Words — Development Report

## User Authentication

Users must register an account and confirm their email address (if email confirmation is enabled in the Supabase project settings) before being able to log in. Unauthenticated users can only access public routes; any attempt to navigate to a protected route redirects them to the login page.

Upon successful registration, two rows are automatically created via a database trigger:

- A new row in the `profiles` table, storing the user's public information (e.g. nickname).
- A new row in the `settings` table, populated with default values. The user's starting Elo rating is set to **1000**.

## Login & Session Management

After a successful login, Supabase issues an active session to the client via two HTTP-only cookies (access token and refresh token). These cookies are automatically managed by the Supabase client and are used to authenticate subsequent requests. SvelteKit's server-side hooks read these cookies to determine the user's authentication state on every request, protecting server `load` functions and actions on guarded routes.

## Settings

The settings page is a form without an explicit save button. Instead, changes are persisted automatically using a **debounced autosave** strategy:

- Any change to a field (toggle, slider) starts an 800ms timer.
- If another change occurs before the timer expires, the timer resets.
- Once the timer completes without interruption, the accumulated changes are written to the `settings` table in a single database call.

The 800ms debounce window was chosen to allow the user to interact with multiple controls in quick succession (e.g. flipping several switches or dragging a slider) without triggering a separate API call for each individual change.

## Theme

The active theme is applied by a Svelte `$effect` rune in `routes/+layout.svelte`, which reads from the `themeStore` defined in `lib/stores/theme.svelte.ts`. The theme source depends on the user's authentication state:

- **Authenticated users:** the theme stored in the `settings` table is applied. This value is loaded server-side during the layout's `load` function and kept in sync with the store.
- **Unauthenticated users:** the browser's default `prefers-color-scheme` preference is used. When a new user completes registration, this detected preference is written to their `settings` row as the initial theme value, which they can later change from the settings page.

## Ranked Game Lookup

When a user initiates a ranked game search, they are redirected to a loading screen while matchmaking runs server-side. The lookup follows this logic:

1. Query the `ranked_games` table for any game with `status = 'waiting'`, ordered by creation time ascending (oldest first, as it is most likely to fill up soonest).
2. If a waiting game is found, the user is atomically added to it via the `ranked_game_players` table.
3. If no waiting game exists, a new one is created and the user is added as its first player.

Steps 1–3 are executed inside a single PostgreSQL function using `FOR UPDATE SKIP LOCKED` to prevent race conditions: if two users trigger the lookup simultaneously, one acquires the row lock and joins the existing game, while the other skips the locked row and creates a new one, ensuring no two players are accidentally placed in the same game slot twice.

Once assigned to a game, the client subscribes to that game's row via **Supabase Realtime**. When enough players have joined and the game's `status` is updated to `in_progress`, all subscribed clients receive the event and are simultaneously redirected to the game screen.

> **Note:** Elo-based matchmaking (pairing players of similar skill rating) is not implemented at this stage. Given the current low player count, all ranked players are pooled together regardless of Elo. Skill-based filtering will be introduced once the player base is large enough to support it without excessively increasing queue wait times.