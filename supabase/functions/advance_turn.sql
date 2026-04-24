-- ============================================================
-- advance_turn(p_game_id uuid)
-- Called by:
--   1. Trigger on game_words INSERT (only when active player submits)
--   2. pg_cron job every 5 seconds for expired phase_deadline
-- ============================================================

CREATE OR REPLACE FUNCTION public.advance_turn(p_game_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_game              ranked_games%ROWTYPE;
    v_new_index         int;
    v_new_player_id     uuid;
    v_game_words_row_id uuid;
BEGIN
    -- Lock the game row to prevent concurrent execution
    -- (e.g. trigger and cron firing at the same time)
    SELECT * INTO v_game
    FROM ranked_games
    WHERE id = p_game_id
    FOR UPDATE;

    -- Guard: only run during word_input phase
    -- If the phase already changed (e.g. cron ran after trigger already advanced),
    -- this is a no-op
    IF v_game.phase != 'word_input' THEN
        RETURN;
    END IF;

    -- Guard: active_player_id must exist
    IF v_game.active_player_id IS NULL THEN
        RETURN;
    END IF;

    -- uuid if the player voted, NULL otherwise
    SELECT id INTO v_game_words_row_id
    FROM game_words
    WHERE game_id = p_game_id
    AND player_id = v_game.active_player_id
    AND round_number = v_game.round_number;


    -- If the deadline hasn't passed AND the active player hasn't submitted yet,
    -- do nothing (called too early — shouldn't happen but safe to guard)
    IF v_game.phase_deadline > now() AND v_game_words_row_id IS NULL THEN
        RETURN;
    END IF;

    -- If the active player timed out (deadline passed) and has no word yet,
    -- insert a NULL word row on their behalf
    IF v_game_words_row_id IS NULL THEN
        INSERT INTO game_words (game_id, player_id, word, round_number)
        VALUES (p_game_id, v_game.active_player_id, NULL, v_game.round_number);
    END IF;

    -- If v_game_words_row_id isn't null then the player correctly input the word before
    -- the timer ran out and just advance the turn

    -- Advance turn index
    v_new_index := v_game.turn_index + 1;

    -- Last player's turn just ended then move to voting phase
    IF v_new_index >= array_length(v_game.turn_order, 1) THEN
        UPDATE ranked_games SET
            active_player_id = NULL,
            turn_index       = 0,
            phase            = 'voting',
            phase_deadline   = now() + interval '60 seconds'
        WHERE id = p_game_id;

    -- Otherwise -> advance to next player
    ELSE
        v_new_player_id := v_game.turn_order[v_new_index + 1]; -- 1-based in Postgres

        UPDATE ranked_games SET
            turn_index       = v_new_index,
            active_player_id = v_new_player_id,
            phase_deadline   = now() + interval '15 seconds'
        WHERE id = p_game_id;
    END IF;
END;
$$;