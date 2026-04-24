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
2. All players in the game are randomly shuffled using `ROW_NUMBER() OVER (ORDER BY random())` and assigned roles: the 1st player becomes the **spy**, the 2nd and 3rd become **imposters**, and the rest are **civilians**.
3. Each player's resolved word is written to their `ranked_game_players.word` column based on their role — civilians receive the civilian word, imposters receive the imposter word, and the spy receives `NULL`.
4. A random turn order is assigned, `turn_index` is set to 0, `active_player_id` is set to the first player in the order, and `phase` is set to `word_input` with a `phase_deadline` of 15 seconds from game start.

Because all steps occur within the same transaction, the Realtime notification that triggers client navigation to `/game` is only fired after the commit — guaranteeing that roles, words, and turn order are always set by the time any client fetches them. Players receive only their own word via RLS policies on `ranked_game_players`, preventing any client from reading another player's assigned word.

## Word Input Phase

During the word input phase, players take turns submitting a word to the `game_words` table in the order defined by `ranked_games.turn_order`. The phase is managed by three database-level components:

### Turn Enforcement

A `BEFORE INSERT` trigger (`guard_word_submission`) on the `game_words` table rejects any insert where the submitting player is not the current `active_player_id` in `word_input` phase. This prevents out-of-turn submissions at the database level, regardless of client behaviour.

### Turn Advancement

An `AFTER INSERT` trigger (`handle_word_submitted`) fires when a valid word is inserted. It calls `advance_turn(game_id)`, which:

1. Acquires a row-level lock on the game (`FOR UPDATE`) to prevent concurrent execution.
2. Verifies the game is still in `word_input` phase (idempotency guard).
3. Increments `turn_index` and updates `active_player_id` to the next player in `turn_order`.
4. Resets `phase_deadline` to `now() + 15 seconds` for the next player's turn.
5. If the last player has submitted, sets `active_player_id = NULL`, resets `turn_index` to 0, transitions `phase` to `voting`, and sets `phase_deadline` to `now() + 60 seconds`.

### Timeout Handling

A `pg_cron` job (`advance-expired-turns`) runs every 5 seconds and calls `advance_turn` for any game in `word_input` phase whose `phase_deadline` has passed. If the active player has no submitted word when `advance_turn` is called after a deadline, a `NULL` word row is inserted on their behalf before the turn advances. The `FOR UPDATE` lock inside `advance_turn` ensures that if the cron job and a late word submission trigger fire simultaneously, only one proceeds and the other becomes a no-op.

## Player Disconnection

To detect when a player closes their tab, loses connectivity, or navigates away, the application uses a **heartbeat mechanism**. While on any game-related page (loading screen, lobby, or active game), the client sends a ping to `POST /api/heartbeat` every 5 seconds using `navigator.sendBeacon`. This updates the player's `last_seen` timestamp in `ranked_game_players`.

A `pg_cron` job runs every 15 seconds and removes any player whose `last_seen` has not been updated within that window:

```sql
DELETE FROM ranked_game_players
WHERE last_seen < now() - interval '15 seconds';
```

`sendBeacon` is used instead of `fetch` because it is fire-and-forget and is guaranteed to be dispatched even when the page is being unloaded, making it reliable for close and navigation events. When a player is removed, a `DELETE` trigger (`handle_player_leave`) on `ranked_game_players` automatically decrements `player_count` on the corresponding `ranked_games` row and adjusts `turn_order` and `turn_index` if the game is in progress, keeping the turn state consistent regardless of the deletion source.