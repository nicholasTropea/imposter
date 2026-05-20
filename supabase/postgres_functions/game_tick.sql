CREATE OR REPLACE FUNCTION game_tick()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    -- advance expired word_input turns
    PERFORM public.advance_turn(id)
    FROM ranked_games
    WHERE phase = 'word_input'
    AND status != 'finished'
    AND phase_deadline < now()
    AND active_player_id IS NOT NULL;

    -- advance from reveal phase
    PERFORM public.advance_reveal(id)
    FROM ranked_games
    WHERE phase = 'reveal'
    AND status != 'finished'
    AND phase_deadline < now();

    -- close expired voting
    PERFORM public.close_voting(id)
    FROM ranked_games
    WHERE phase = 'voting'
    AND status != 'finished'
    AND phase_deadline < now();

    -- start next round
    PERFORM public.advance_to_next_round(id)
    FROM ranked_games
    WHERE phase = 'results'
    AND status != 'finished'
    AND phase_deadline < now();
END;
$$;