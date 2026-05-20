CREATE OR REPLACE FUNCTION advance_to_next_round(p_game_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_game ranked_games%ROWTYPE;
BEGIN
    SELECT * INTO v_game
    FROM ranked_games
    WHERE id = p_game_id
    FOR UPDATE;

    -- Guard: only act if still in results phase
    IF v_game.phase != 'results' THEN
        RETURN;
    END IF;

    UPDATE ranked_games SET
        phase            = 'word_input',
        round_number     = v_game.round_number + 1,
        turn_index       = 0,
        active_player_id = v_game.turn_order[1], -- 1-based in Postgres
        eliminated_role  = NULL,
        phase_deadline   = now() + interval '15 seconds'
    WHERE id = p_game_id;
END;
$$;