-- Creates (or replaces) a function that either joins an existing ranked game
-- or creates a new one if none is available. Returns the game's UUID.
create or replace function join_or_create_ranked_game (p_user_id UUID) RETURNS UUID as $$

-- DECLARE is where you define local variables
DECLARE
    result_game_id UUID;  -- will hold the UUID of the game we find or create

-- BEGIN/END wraps the actual logic of the function
BEGIN
    -- pg_advisory_xact_lock acquires an application-level lock using an
    -- arbitrary integer as an identifier. Unlike row locks, this works even
    -- when there are no rows to lock (empty table). Only one transaction can
    -- hold this lock at a time — others wait until it's released.
    -- It's "xact" (transaction-level), meaning it auto-releases on commit/rollback.
    PERFORM pg_advisory_xact_lock(1001); -- 1001 = matchmaking

    -- SELECT INTO stores the query result into a variable.
    -- Finds the most populated game that still has room (player_count < max).
    -- If no rows match, game_id stays NULL.
    SELECT id INTO result_game_id
    FROM ranked_games
    WHERE status = 'waiting'
      AND player_count < max_players
    ORDER BY player_count DESC
    LIMIT 1;

    
    -- No available game found — create a new one and immediately assign a random word pair.
    -- RETURNING lets you capture the generated UUID immediately
    -- instead of doing a separate SELECT after the INSERT.
    IF result_game_id IS NULL THEN
        INSERT INTO ranked_games (words_id)
        VALUES ((SELECT id FROM words ORDER BY random() LIMIT 1))
        RETURNING id INTO result_game_id;        
    END IF;

    -- Add the player to the game.
    -- ON CONFLICT DO NOTHING prevents an error if they somehow call this twice
    -- (the PRIMARY KEY on ranked_game_players is (game_id, user_id)).
    INSERT INTO ranked_game_players (game_id, user_id)
    VALUES (result_game_id, p_user_id)
    ON CONFLICT DO NOTHING;

    -- Increment the player count and set the status to 'in-progress' if the game is full.
    UPDATE ranked_games
    SET
        player_count = player_count + 1,
        status = CASE
            WHEN player_count + 1 >= max_players THEN 'in_progress' -- Checks old player count
            ELSE 'waiting'
        END
    WHERE id = result_game_id;


    -- Randomly shuffle all players in the game, then assign roles and words:
    -- 1st player  → spy
    -- 2nd player  → imposter
    -- 3rd player  → imposter
    -- rest        → civilian
    -- ROW_NUMBER() OVER (ORDER BY random()) gives each player a random rank
    IF (SELECT status FROM ranked_games WHERE id = result_game_id) = 'in_progress' THEN
        -- Assign roles based on random shuffle
        UPDATE ranked_game_players
        SET role = CASE ranked.row_num
            WHEN 1 THEN 'spy'
            WHEN 2 THEN 'imposter'
            WHEN 3 THEN 'imposter'
            ELSE        'civilian'
        END
        FROM (
            SELECT user_id,
                   ROW_NUMBER() OVER (ORDER BY random()) AS row_num
            FROM ranked_game_players
            WHERE ranked_game_players.game_id = result_game_id
        ) AS ranked
        WHERE ranked_game_players.user_id = ranked.user_id
          AND ranked_game_players.game_id = result_game_id;

        
        -- Assign words based on role
        UPDATE ranked_game_players
        SET word = CASE ranked_game_players.role
            WHEN 'civilian' THEN words.civilian_word
            WHEN 'imposter' THEN words.imposter_word
            WHEN 'spy'      THEN NULL
        END
        FROM ranked_games
        JOIN words ON words.id = ranked_games.words_id
        WHERE ranked_game_players.game_id = result_game_id
        AND ranked_games.id = result_game_id;
    END IF;

    -- Returns the game UUID to the caller (the SvelteKit .rpc() call)
    RETURN result_game_id;
END;

-- Double dollar sign marks the end of the function body. LANGUAGE plpgsql tells Postgres
-- this is written in PL/pgSQL (Postgres's procedural language),
-- as opposed to plain SQL or other supported languages.
$$ LANGUAGE plpgsql;