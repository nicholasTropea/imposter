-- ============================================================
-- advance_turn(p_game_id uuid)
-- Called by:
--   1. Trigger on game_rounds INSERT (only when active player submits)
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
    v_game_rounds_row_id uuid;
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

    -- uuid if the player submitted, NULL otherwise
    SELECT game_id INTO v_game_rounds_row_id
    FROM game_rounds
    WHERE game_id = p_game_id
    AND player_id = v_game.active_player_id
    AND round_number = v_game.round_number;


    -- If the deadline hasn't passed AND the active player hasn't submitted yet,
    -- do nothing (called too early — shouldn't happen but safe to guard)
    IF v_game.phase_deadline > now() AND v_game_rounds_row_id IS NULL THEN
        RETURN;
    END IF;

    -- If the active player timed out (deadline passed) and has no word yet,
    -- insert a NULL word row on their behalf
    IF v_game_rounds_row_id IS NULL THEN
        INSERT INTO game_rounds (
            game_id,
            player_id,
            round_number,
            submitted_word,
            target_player_id,
            voted
        )
        VALUES (
            p_game_id,
            v_game.active_player_id,
            v_game.round_number,
            NULL,
            NULL,
            FALSE
        );
    END IF;

    -- transition to reveal phase
    UPDATE ranked_games SET
        phase = 'reveal',
        phase_deadline = now() + interval '5 seconds'
    WHERE ranked_games.id = p_game_id;
END;
$$;