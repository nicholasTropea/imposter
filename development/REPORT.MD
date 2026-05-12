# Imposter Words — Development Report

## User Authentication

Users must register an account and confirm their email address (if email confirmation is enabled in the Supabase project settings) before being able to log in. Unauthenticated users can only access public routes; any attempt to navigate to a protected route redirects them to the login page.

Upon successful registration, two rows are automatically created via a database trigger (`handle_new_user`):

- A new row in the `players` table, storing the user's public information (e.g. nickname, Elo rating, win counters).
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

When a user initiates a ranked game search, they are redirected to a loading screen while matchmaking runs server-side. The lookup is handled by the `join_or_create_ranked_game` PostgreSQL function and follows this logic:

1. Query the `ranked_games` table for any game with `status = 'waiting'`, ordered by most populated first (to fill games as quickly as possible).
2. If a waiting game is found, the user is atomically added to it via the `ranked_game_players` table.
3. If no waiting game exists, a new one is created with a randomly selected word pair from the `words` table, and the user is added as its first player.
4. The user is redirected to the game lobby page for the found or created game.

Steps 1–3 are executed inside a single PostgreSQL transaction using `pg_advisory_xact_lock` to prevent race conditions: if two users trigger the lookup simultaneously, one acquires the application-level lock and proceeds, while the other waits until the first transaction commits, ensuring no two players are accidentally placed in different games when one slot was available.

> **Note:** Elo-based matchmaking (pairing players of similar skill rating) is not implemented at this stage. Given the current low player count, all ranked players are pooled together regardless of Elo. Skill-based filtering will be introduced once the player base is large enough to support it without excessively increasing queue wait times.

## Game Lobby

Once redirected to the lobby, players wait for the game to fill up. The lobby page uses a two-layered data strategy to ensure the player list is always accurate:

- **Initial render:** the server `load` function fetches the current player list from `ranked_game_players`, joined with the `players` table to resolve nicknames. This data is returned to the page and rendered immediately on first load, before any client-side code runs.
- **Live updates:** a Supabase Realtime subscription on the `ranked_game_players` table listens for any `INSERT` or `DELETE` events filtered by `game_id`. On each event, the full player list is refetched and the UI is updated reactively. A full refetch is used rather than patching from the event payload because the payload only contains columns from `ranked_game_players` and does not include the joined `nickname` from the `players` table.

The lobby also subscribes to `UPDATE` events on the `ranked_games` table. When the game's `status` transitions to `in_progress`, all connected clients are automatically navigated to the game page via `goto()`. To guard against a race condition where the last player to join triggers the game start before their Realtime subscription is ready, the lobby checks the current game status immediately on mount and navigates directly if the game has already started.

Both Realtime subscriptions require the `ranked_game_players` and `ranked_games` tables to be included in the `supabase_realtime` PostgreSQL publication. The channel is cleaned up via `onMount`'s return callback when the component is destroyed.

## Game Start & Role Assignment

When the last player joins and the lobby reaches `max_players`, the `join_or_create_ranked_game` function handles game initialization atomically in the same transaction as the player insertion:

1. `ranked_games.status` is set to `in_progress`.
2. All players in the game are randomly shuffled using `ROW_NUMBER() OVER (ORDER BY random())` and assigned roles: the 1st player becomes the **spy**, the 2nd becomes the **imposter**, and the 3rd and 4th become **civilians**.
3. Each player's resolved word is written to their `ranked_game_players.word` column based on their role — civilians receive the civilian word, the imposter receives the imposter word, and the spy receives `NULL`.
4. A random turn order is assigned, `turn_index` is set to 0, `active_player_id` is set to the first player in the order, and `phase` is set to `word_input` with a `phase_deadline` of 15 seconds from game start.

Because all steps occur within the same transaction, the Realtime notification that triggers client navigation to `/game` is only fired after the commit — guaranteeing that roles, words, and turn order are always set by the time any client fetches them. Players receive only their own word via RLS policies on `ranked_game_players`, preventing any client from reading another player's assigned word.

## Game Loop

The game progresses through a series of phases managed entirely at the database level. The phase sequence per round is:

```text
word_input → reveal → voting → results → word_input (next round) → … → finished
```

A single `pg_cron` job (`game_tick`) runs every 5 seconds and acts as the central timeout dispatcher. It calls the appropriate advancement function for each game whose `phase_deadline` has expired, filtered to games with `status != 'finished'` to avoid processing completed games:

- `advance_turn` — called when a `word_input` deadline expires
- `advance_reveal` — called when a `reveal` deadline expires
- `close_voting` — called when a `voting` deadline expires (triggers `tally_votes`)
- `advance_to_next_round` — called when a `results` deadline expires

### Word Input Phase

During the word input phase, players take turns submitting a word in the order defined by `ranked_games.turn_order`. The phase is managed by three database-level components:

**Turn Enforcement:** A `BEFORE INSERT` trigger (`guard_word_submission`) on the `game_rounds` table rejects any insert where the submitting player is not the current `active_player_id` in `word_input` phase. This prevents out-of-turn submissions at the database level, regardless of client behaviour.

**Turn Advancement:** An `AFTER INSERT` trigger (`handle_word_submitted`) fires when a valid word is inserted. It calls `advance_turn(game_id)`, which acquires a row-level lock on the game (`FOR UPDATE`), verifies the game is still in `word_input` phase (idempotency guard), and transitions `phase` to `reveal` with a 5-second deadline for the submitted word to be shown.

**Timeout Handling:** If the active player does not submit before their deadline, `game_tick` calls `advance_turn`, which inserts a `NULL` word row on their behalf before advancing. The `FOR UPDATE` lock inside `advance_turn` ensures that if the cron job and a late submission trigger fire simultaneously, only one proceeds and the other becomes a no-op.

### Reveal Phase

During the reveal phase, all clients display the active player's submitted word (or a "not submitted" indicator if the word is `NULL`) for 5 seconds. Once the deadline expires, `advance_reveal` is called, which advances to the next player's `word_input` turn. If the last player's word has just been revealed, the phase instead transitions to `voting` with a 60-second deadline.

### Voting Phase

During the voting phase, players vote to eliminate one of the remaining players. Votes are cast via the `cast_vote` PostgreSQL function, which validates the vote and records it in the `game_rounds` table (updating the voter's row with `target_player_id` and `voted = true`). `game_rounds` has `REPLICA IDENTITY FULL` enabled, so the Realtime `UPDATE` payload includes both `old` and `new` rows, allowing the client to update vote counts correctly even when a player changes their vote.

Players may also cast a skip vote (represented as `target_player_id = NULL`). When all players have voted, or when the voting deadline expires (`close_voting`), `tally_votes` is called. It identifies the player(s) with the most votes:

- If one player has a clear majority, they are eliminated.
- If there is a tie, one of the tied players is eliminated at random.
- If skip has the most votes, no one is eliminated.

The eliminated player is removed from `turn_order`, has points deducted, and the game moves to the `results` phase. `check_game_end` is called after elimination to determine whether the game should end based on the remaining player composition.

During the voting phase, players can also communicate via a **real-time broadcast chat** channel. Messages are sent and received over the existing Supabase Realtime channel using the `broadcast` event type and are never persisted to the database. Chat is restricted to the voting phase only.

### Results Phase

During the results phase (10-second deadline), all clients display which player was eliminated and their role, or a "no one was eliminated" message if the vote was skipped. The `active_player_id` column is repurposed during this phase to carry the eliminated player's ID, allowing clients to look up their nickname and role. Once the deadline expires, `advance_to_next_round` transitions back to `word_input` for the next round.

### Game End

`check_game_end` is called after every elimination. It evaluates the remaining players in `turn_order` and sets `status = 'finished'` with an appropriate `winner` value if a winning condition is met. The client detects the game end via the `ranked_games` UPDATE subscription:

- If the game ends during the `results` phase, the client waits for the results timer to expire before redirecting to the end screen.
- If the game ends during any other phase, the client redirects immediately.

## Player Disconnection

To detect when a player closes their tab, loses connectivity, or navigates away, the application uses a **heartbeat mechanism**. While on any game-related page (loading screen, lobby, or active game), the client sends a ping to `POST /api/heartbeat` every 5 seconds using `navigator.sendBeacon`. This updates the player's `last_seen` timestamp in `ranked_game_players`.

A `pg_cron` job runs every 15 seconds and removes any player whose `last_seen` has not been updated within that window, skipping games that are already `finished`:

```sql
DELETE FROM ranked_game_players
USING ranked_games
WHERE ranked_game_players.game_id = ranked_games.id
AND ranked_game_players.last_seen < now() - interval '45 seconds'
AND ranked_games.status != 'finished';
```

`sendBeacon` is used instead of `fetch` because it is fire-and-forget and is guaranteed to be dispatched even when the page is being unloaded, making it reliable for close and navigation events. The heartbeat is stopped client-side as soon as the game's `status` transitions to `finished`.

When a player is removed, a `DELETE` trigger (`handle_player_leave`) on `ranked_game_players` automatically:

- Acquires a row-level lock before modifying game state.
- Decrements `player_count` on the corresponding `ranked_games` row.
- Only deducts points if the player has not already been eliminated.
- Adjusts `turn_order` and `turn_index` to keep the turn state consistent.
- If the game is in `voting` phase, restarts the voting phase and resets the timer.
- Calls `check_game_end` to determine whether the game should end as a result of the departure.

A separate daily `pg_cron` job (`cleanup_cron_logs`) deletes rows from `cron.job_run_details` older than 1 day to prevent the cron log table from growing unboundedly.

## Game Page

The game page (`/game/[gameId]`) is the main in-game view. Its server `load` function fetches the game state, all player nicknames, and the current player's role and word in parallel, then returns them for the initial render. It redirects to the lobby if the game is not `in_progress`, and to `/home` if the current user is not a participant.

The page renders one of four views depending on the current phase:

- **`word_input`** — displays whose turn it is, the player's secret word, and a submission form (only shown to the active player). The form prevents submitting an empty word or the player's own assigned word.
- **`reveal`** — displays the active player's submitted word for the round, or a "not submitted" indicator.
- **`voting`** — displays a grid of player cards, each showing the current vote count. Players tap a card to vote; tapping again or tapping a different card updates the vote. A skip button is also available. Each card has a word history button (📋) that opens a bottom sheet listing all words that player has submitted across rounds. A chat FAB (💬) opens the broadcast chat.
- **`results`** — displays the eliminated player's name and role (or a skip message), using `active_player_id` as a pointer to the eliminated player.

A fixed timer bar at the top of the screen reflects the remaining time in the current phase, driven by `phase_deadline` and updated every 100ms. Per-phase durations used for the progress calculation are: `word_input` 15s, `reveal` 5s, `voting` 60s, `results` 10s.

Players who have been eliminated (no longer in `ranked_game_players`) remain on the page as spectators — they can see all phases and chat history but cannot vote or submit words.

## Game End Page

The game end page (`/game/[gameId]/end`) is shown after the game finishes. Its server `load` function verifies the player participated in the game and that the game status is `finished`, then returns the player's role, current Elo, and a reconstructed Elo delta:

- **+25** — player won and survived (still present in `turn_order`)
- **−5** — player lost but survived
- **−10** — player was eliminated by vote

The page displays a Victory or Defeat label, the winning faction, the player's role, and an animated Elo counter that transitions from `previousElo` to `currentElo` over 1500ms using an ease-out cubic curve, starting after an 800ms delay. A "Back to Home" button returns the player to the home screen.

## Local Game Mode

The local game mode allows players to start a game locally, including offline, by passing a single device around. It is accessible from the home page and lives under the `/local_game` route. SSR is disabled for the entire route via `local_game/+layout.ts` (`ssr = false`) because all data is sourced client-side from `localStorage` and the Cache API.

### Player Setup

The settings page (`/local_game/settings`) lets the host add and remove player nicknames before starting the game. The player list is persisted to `localStorage` under the `local_players` key so it survives page refreshes. A minimum of 4 players is required to start. When the host navigates back to home, the key is removed.

### Word Pair Loading

The load function for the play page (`/local_game/play/+page.ts`) resolves a word pair through a three-tier fallback strategy:

1. **localStorage cache** — if a previously fetched pair is cached and not expired, it is served immediately without a network request.
2. **Supabase** — if no valid cache exists and the device is online, a random pair is fetched from the `words` table and written to the cache.
3. **Hardcoded fallback** — if both the cache and the network are unavailable, a pair is picked at random from a static list defined in `lib/data/wordPairs.ts`, ensuring the game is always playable offline.

### Game Logic

Role assignment, the game loop, voting, elimination, and win condition checks all run entirely client-side in `local_game/play/+page.svelte` with no database involvement. The number of spies, imposters, and civilians scales with player count. A UUID generated via `crypto.randomUUID()` is used as a sentinel value for the skip vote option, avoiding any string collision with player nicknames.

When the game ends, the host can choose to play again — which navigates back to `/local_game/settings` so players can also adjust the roster — or return to home, which clears the `local_players` key from `localStorage`.

## Progressive Web App Setup

The application is configured as a Progressive Web App (PWA) using `vite-plugin-pwa`. The plugin generates the web app manifest and service worker during the production build, enabling installability and offline asset caching.

The manifest defines the app name, short name, display mode (`standalone`), start URL, theme colors, and the required icons (`192x192` and `512x512`, with the larger icon also marked as `maskable`). In `app.html`, `theme-color` meta tags are provided separately for light and dark `prefers-color-scheme` values so the browser chrome better matches the active system theme.

The service worker is registered client-side from `routes/+layout.svelte` using the `virtual:pwa-register` helper. Static build assets are precached automatically through Workbox's generated service worker, allowing the application shell to load even when the network is unavailable.

At this stage, the PWA setup covers installability and offline caching of static assets. Route-level differentiation between browser visitors and installed-app launches is planned separately and is not yet part of this checkpoint.

## Type System

The `lib/types/supabase.ts` file is auto-generated from the Supabase schema and kept in sync with all database changes, including the renamed `game_rounds` table (previously `game_words`), new columns, new RPC functions, and the updated `game_phase` enum which now includes the `reveal` value.

A hand-authored `lib/types/overrides.ts` file provides a `CastVoteArgs` type that overrides the auto-generated `cast_vote` function args to allow `p_target_id` to be `string | null`, reflecting the skip-vote use case where no target is selected.