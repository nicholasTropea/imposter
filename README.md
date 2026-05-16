# Imposter Words

## Overview

Imposter Words is a real-time social deduction word game built as a web application. Players can create an account, join ranked online matches, wait in a multiplayer lobby, play through a phase-based game loop, and view the final result with Elo updates.

The project also includes a local game mode that runs entirely client-side and remains playable offline by passing a single device between players. The application is installable as a Progressive Web App (PWA), supports offline loading of the application shell and static assets, and uses shared connectivity utilities to detect and guard online-only actions.

The routing structure now separates offline-capable shell routes from authenticated server-backed areas. The root route `/` is configured as a client-only prerendered entry page, `/home` is intentionally accessible offline, and only actions or pages that truly require live backend access remain protected through the `(protected)` route group.

## Tech Stack

The application uses the following stack:

- **Frontend:** SvelteKit 5, TypeScript
- **UI library:** m3-svelte
- **Backend platform:** Supabase
- **Database:** PostgreSQL
- **Realtime:** Supabase Realtime
- **Authentication:** Supabase Auth
- **Background jobs / scheduling:** `pg_cron`
- **PWA tooling:** `@vite-pwa/sveltekit`
- **Package manager:** npm

SvelteKit handles routing, layouts, server `load` functions, form actions, and client-side navigation. Supabase provides authentication, PostgreSQL storage, Row Level Security, Realtime subscriptions, and RPC-backed game logic.

The frontend also includes a shared connectivity layer composed of `lib/stores/network.ts`, `lib/utils/checkConnection.ts`, and `lib/utils/onlineGuard.ts`. These files provide global offline state, real network verification, and reusable guards for online-only navigation and form submissions.

## Authentication

Users register an account and confirm their email address if email confirmation is enabled in the Supabase project settings. Upon successful registration, a database trigger named `handle_new_user` inserts one row into the `players` table and one row into the `settings` table, with the initial Elo set to 1000.

Authentication is split between client-side state and server-protected route groups. Client-side auth state is initialized through `lib/stores/auth.ts` for reactive UI and navigation decisions, while authenticated server-backed sections remain guarded through the `(protected)` route group rather than through global layout-level server loading.

This means `/home` is no longer treated as a fully protected server route. Instead, it remains available offline as part of the application shell, while operations that require a live Supabase session are guarded individually through online-gated navigation, form handlers, and protected server routes where appropriate.

## Settings

The settings page persists changes automatically through a debounced autosave mechanism. The page does not use an explicit save button.

Each change updates a full in-memory settings snapshot and starts an 800ms timer. If the user changes another control before the timer expires, the timer resets. Once the timer completes without interruption, the latest snapshot is sent to the `saveSettings` server action in a single request.

The page now uses two localStorage-backed layers to support offline editing after the protected route has already loaded. A `settings_local_draft` entry stores the latest full local snapshot so the UI can survive refreshes, while a separate `settings_pending_sync` entry stores the latest version that still needs to be written to the backend.

When the client is offline, settings changes are still applied locally, persisted to localStorage, and marked for later synchronization instead of being discarded. When connectivity returns, the page automatically retries the pending payload and clears the pending-sync entry after a successful save.

This allows the settings page to remain usable after load even though entering it still requires an authenticated online server request. In practice, the page behaves like an offline-capable editor layered on top of a protected server-backed route.

## Theme

Theme state is now managed through `lib/stores/theme.svelte.ts` as a shared Svelte 5 rune-based module. The store tracks `dark`, `contrast`, and `initialized` state, resolves the initial theme from `localStorage` or `prefers-color-scheme`, and persists user-selected light or dark mode back to `localStorage`.

The theme module also acts as the single global theme manager for the app. Instead of relying on a layout-level reactive effect to notice theme changes and toggle document classes, the store applies the correct CSS class directly to `document.documentElement` whenever the theme or contrast changes.

This moved the global DOM side effect into the same module that owns theme state. In practice, this made theme switching more reliable because theme changes now follow one explicit path: update shared state, persist the preference, and immediately apply the root document class.

The root `routes/+layout.svelte` has therefore been simplified. It still imports the theme stylesheets, initializes the shared theme store on startup, registers the service worker, initializes the client auth store, and renders the global offline pill and snackbar, but it no longer needs a dedicated reactive effect just to synchronize document theme classes.

For authenticated sections, database-backed theme preferences can still be loaded from the `settings` table and then pushed into the shared theme manager when needed. This allows persisted account settings to override browser-derived defaults while keeping one centralized implementation for live theme application.

The settings page integrates directly with this shared theme manager, so changing the theme preference updates the current UI immediately while also feeding into the same persisted autosave flow used for the rest of the settings state.

## Ranked Matchmaking

When a user starts a ranked game search, the application redirects them to a loading screen while matchmaking runs on the backend. Matchmaking is implemented by the `join_or_create_ranked_game` PostgreSQL function.

The function follows this flow:

1. Query `ranked_games` for a game with `status = 'waiting'`, ordered by most populated first.
2. If a waiting game exists, add the user to it through `ranked_game_players`.
3. If no waiting game exists, create a new game with a random word pair from the `words` table and add the user as the first player.
4. Redirect the user to the lobby for the resolved game.

These steps run inside a single PostgreSQL transaction using `pg_advisory_xact_lock`, which prevents race conditions when multiple players enter matchmaking at the same time.

Elo-based matchmaking is not yet applied. All ranked players currently share the same queue regardless of rating.

## Game Lobby

After matchmaking, players enter a lobby and wait for the game to fill. The lobby uses a two-layer data model:

- **Initial render:** the server `load` function fetches the current player list from `ranked_game_players`, joined with `players` to resolve nicknames.
- **Live updates:** a Supabase Realtime subscription listens for changes on `ranked_game_players` filtered by `game_id`, then refetches the full player list and updates the UI reactively.

A full refetch is used instead of patching from the Realtime payload because the payload does not include the joined nickname data.

The lobby also subscribes to `UPDATE` events on `ranked_games`. When the game status becomes `in_progress`, all connected clients navigate automatically to the corresponding game page.

To avoid a race condition where the game may already have started before the subscription becomes active, the lobby performs an immediate status check on mount and navigates directly if needed.

## Game Flow

The game logic is managed primarily at the database level. Each round progresses through this phase sequence:

```text
word_input → reveal → voting → results → word_input → …
```

A central `pg_cron` job named `game_tick` runs every 5 seconds and advances any game whose `phase_deadline` has expired.

### Game Start and role assignment

When the last player joins and the lobby reaches capacity, the `join_or_create_ranked_game` function initializes the game atomically in the same transaction as the player insertion.

The function:

1. Sets `ranked_games.status` to `in_progress`.
2. Randomly shuffles players and assigns roles.
3. Writes each player's resolved word to `ranked_game_players.word`.
4. Generates a random turn order.
5. Sets `turn_index = 0`, `active_player_id` to the first player, and the initial phase to `word_input` with a 15-second deadline.

The first player becomes the spy, the second becomes the imposter, and the remaining two become civilians. Civilians receive the civilian word, the imposter receives the imposter word, and the spy receives `NULL`.

### Word input

During `word_input`, players take turns submitting a word in the order defined by `turn_order`.

A `BEFORE INSERT` trigger named `guard_word_submission` on `game_rounds` ensures that only the current `active_player_id` can submit during `word_input`.

An `AFTER INSERT` trigger named `handle_word_submitted` calls `advance_turn(game_id)`, which transitions the game to `reveal` and sets a 5-second deadline. If a player does not submit before the deadline, the cron-driven timeout path inserts a `NULL` submission on their behalf and advances the game.

### Reveal

During `reveal`, all clients display the active player's submitted word or a “not submitted” indicator for 5 seconds.

When the reveal deadline expires, `advance_reveal` moves to the next player's `word_input` turn. If the last player's word has already been revealed, the game transitions to `voting` with a 60-second deadline.

### Voting

During `voting`, players vote to eliminate one of the remaining participants through the `cast_vote` PostgreSQL function.

Votes are written to `game_rounds`. Players may also cast a skip vote by sending `target_player_id = NULL`. When all players have voted, or when the voting deadline expires, `close_voting` calls `tally_votes`.

Vote resolution follows this logic:

- If one player has the most votes, that player is eliminated.
- If several players are tied for most votes, one of the tied players is eliminated at random.
- If skip has the most votes, no one is eliminated.

The eliminated player is removed from `turn_order`, receives a points penalty, and the game moves to `results`. `check_game_end` runs after elimination to determine whether the game has reached a win condition.

During the voting phase, players can also communicate through a Realtime broadcast chat channel. Messages are transient and are not persisted to the database.

### Results

During `results`, the client displays the eliminated player's identity and role, or a skip result if no one was removed. The `active_player_id` column is reused during this phase to point to the eliminated player for client lookup.

After the 10-second result timer expires, `advance_to_next_round` transitions the game back to `word_input`.

### Game end

`check_game_end` runs after each elimination. When a winning condition is satisfied, it sets `status = 'finished'` and records the winner.

Clients detect the end through the `ranked_games` `UPDATE` subscription:

- If the game ends during `results`, the client waits for the result timer before redirecting.
- If the game ends in another phase, the client redirects immediately.

## Player Disconnection

The application tracks player connectivity through a heartbeat mechanism. While a player is on a game-related page such as the loading screen, lobby, or active game, the client sends a heartbeat to `POST /api/heartbeat` every 5 seconds using `navigator.sendBeacon`.

Each heartbeat updates the player's `last_seen` timestamp in `ranked_game_players`.

A `pg_cron` job runs every 15 seconds and removes any player whose `last_seen` is older than 45 seconds, excluding finished games:

```sql
DELETE FROM ranked_game_players
USING ranked_games
WHERE ranked_game_players.game_id = ranked_games.id
AND ranked_game_players.last_seen < now() - interval '45 seconds'
AND ranked_games.status != 'finished';
```

`sendBeacon` is used because it is reliable during unload and navigation transitions.

When a player is removed, a `DELETE` trigger named `handle_player_leave` updates the game state safely by:

- locking the relevant game row,
- decrementing `player_count`,
- applying a points penalty only if the player had not already been eliminated,
- adjusting `turn_order` and `turn_index`,
- restarting `voting` if the disconnection happens during voting,
- calling `check_game_end` afterward.

A separate daily `pg_cron` job named `cleanup_cron_logs` deletes old rows from `cron.job_run_details`.

## Local Game Mode

The local game mode runs entirely client-side and remains playable offline. It is available under `/local_game`, and SSR is disabled for this route group because all data comes from browser-side sources such as `localStorage` and cached assets.

### Player setup

The settings page at `/local_game/settings` allows the host to add and remove player nicknames. The list is saved to `localStorage` under the `local_players` key so it survives refreshes.

A minimum of 4 players is required to start the game.

### Word pair loading

The play page resolves a word pair through a three-level fallback strategy:

1. **`localStorage` cache** — if a cached pair exists and is still valid, it is used immediately.
2. **Supabase** — if no valid cache exists and the device is online, a random pair is fetched from the `words` table and cached.
3. **Hardcoded fallback** — if no cache exists and the network is unavailable, a random pair is selected from `lib/data/wordPairs.ts`.

This guarantees that local mode always remains playable, even offline.

### Local game logic

All role assignment, phase progression, voting, elimination, and win condition checks run entirely on the client in `local_game/play/+page.svelte`.

The number of spies, imposters, and civilians scales with player count. A UUID generated through `crypto.randomUUID()` is used as a sentinel value for the skip vote to avoid collisions with player nicknames.

When the local game ends, players can either return to `/local_game/settings` to play again with an adjusted roster or navigate back to home, which clears the `local_players` key.

## Progressive Web App Setup

The application is configured as a Progressive Web App (PWA) using `@vite-pwa/sveltekit`, which integrates manifest generation and service worker support with SvelteKit.

The manifest defines the app name, short name, display mode (`standalone`), start URL, theme colors, and required icons. The application launches from `/`, and the app shell is designed to load even when the network is unavailable because static assets are precached for offline use.

The service worker is registered client-side from `routes/+layout.svelte` using `virtual:pwa-register`. Static assets are precached, and navigation fallback is configured so the application shell can still load when a route request cannot be fulfilled from the network.

In addition to service-worker-based offline loading, the app includes a global connectivity utility. `isEffectivelyOffline()` performs a real network probe instead of trusting `navigator.onLine` alone, `offline` exposes a shared store with polling and browser online/offline listeners, and `onlineGuard` provides reusable helpers for protecting navigation and form submissions that require a live connection.

The current routing design builds on that PWA setup by making both `/` and `/home` part of the offline-capable shell, while backend-dependent operations remain explicitly guarded. This makes the application more resilient under unstable connectivity without exposing server-backed actions indiscriminately.

## Type System

The file `lib/types/supabase.ts` is auto-generated from the Supabase schema and is kept aligned with database changes including table names, new columns, RPC functions, and enum updates.

A hand-authored file, `lib/types/overrides.ts`, defines `CastVoteArgs` so the `cast_vote` RPC accepts `p_target_id` as `string | null`, matching the skip-vote case where no target player is selected.

## Running the Project

Install dependencies with npm:

```bash
npm install
```

Run the development server:

```bash
npm run dev
```

Open the app in the browser:

```text
http://localhost:5173
```

Build the production version:

```bash
npm run build
```

Preview the production build locally:

```bash
npm run preview
```