CREATE OR REPLACE FUNCTION check_game_end(p_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_turn_order     uuid[];
    v_spy_count      int;
    v_imposter_count int;
    v_civilian_count int;
    v_winner         text;
BEGIN
    SELECT turn_order INTO v_turn_order
    FROM ranked_games
    WHERE id = p_game_id;

    SELECT
        COUNT(*) FILTER (WHERE role = 'spy'),
        COUNT(*) FILTER (WHERE role = 'imposter'),
        COUNT(*) FILTER (WHERE role = 'civilian')  
    INTO v_spy_count, v_imposter_count, v_civilian_count
    FROM ranked_game_players
    WHERE game_id = p_game_id
    AND user_id = ANY(v_turn_order);

    IF (
        (v_spy_count > 0 AND v_imposter_count = 0 AND v_civilian_count = 0) OR
        (v_spy_count > 0 AND array_length(v_turn_order, 1) = 2)
    ) THEN
        v_winner := 'spy';

    ELSIF (
        (v_imposter_count > 0 AND v_spy_count = 0 AND v_civilian_count = 0) OR
        (v_imposter_count > 0 AND v_spy_count = 0 AND array_length(v_turn_order, 1) = 2)
    ) THEN
        v_winner := 'imposter';

    ELSIF (v_civilian_count > 0 AND v_spy_count = 0 AND v_imposter_count = 0) THEN
        v_winner := 'civilian';

    END IF;

    IF v_winner IS NULL THEN
        RETURN;
    END IF;

    -- +25 to survived winners, -5 to survived losers
    UPDATE players
    SET elo = elo + CASE
        WHEN rgp.role = v_winner THEN 25
        ELSE -5
    END
    FROM ranked_game_players rgp
    WHERE players.id = rgp.user_id
    AND rgp.game_id = p_game_id
    AND rgp.user_id = ANY(v_turn_order); -- not eliminated

    UPDATE ranked_games SET
        status = 'finished',
        phase  = 'results',
        winner = v_winner
    WHERE id = p_game_id;
END;
$$;