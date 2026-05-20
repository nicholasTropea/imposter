CREATE OR REPLACE FUNCTION get_player_rank(p_user_id uuid)
-- STABLE tells no edits are made so that the query can be optimized
RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT rank::integer FROM (
        SELECT id, RANK() OVER (ORDER BY elo DESC) AS rank
        FROM players
    ) ranked
    WHERE id = p_user_id;
$$;