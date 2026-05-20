CREATE OR REPLACE FUNCTION public.advance_reveal(p_game_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_game          ranked_games%ROWTYPE;
    v_new_index     int;
    v_new_player_id uuid;
BEGIN
    SELECT * INTO v_game
    FROM ranked_games
    WHERE id = p_game_id
    FOR UPDATE;

    -- guard: only run during reveal phase
    IF v_game.phase != 'reveal' THEN
        RETURN;
    END IF;

    -- advance turn index
    v_new_index := v_game.turn_index + 1;

    -- last player just revealed -> move to voting
    IF v_new_index >= array_length(v_game.turn_order, 1) THEN
        UPDATE ranked_games SET
            active_player_id = NULL,
            turn_index       = 0,
            phase            = 'voting',
            phase_deadline   = now() + interval '60 seconds'
        WHERE id = p_game_id;

    -- otherwise -> next player's word_input turn
    ELSE
        v_new_player_id := v_game.turn_order[v_new_index + 1]; -- 1-based in postgres

        UPDATE ranked_games SET
            turn_index       = v_new_index,
            active_player_id = v_new_player_id,
            phase            = 'word_input',
            phase_deadline   = now() + interval '15 seconds'
        WHERE id = p_game_id;
    END IF;
END;
$$;