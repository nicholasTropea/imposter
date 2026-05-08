CREATE OR REPLACE FUNCTION close_voting(p_game_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    -- guard: only act if still in voting phase
    IF NOT EXISTS (
        SELECT 1 FROM ranked_games
        WHERE id = p_game_id
        AND phase = 'voting'
    ) THEN
        RETURN;
    END IF;

    PERFORM tally_votes(p_game_id);
END;
$$;