-- Decrements the player count in `ranked_games` whenever a player row is deleted
-- from `ranked_game_players`. Triggered automatically on every DELETE, regardless
-- of whether the deletion was caused by the heartbeat cron job, a manual leave,
-- or any other code path.
-- If the game is in progress, updates the turn_order, turn_index and
-- active_player_id columns based on the index of the deleted player.
CREATE OR REPLACE FUNCTION handle_player_leave()
RETURNS trigger LANGUAGE plpgsql
AS $$
DECLARE
    v_game                      ranked_games%ROWTYPE;
    v_removed_player_position   int;
    v_new_players_array         uuid[];
    v_new_turn_index            int;

BEGIN
    -- Decrement player count
    UPDATE ranked_games
    SET player_count = player_count - 1
    WHERE id = OLD.game_id; -- OLD refers to the deleted row

    -- Get game information
    SELECT * INTO v_game
    FROM ranked_games
    WHERE ranked_games.id = OLD.game_id
    FOR UPDATE; -- locks the row until the transaction ends (handles simultaneus disconnections)

    -- If game hasn't started then only decrease the count
    IF v_game.status != 'in_progress' THEN
        RETURN OLD;
    END IF;

    -- Retrieve 0-based index of the deleted player
    -- unnest expands the array into rows, ORDINALITY adds indices, so it returns:
    -- pid   i
    --  A    1
    --  B    2
    SELECT i - 1 INTO v_removed_player_position
    FROM unnest(v_game.turn_order) WITH ORDINALITY AS t(pid, i)
    WHERE pid = OLD.user_id;

    -- Edge case in which player was not in turn_order
    IF v_removed_player_position IS NULL THEN
        RETURN OLD;
    END IF;

      -- Build the new turn_order array with the leaving player removed (keeps order)
    SELECT ARRAY(
        SELECT pid
        FROM unnest(v_game.turn_order) AS t(pid)
        WHERE pid != OLD.user_id
    ) INTO v_new_players_array;

    -- Adjust turn_index based on where the removed player was relative
    -- to the current turn:
    --
    --      Case 1: removed player was BEFORE current index
    --          → every player shifted left by 1, so we decrement index to
    --          keep pointing at the same player
    --
    --      Case 2: removed player was AT current index
    --          → their slot is gone, the next player slides into this index
    --          automatically, so no change needed
    --
    --      Case 3: removed player was AFTER current index
    --          → nothing before or at the current position changed, no adjustment
    IF v_removed_player_position < v_game.turn_index THEN
        v_new_turn_index := v_game.turn_index - 1;
    ELSE
        v_new_turn_index := v_game.turn_index;
    END IF;

    -- Guard: if the index now points past the end of the array
    -- (e.g. the last player in the order left), wrap back to 0.
    -- (second parameter is the dimension of the array (1D in this case))
    IF array_length(v_new_players_array, 1) IS NULL
    OR v_new_turn_index >= array_length(v_new_players_array, 1) THEN
        v_new_turn_index := 0;
    END IF;

    -- Update the game with the new turn order, corrected index,
    -- and the new active player derived from the updated array.
    -- Postgres arrays are 1-based, so add 1 to the 0-based index.
    UPDATE ranked_games SET
        turn_order       = v_new_players_array,
        turn_index       = v_new_turn_index,
        active_player_id = v_new_players_array[v_new_turn_index + 1]
    WHERE ranked_games.id = OLD.game_id;

    RETURN OLD;
END;
$$;

CREATE OR REPLACE TRIGGER on_player_leave
    AFTER DELETE ON ranked_game_players
    FOR EACH ROW EXECUTE PROCEDURE handle_player_leave();