-- Schema dump from Supabase (public schema only)
-- Regenerate with:
-- pg_dump "postgresql://postgres.[PROJECT ID]:[DATABASE PASSWORD]@aws-1-eu-central-1.pooler.supabase.com:5432/postgres"
-- --schema-only --schema=public --no-owner --no-privileges --file supabase/schema.sql
--
-- PostgreSQL database dump
--

\restrict FEYhGgJ4WpJEQrJGLHOraS1wImyELdbcsavWMYl3ay1ncFXi0FAuGKcywzkt4kp

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.9 (Ubuntu 17.9-1.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: game_phase; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.game_phase AS ENUM (
    'word_input',
    'voting',
    'results',
    'reveal'
);


--
-- Name: theme_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.theme_type AS ENUM (
    'dark',
    'light'
);


--
-- Name: advance_reveal(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.advance_reveal(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: advance_to_next_round(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.advance_to_next_round(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_game ranked_games%ROWTYPE;
BEGIN
    SELECT * INTO v_game
    FROM ranked_games
    WHERE id = p_game_id
    FOR UPDATE;

    -- Guard: only act if still in results phase
    IF v_game.phase != 'results' THEN
        RETURN;
    END IF;

    UPDATE ranked_games SET
        phase            = 'word_input',
        round_number     = v_game.round_number + 1,
        turn_index       = 0,
        active_player_id = v_game.turn_order[1], -- 1-based in Postgres
        eliminated_role  = NULL,
        phase_deadline   = now() + interval '15 seconds'
    WHERE id = p_game_id;
END;
$$;


--
-- Name: advance_turn(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.advance_turn(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_game              ranked_games%ROWTYPE;
    v_new_index         int;
    v_new_player_id     uuid;
    v_game_rounds_row_id uuid;
BEGIN
    -- Lock the game row to prevent concurrent execution
    -- (e.g. trigger and cron firing at the same time)
    SELECT * INTO v_game
    FROM ranked_games
    WHERE id = p_game_id
    FOR UPDATE;
    
    -- Guard: only run during word_input phase
    -- If the phase already changed (e.g. cron ran after trigger already advanced),
    -- this is a no-op
    IF v_game.phase != 'word_input' THEN
        RETURN;
    END IF;

    -- Guard: active_player_id must exist
    IF v_game.active_player_id IS NULL THEN
        RETURN;
    END IF;

    -- uuid if the player submitted, NULL otherwise
    SELECT game_id INTO v_game_rounds_row_id
    FROM game_rounds
    WHERE game_id = p_game_id
    AND player_id = v_game.active_player_id
    AND round_number = v_game.round_number;


    -- If the deadline hasn't passed AND the active player hasn't submitted yet,
    -- do nothing (called too early — shouldn't happen but safe to guard)
    IF v_game.phase_deadline > now() AND v_game_rounds_row_id IS NULL THEN
        RETURN;
    END IF;

    -- If the active player timed out (deadline passed) and has no word yet,
    -- insert a NULL word row on their behalf
    IF v_game_rounds_row_id IS NULL THEN
        INSERT INTO game_rounds (
            game_id,
            player_id,
            round_number,
            submitted_word,
            target_player_id,
            voted
        )
        VALUES (
            p_game_id,
            v_game.active_player_id,
            v_game.round_number,
            NULL,
            NULL,
            FALSE
        );
    END IF;

    -- transition to reveal phase
    UPDATE ranked_games SET
        phase = 'reveal',
        phase_deadline = now() + interval '5 seconds'
    WHERE ranked_games.id = p_game_id;
END;
$$;


--
-- Name: cast_vote(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cast_vote(p_game_id uuid, p_voter_id uuid, p_target_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_turn_order     uuid[];                -- active players in the game
    v_vote_count     int;                   -- votes cast so far this round
    v_round          int;                   -- current round number
    v_round_row      game_rounds%ROWTYPE;   -- the voter's row for this round
BEGIN
    -- lock the game row for the duration of the transaction.
    -- this prevents two players submitting at the same time and both missing the
    -- phase transition
    SELECT turn_order, round_number
    INTO v_turn_order, v_round
    FROM ranked_games
    WHERE id = p_game_id
    AND phase = 'voting'
    FOR UPDATE;

    -- guard: game not found or not in voting phase
    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- fetch the voter's game_rounds row for this round.
    -- this row is created during the word_input phase upon word submit.
    SELECT * INTO v_round_row 
    FROM game_rounds
    WHERE game_id = p_game_id
    AND player_id = p_voter_id
    AND round_number = v_round;

    -- guard: voter has no round row, shouldn't happen in normal flow
    IF v_round_row IS NULL THEN
        RETURN;
    END IF;

    -- guard: target is not an active player (in game and not eliminated)
    IF (
        p_target_id IS NOT NULL AND
        NOT (p_target_id = ANY(v_turn_order))
    ) THEN
        RETURN;
    END IF;

    -- guard: player already voted that target this round
    IF (
        v_round_row.voted = true AND
        v_round_row.target_player_id IS NOT DISTINCT FROM p_target_id
    ) THEN
        RETURN;
    END IF;

    -- record the vote.
    -- target_player_id = NULL means the player chose to skip.
    UPDATE game_rounds
    SET target_player_id = p_target_id, voted = true
    WHERE game_id = p_game_id
    AND player_id = p_voter_id
    AND round_number = v_round;

    -- count how many players have voted so far this round (including skips)
    SELECT COUNT(*) INTO v_vote_count
    FROM game_rounds
    WHERE game_id = p_game_id
    AND round_number = v_round
    AND voted = TRUE;

    -- if not everyone has voted yet, nothing else to do
    -- TODO: v_player_count must account for eliminated players in future rounds
    IF v_vote_count < array_length(v_turn_order, 1) THEN
        RETURN;
    END IF;

    -- every player has voted
    PERFORM tally_votes(p_game_id);
END;
$$;


--
-- Name: check_game_end(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_game_end(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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


--
-- Name: close_voting(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.close_voting(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: game_tick(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.game_tick() RETURNS void
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: get_player_rank(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_player_rank(p_user_id uuid) RETURNS integer
    LANGUAGE sql STABLE
    AS $$
    SELECT rank::integer FROM (
        SELECT id, RANK() OVER (ORDER BY elo DESC) AS rank
        FROM players
    ) ranked
    WHERE id = p_user_id;
$$;


--
-- Name: guard_word_submission(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_word_submission() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$

BEGIN
  INSERT INTO public.Players (id, nickname)
  VALUES (
    new.id,
    new.raw_user_meta_data ->> 'nickname'
  );

  INSERT INTO public.Settings (user_id)
  VALUES (new.id);

  RETURN new;
END;

$$;


--
-- Name: handle_player_leave(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_player_leave() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_game                      ranked_games%ROWTYPE;
    v_removed_player_position   int;
    v_new_players_array         uuid[];
    v_new_turn_index            int;
BEGIN
    -- Get game information
    SELECT * INTO v_game
    FROM ranked_games
    WHERE ranked_games.id = OLD.game_id
    FOR UPDATE; -- locks the row until the transaction ends (handles simultaneus disconnections)

    -- Decrement player count
    UPDATE ranked_games
    SET player_count = player_count - 1
    WHERE id = OLD.game_id; -- OLD refers to the deleted row

    -- If game hasn't started then only decrease the count
    IF v_game.status != 'in_progress' THEN
        RETURN OLD;
    END IF;

    -- ── GAME IN PROGRESS ───────────────────────────────────────────────────────────────

    -- detract points from the leaving player's elo if he's not eliminated already
    IF (OLD.user_id = ANY(v_game.turn_order)) THEN
        UPDATE players
        SET elo = elo - 20
        WHERE id = OLD.user_id;
    END IF;

    -- Retrieve 0-based index of the deleted player
    -- unnest expands the array into rows, ORDINALITY adds indices, so it returns:
    -- pid   i
    --  A    1
    --  B    2
    SELECT i - 1 INTO v_removed_player_position
    FROM unnest(v_game.turn_order) WITH ORDINALITY AS t(pid, i)
    WHERE pid = OLD.user_id;

    -- player was not in turn_order (has been eliminated)
    IF v_removed_player_position IS NULL THEN
        RETURN OLD;
    END IF;

    -- Build the new turn_order array with the leaving player removed (keeps order)
    SELECT ARRAY(
        SELECT pid
        FROM unnest(v_game.turn_order) AS t(pid)
        WHERE pid != OLD.user_id
    ) INTO v_new_players_array;

    -- Adjust turn_index based on where the removed player was relative
    -- to the current turn:
    --
    --      Case 1: removed player was BEFORE current index
    --          → every player shifted left by 1, so we decrement index to
    --          keep pointing at the same player
    --
    --      Case 2: removed player was AT current index
    --          → their slot is gone, the next player slides into this index
    --          automatically, so no change needed
    --
    --      Case 3: removed player was AFTER current index
    --          → nothing before or at the current position changed, no adjustment
    IF v_removed_player_position < v_game.turn_index THEN
        v_new_turn_index := v_game.turn_index - 1;
    ELSE
        v_new_turn_index := v_game.turn_index;
    END IF;

    -- Guard: if the index now points past the end of the array
    -- (e.g. the last player in the order left), wrap back to 0.
    -- (second parameter is the dimension of the array (1D in this case))
    IF array_length(v_new_players_array, 1) IS NULL
    OR v_new_turn_index >= array_length(v_new_players_array, 1) THEN
        v_new_turn_index := 0;
    END IF;

    -- restart the voting phase in case it was active
    IF v_game.phase = 'voting' THEN
        -- wipe all votes for this round
        UPDATE game_rounds SET
            target_player_id = NULL,
            voted = FALSE
        WHERE game_id = OLD.game_id
        AND round_number = v_game.round_number;

        -- delete all entries of the leaving player
        DELETE FROM game_rounds
        WHERE game_id = OLD.game_id
        AND player_id = OLD.user_id;
    END IF;

    -- Update the game with the new turn order, corrected index,
    -- and the new active player derived from the updated array.
    -- Postgres arrays are 1-based, so add 1 to the 0-based index.
    -- update phase_deadline if the game is in the voting phase or if the leaving
    -- player is the active one, resetting the timer for the next player
    UPDATE ranked_games SET
        turn_order       = v_new_players_array,
        turn_index       = v_new_turn_index,
        active_player_id = v_new_players_array[v_new_turn_index + 1],
        phase_deadline = CASE
                            WHEN v_game.phase = 'voting'
                            THEN now() + interval '60 seconds'

                            WHEN (
                                v_game.phase = 'word_input' AND
                                v_game.active_player_id = OLD.user_id
                            )
                            THEN now() + interval '15 seconds'

                            ELSE phase_deadline
                         END
    WHERE ranked_games.id = OLD.game_id;

    -- check if the game should end
    PERFORM check_game_end(OLD.game_id);

    RETURN OLD;
END;
$$;


--
-- Name: handle_word_submitted(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_word_submitted() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
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


--
-- Name: heartbeat(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.heartbeat(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    UPDATE public.ranked_game_players
    SET last_seen = now()
    WHERE game_id = p_game_id
    AND user_id = auth.uid();
END;
$$;


--
-- Name: join_or_create_ranked_game(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_or_create_ranked_game(p_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$

-- DECLARE is where you define local variables
DECLARE
    v_result_game_id UUID;  -- will hold the UUID of the game we find or create
    v_turn_order     UUID[];
    v_status         text;

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
    SELECT id INTO v_result_game_id
    FROM ranked_games
    WHERE status = 'waiting'
      AND player_count < max_players
    ORDER BY player_count DESC
    LIMIT 1;

    
    -- No available game found — create a new one and immediately assign a random word pair.
    -- RETURNING captures the generated UUID immediately
    -- instead of doing a separate SELECT after the INSERT.
    IF v_result_game_id IS NULL THEN
        INSERT INTO ranked_games (words_id)
        VALUES ((SELECT id FROM words ORDER BY random() LIMIT 1))
        RETURNING id INTO v_result_game_id;        
    END IF;

    -- Add the player to the game.
    -- ON CONFLICT DO NOTHING prevents an error if they somehow call this twice
    -- (the PRIMARY KEY on ranked_game_players is (game_id, user_id)).
    INSERT INTO ranked_game_players (game_id, user_id)
    VALUES (v_result_game_id, p_user_id)
    ON CONFLICT DO NOTHING;

    -- Increment the player count and set the status to 'in-progress' if the game is full.
    UPDATE ranked_games
    SET
        player_count = player_count + 1,
        status = CASE
            WHEN player_count + 1 >= max_players THEN 'in_progress' -- Checks old player count
            ELSE 'waiting'
        END
    WHERE id = v_result_game_id
    RETURNING status INTO v_status;


    -- Randomly shuffle all players in the game, then assign roles and words:
    -- 1st player  -> spy
    -- 2nd player  -> imposter
    -- 3rd player  -> imposter
    -- rest        -> civilian
    -- ROW_NUMBER() OVER (ORDER BY random()) gives each player a random rank
    IF v_status = 'in_progress' THEN
        -- Assign roles based on random shuffle
        UPDATE ranked_game_players
        SET role = CASE ranked.row_num
            WHEN 1 THEN 'spy'
            WHEN 2 THEN 'imposter'
            ELSE        'civilian'
        END
        FROM (
            SELECT user_id,
                   ROW_NUMBER() OVER (ORDER BY random()) AS row_num
            FROM ranked_game_players
            WHERE ranked_game_players.game_id = v_result_game_id
        ) AS ranked
        WHERE ranked_game_players.user_id = ranked.user_id
          AND ranked_game_players.game_id = v_result_game_id;

        
        -- Assign words based on role
        UPDATE ranked_game_players
        SET word = CASE ranked_game_players.role
            WHEN 'civilian' THEN words.civilian_word
            WHEN 'imposter' THEN words.imposter_word
            WHEN 'spy'      THEN NULL
        END
        FROM ranked_games
        JOIN words ON words.id = ranked_games.words_id
        WHERE ranked_game_players.game_id = v_result_game_id
        AND ranked_games.id = v_result_game_id;

        -- Build a random turn order from all players in the game
        SELECT ARRAY(
            SELECT user_id
            FROM ranked_game_players
            WHERE game_id = v_result_game_id
            ORDER BY random()
        ) INTO v_turn_order;

        -- Store turn order, set first active player, set phase to word_input
        UPDATE ranked_games SET
            turn_order       = v_turn_order,
            turn_index       = 0,
            active_player_id = v_turn_order[1], -- 1-based in Postgres
            phase            = 'word_input',
            phase_deadline   = now() + interval '15 seconds' -- first turn starts immediately
        WHERE id = v_result_game_id;

        -- Notification: Game Started
        INSERT INTO public.notification_outbox (type, game_id, payload)
        VALUES (
            'game_start',
            v_result_game_id,
            jsonb_build_object(
                'message', 'The game has started!'
            )
        );
    END IF;

    -- Returns the game UUID to the caller (the SvelteKit .rpc() call)
    RETURN v_result_game_id;
END;

-- Double dollar sign marks the end of the function body. LANGUAGE plpgsql tells Postgres
-- this is written in PL/pgSQL (Postgres's procedural language),
-- as opposed to plain SQL or other supported languages.
$$;


--
-- Name: tally_votes(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tally_votes(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_round             int;
    v_skips             int;
    v_max_votes         int;
    v_eliminated_id     uuid;
    v_eliminated_role   text;
    v_turn_order        uuid[];
    v_new_turn_order    uuid[];
    v_turn_index        int;
    v_new_turn_index    int;
    v_removed_position  int;
BEGIN
    -- get round number
    SELECT round_number, turn_order, turn_index INTO v_round, v_turn_order, v_turn_index
    FROM ranked_games
    WHERE id = p_game_id;

    -- count how many players chose to skip
    -- COUNT() returns 0 if no row is found
    SELECT COUNT(*) INTO v_skips
    FROM game_rounds
    WHERE game_id = p_game_id
    AND round_number = v_round
    AND target_player_id IS NULL
    AND voted = TRUE;

    -- find the highest number of votes any single player received.
    -- COALESCE handles the edge case where v_max_votes would be NULL
    -- (since MAX() returns NULL if no rows are found),
    -- turning NULL into 0 making the comparison still work
    -- COALESCE(a, b, ..., z) picks the first (left to right) value != NULL
    SELECT MAX(vote_count) INTO v_max_votes
    FROM (
        SELECT COUNT(*) AS vote_count
        FROM game_rounds
        WHERE game_id = p_game_id
        AND round_number = v_round
        AND target_player_id IS NOT NULL
        AND voted = TRUE
        GROUP BY target_player_id
    ) AS counts;

    -- if skips are equal to or exceed the top player vote count, no one is eliminated
    IF v_skips >= COALESCE(v_max_votes, 0) THEN
        UPDATE ranked_games SET
            phase            = 'results',
            active_player_id = NULL, -- signals (no elimination this round)
            phase_deadline   = now() + interval '10 seconds'
        WHERE id = p_game_id;
        RETURN;
    END IF;

    -- pick a random player among those tied at the top vote count
    SELECT target_player_id INTO v_eliminated_id
    FROM game_rounds
    WHERE game_id = p_game_id
    AND round_number = v_round
    AND target_player_id IS NOT NULL
    GROUP BY target_player_id
    HAVING COUNT(*) = v_max_votes
    ORDER BY random()
    LIMIT 1;

    -- retrieve 0-based index of the deleted player
    -- unnest expands the array into rows, ORDINALITY adds indices, so it returns:
    -- pid   i
    --  A    1
    --  B    2
    SELECT i - 1 INTO v_removed_position
    FROM unnest(v_turn_order) WITH ORDINALITY AS t(pid, i)
    WHERE pid = v_eliminated_id;

    -- build the new turn_order array with the leaving player removed (keeps order)
    SELECT ARRAY(
        SELECT pid
        FROM unnest(v_turn_order) AS t(pid)
        WHERE pid != v_eliminated_id
    ) INTO v_new_turn_order;

    -- adjust turn_index based on where the removed player was relative
    -- to the current turn:
    --
    --      case 1: removed player was BEFORE current index
    --          → every player shifted left by 1, so we decrement index to
    --          keep pointing at the same player
    --
    --      case 2: removed player was AT current index
    --          → their slot is gone, the next player slides into this index
    --          automatically, so no change needed
    --
    --      case 3: removed player was AFTER current index
    --          → nothing before or at the current position changed, no adjustment
    IF v_removed_position < v_turn_index THEN
        v_new_turn_index := v_turn_index - 1;
    ELSE
        v_new_turn_index := v_turn_index;
    END IF;

    -- guard: if the index now points past the end of the array
    -- (e.g. the last player in the order left), wrap back to 0.
    -- (second parameter is the dimension of the array (1D in this case))
    IF array_length(v_new_turn_order, 1) IS NULL
    OR v_new_turn_index >= array_length(v_new_turn_order, 1) THEN
        v_new_turn_index := 0;
    END IF;

    -- look up the eliminated player's role
    SELECT role INTO v_eliminated_role
    FROM ranked_game_players
    WHERE game_id = p_game_id
    AND user_id = v_eliminated_id;

    -- deduct elo from the eliminated player
    UPDATE players SET
        elo = elo - 10
    WHERE id = v_eliminated_id;

    -- transition to results phase with the eliminated player
    UPDATE ranked_games SET
        phase               =      'results',
        active_player_id    =      v_eliminated_id,
        eliminated_role     =      v_eliminated_role,
        turn_order          =      v_new_turn_order,
        turn_index          =      v_new_turn_index,
        phase_deadline      =      now() + interval '10 seconds'
    WHERE id = p_game_id;

    -- check if the game should end
    PERFORM check_game_end(p_game_id);
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: game_rounds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_rounds (
    game_id uuid NOT NULL,
    player_id uuid NOT NULL,
    round_number integer NOT NULL,
    submitted_word text,
    target_player_id uuid,
    voted boolean DEFAULT false
);

ALTER TABLE ONLY public.game_rounds REPLICA IDENTITY FULL;


--
-- Name: notification_outbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_outbox (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    type text NOT NULL,
    game_id uuid,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    processed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: players; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.players (
    id uuid DEFAULT auth.uid() NOT NULL,
    nickname text NOT NULL,
    elo integer DEFAULT 1000 NOT NULL,
    played_games integer DEFAULT 0 NOT NULL,
    civilian_wins integer DEFAULT 0 NOT NULL,
    imposter_wins integer DEFAULT 0 NOT NULL,
    spy_wins integer DEFAULT 0 NOT NULL
);


--
-- Name: push_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    player_id uuid NOT NULL,
    endpoint text NOT NULL,
    p256dh text NOT NULL,
    auth text NOT NULL,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone DEFAULT now() NOT NULL,
    is_active boolean DEFAULT true NOT NULL
);


--
-- Name: ranked_game_players; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ranked_game_players (
    game_id uuid NOT NULL,
    user_id uuid NOT NULL,
    joined_at timestamp with time zone DEFAULT now(),
    role text,
    word text,
    last_seen timestamp with time zone DEFAULT now()
);


--
-- Name: ranked_games; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ranked_games (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    status text DEFAULT 'waiting'::text NOT NULL,
    max_players integer DEFAULT 4 NOT NULL,
    player_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    words_id bigint NOT NULL,
    turn_order uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    turn_index integer DEFAULT 0 NOT NULL,
    round_number integer DEFAULT 1 NOT NULL,
    active_player_id uuid,
    phase public.game_phase DEFAULT 'word_input'::public.game_phase NOT NULL,
    phase_deadline timestamp with time zone,
    eliminated_role text,
    winner text
);


--
-- Name: settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings (
    user_id uuid NOT NULL,
    theme public.theme_type DEFAULT 'dark'::public.theme_type NOT NULL,
    master_volume integer DEFAULT 100 NOT NULL,
    music_volume integer DEFAULT 100 NOT NULL,
    sound_effects boolean DEFAULT true NOT NULL,
    game_invites boolean DEFAULT true NOT NULL,
    daily_rewards boolean DEFAULT true NOT NULL
);


--
-- Name: words; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.words (
    id bigint NOT NULL,
    civilian_word text NOT NULL,
    imposter_word text NOT NULL
);


--
-- Name: words_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.words ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.words_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: game_rounds game_rounds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_rounds
    ADD CONSTRAINT game_rounds_pkey PRIMARY KEY (game_id, player_id, round_number);


--
-- Name: notification_outbox notification_outbox_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_outbox
    ADD CONSTRAINT notification_outbox_pkey PRIMARY KEY (id);


--
-- Name: players profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: players profiles_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT profiles_username_key UNIQUE (nickname);


--
-- Name: push_subscriptions push_subscriptions_endpoint_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_endpoint_key UNIQUE (endpoint);


--
-- Name: push_subscriptions push_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: ranked_game_players ranked_game_players_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ranked_game_players
    ADD CONSTRAINT ranked_game_players_pkey PRIMARY KEY (game_id, user_id);


--
-- Name: ranked_games ranked_games_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ranked_games
    ADD CONSTRAINT ranked_games_pkey PRIMARY KEY (id);


--
-- Name: settings settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (user_id);


--
-- Name: words words_created_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.words
    ADD CONSTRAINT words_created_at_key UNIQUE (civilian_word);


--
-- Name: words words_imposter_word_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.words
    ADD CONSTRAINT words_imposter_word_key UNIQUE (imposter_word);


--
-- Name: words words_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.words
    ADD CONSTRAINT words_pkey PRIMARY KEY (id);


--
-- Name: game_rounds before_word_submitted; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER before_word_submitted BEFORE INSERT ON public.game_rounds FOR EACH ROW EXECUTE FUNCTION public.guard_word_submission();


--
-- Name: ranked_game_players on_player_leave; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_player_leave AFTER DELETE ON public.ranked_game_players FOR EACH ROW EXECUTE FUNCTION public.handle_player_leave();


--
-- Name: game_rounds on_word_submitted; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_word_submitted AFTER INSERT ON public.game_rounds FOR EACH ROW EXECUTE FUNCTION public.handle_word_submitted();


--
-- Name: notification_outbox send_push_notification; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER send_push_notification AFTER INSERT ON public.notification_outbox FOR EACH ROW EXECUTE FUNCTION supabase_functions.http_request('https://rsimwvkiyhpfpjpqhche.supabase.co/functions/v1/send-push', 'POST', '{"Content-type":"application/json","Authorization":"Bearer SECRET_KEY"}', '{}', '5000');


--
-- Name: game_rounds game_rounds_game_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_rounds
    ADD CONSTRAINT game_rounds_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.ranked_games(id) ON DELETE CASCADE;


--
-- Name: game_rounds game_rounds_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_rounds
    ADD CONSTRAINT game_rounds_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: game_rounds game_rounds_target_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_rounds
    ADD CONSTRAINT game_rounds_target_player_id_fkey FOREIGN KEY (target_player_id) REFERENCES public.players(id) ON DELETE SET NULL;


--
-- Name: notification_outbox notification_outbox_game_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_outbox
    ADD CONSTRAINT notification_outbox_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.ranked_games(id) ON DELETE CASCADE;


--
-- Name: players profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: push_subscriptions push_subscriptions_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: ranked_game_players ranked_game_players_game_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ranked_game_players
    ADD CONSTRAINT ranked_game_players_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.ranked_games(id) ON DELETE CASCADE;


--
-- Name: ranked_game_players ranked_game_players_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ranked_game_players
    ADD CONSTRAINT ranked_game_players_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: ranked_games ranked_games_active_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ranked_games
    ADD CONSTRAINT ranked_games_active_player_id_fkey FOREIGN KEY (active_player_id) REFERENCES public.players(id);


--
-- Name: ranked_games ranked_games_words_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ranked_games
    ADD CONSTRAINT ranked_games_words_id_fkey FOREIGN KEY (words_id) REFERENCES public.words(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: settings settings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: words Authenticated users can read the word bank; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can read the word bank" ON public.words FOR SELECT TO authenticated USING (true);


--
-- Name: game_rounds Game rounds are viewable by participants; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Game rounds are viewable by participants" ON public.game_rounds FOR SELECT USING (true);


--
-- Name: ranked_games Games are viewable by everyone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Games are viewable by everyone" ON public.ranked_games FOR SELECT USING (true);


--
-- Name: ranked_game_players Lobby membership is viewable by everyone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Lobby membership is viewable by everyone" ON public.ranked_game_players FOR SELECT USING (true);


--
-- Name: game_rounds Players can insert their own round data; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Players can insert their own round data" ON public.game_rounds FOR INSERT TO authenticated WITH CHECK ((auth.uid() = player_id));


--
-- Name: players Public profiles are viewable by everyone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public profiles are viewable by everyone" ON public.players FOR SELECT USING (true);


--
-- Name: push_subscriptions Users can manage their own push subscriptions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can manage their own push subscriptions" ON public.push_subscriptions TO authenticated USING ((auth.uid() = player_id));


--
-- Name: settings Users can manage their own settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can manage their own settings" ON public.settings TO authenticated USING ((auth.uid() = user_id));


--
-- Name: players Users can update their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update their own profile" ON public.players FOR UPDATE TO authenticated USING ((auth.uid() = id));


--
-- Name: game_rounds; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.game_rounds ENABLE ROW LEVEL SECURITY;

--
-- Name: notification_outbox; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

--
-- Name: players; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;

--
-- Name: push_subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: ranked_game_players; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ranked_game_players ENABLE ROW LEVEL SECURITY;

--
-- Name: ranked_games; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ranked_games ENABLE ROW LEVEL SECURITY;

--
-- Name: settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

--
-- Name: words; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.words ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict FEYhGgJ4WpJEQrJGLHOraS1wImyELdbcsavWMYl3ay1ncFXi0FAuGKcywzkt4kp

