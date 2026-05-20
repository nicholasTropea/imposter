CREATE OR REPLACE FUNCTION tally_votes(p_game_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_round             int;
    v_skips             int;
    v_max_votes         int;
    v_eliminated_id     uuid;
    v_eliminated_role   text;
    v_turn_order        uuid[];
    v_new_turn_order    uuid[];
    v_turn_index        int;
    v_new_turn_index    int;
    v_removed_position  int;
BEGIN
    -- get round number
    SELECT round_number, turn_order, turn_index INTO v_round, v_turn_order, v_turn_index
    FROM ranked_games
    WHERE id = p_game_id;

    -- count how many players chose to skip
    -- COUNT() returns 0 if no row is found
    SELECT COUNT(*) INTO v_skips
    FROM game_rounds
    WHERE game_id = p_game_id
    AND round_number = v_round
    AND target_player_id IS NULL
    AND voted = TRUE;

    -- find the highest number of votes any single player received.
    -- COALESCE handles the edge case where v_max_votes would be NULL
    -- (since MAX() returns NULL if no rows are found),
    -- turning NULL into 0 making the comparison still work
    -- COALESCE(a, b, ..., z) picks the first (left to right) value != NULL
    SELECT MAX(vote_count) INTO v_max_votes
    FROM (
        SELECT COUNT(*) AS vote_count
        FROM game_rounds
        WHERE game_id = p_game_id
        AND round_number = v_round
        AND target_player_id IS NOT NULL
        AND voted = TRUE
        GROUP BY target_player_id
    ) AS counts;

    -- if skips are equal to or exceed the top player vote count, no one is eliminated
    IF v_skips >= COALESCE(v_max_votes, 0) THEN
        UPDATE ranked_games SET
            phase            = 'results',
            active_player_id = NULL, -- signals (no elimination this round)
            phase_deadline   = now() + interval '10 seconds'
        WHERE id = p_game_id;
        RETURN;
    END IF;

    -- pick a random player among those tied at the top vote count
    SELECT target_player_id INTO v_eliminated_id
    FROM game_rounds
    WHERE game_id = p_game_id
    AND round_number = v_round
    AND target_player_id IS NOT NULL
    GROUP BY target_player_id
    HAVING COUNT(*) = v_max_votes
    ORDER BY random()
    LIMIT 1;

    -- retrieve 0-based index of the deleted player
    -- unnest expands the array into rows, ORDINALITY adds indices, so it returns:
    -- pid   i
    --  A    1
    --  B    2
    SELECT i - 1 INTO v_removed_position
    FROM unnest(v_turn_order) WITH ORDINALITY AS t(pid, i)
    WHERE pid = v_eliminated_id;

    -- build the new turn_order array with the leaving player removed (keeps order)
    SELECT ARRAY(
        SELECT pid
        FROM unnest(v_turn_order) AS t(pid)
        WHERE pid != v_eliminated_id
    ) INTO v_new_turn_order;

    -- adjust turn_index based on where the removed player was relative
    -- to the current turn:
    --
    --      case 1: removed player was BEFORE current index
    --          → every player shifted left by 1, so we decrement index to
    --          keep pointing at the same player
    --
    --      case 2: removed player was AT current index
    --          → their slot is gone, the next player slides into this index
    --          automatically, so no change needed
    --
    --      case 3: removed player was AFTER current index
    --          → nothing before or at the current position changed, no adjustment
    IF v_removed_position < v_turn_index THEN
        v_new_turn_index := v_turn_index - 1;
    ELSE
        v_new_turn_index := v_turn_index;
    END IF;

    -- guard: if the index now points past the end of the array
    -- (e.g. the last player in the order left), wrap back to 0.
    -- (second parameter is the dimension of the array (1D in this case))
    IF array_length(v_new_turn_order, 1) IS NULL
    OR v_new_turn_index >= array_length(v_new_turn_order, 1) THEN
        v_new_turn_index := 0;
    END IF;

    -- look up the eliminated player's role
    SELECT role INTO v_eliminated_role
    FROM ranked_game_players
    WHERE game_id = p_game_id
    AND user_id = v_eliminated_id;

    -- deduct elo from the eliminated player
    UPDATE players SET
        elo = elo - 10
    WHERE id = v_eliminated_id;

    -- transition to results phase with the eliminated player
    UPDATE ranked_games SET
        phase               =      'results',
        active_player_id    =      v_eliminated_id,
        eliminated_role     =      v_eliminated_role,
        turn_order          =      v_new_turn_order,
        turn_index          =      v_new_turn_index,
        phase_deadline      =      now() + interval '10 seconds'
    WHERE id = p_game_id;

    -- check if the game should end
    PERFORM check_game_end(p_game_id);
END;
$$;