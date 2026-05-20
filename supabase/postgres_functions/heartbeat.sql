CREATE OR REPLACE FUNCTION public.heartbeat(p_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.ranked_game_players
    SET last_seen = now()
    WHERE game_id = p_game_id
    AND user_id = auth.uid();
END;
$$;