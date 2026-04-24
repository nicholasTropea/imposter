CREATE OR REPLACE FUNCTION public.guard_word_submission()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Reject the insert if the submitting player is not the active player
    IF NOT EXISTS (
        SELECT 1 FROM ranked_games
        WHERE id = NEW.game_id
        AND active_player_id = NEW.player_id
        AND phase = 'word_input'
    ) THEN
        RAISE EXCEPTION 'Player % is not the active player in game %', NEW.player_id, NEW.game_id;
    END IF;

    RETURN NEW; -- allow the insert
END;
$$;

CREATE TRIGGER before_word_submitted
    BEFORE INSERT ON public.game_words
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_word_submission();