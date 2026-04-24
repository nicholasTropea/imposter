-- ============================================================
-- Trigger function: fires AFTER INSERT on game_words
-- Only calls advance_turn if the inserting player is active_player_id
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_word_submitted()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Only advance the turn if the submitting player is the active one.
    -- Guards for old unsynced inserts (should not happen)
    IF EXISTS (
        SELECT 1 FROM ranked_games
        WHERE id = NEW.game_id
        AND active_player_id = NEW.player_id
        AND phase = 'word_input'
    ) THEN
        PERFORM public.advance_turn(NEW.game_id);
    END IF;

    RETURN NEW;
END;
$$;


CREATE TRIGGER on_word_submitted
    AFTER INSERT ON public.game_words
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_word_submitted();