-- Decrements the player count in `ranked_games` whenever a player row is deleted
-- from `ranked_game_players`. Triggered automatically on every DELETE, regardless
-- of whether the deletion was caused by the heartbeat cron job, a manual leave,
-- or any other code path.
CREATE OR REPLACE FUNCTION handle_player_leave()
RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
    -- OLD refers to the deleted row
    UPDATE ranked_games
    SET player_count = player_count - 1
    WHERE id = OLD.game_id;

    RETURN OLD;
END;
$$;

CREATE OR REPLACE TRIGGER on_player_leave
    AFTER DELETE ON ranked_game_players
    FOR EACH ROW EXECUTE PROCEDURE handle_player_leave();