-- Schema dump from Supabase (public schema only)
-- Regenerate with:
-- pg_dump "postgresql://postgres.[PROJECT ID]:[DATABASE PASSWORD]@aws-1-eu-central-1.pooler.supabase.com:5432/postgres"
-- --schema-only --schema=public --no-owner --no-privileges --file supabase/schema.sql

--
-- PostgreSQL database dump
--

\restrict bG5fhBOkXH0ctUwvlF82nBKNtDpwrzRmucbXlJYHVL91ux6idg8Ba0OoqGaaxYR

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
-- Name: theme_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.theme_type AS ENUM (
    'dark',
    'light'
);


--
-- Name: advance_turn(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.advance_turn(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_game              ranked_games%ROWTYPE;
    v_new_index         int;
    v_new_player_id     uuid;
    v_game_words_row_id uuid;
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

    -- uuid if the player voted, NULL otherwise
    SELECT id INTO v_game_words_row_id
    FROM game_words
    WHERE game_id = p_game_id
    AND player_id = v_game.active_player_id
    AND round_number = v_game.round_number;


    -- If the deadline hasn't passed AND the active player hasn't submitted yet,
    -- do nothing (called too early — shouldn't happen but safe to guard)
    IF v_game.phase_deadline > now() AND v_game_words_row_id IS NULL THEN
        RETURN;
    END IF;

    -- If the active player timed out (deadline passed) and has no word yet,
    -- insert a NULL word row on their behalf
    IF v_game_words_row_id IS NULL THEN
        INSERT INTO game_words (game_id, player_id, word, round_number)
        VALUES (p_game_id, v_game.active_player_id, NULL, v_game.round_number);
    END IF;

    -- If v_game_words_row_id isn't null then the player correctly input the word before
    -- the timer ran out and just advance the turn

    -- Advance turn index
    v_new_index := v_game.turn_index + 1;

    -- Last player's turn just ended then move to voting phase
    IF v_new_index >= array_length(v_game.turn_order, 1) THEN
        UPDATE ranked_games SET
            active_player_id = NULL,
            turn_index       = 0,
            phase            = 'voting',
            phase_deadline   = now() + interval '60 seconds'
        WHERE id = p_game_id;

    -- Otherwise -> advance to next player
    ELSE
        v_new_player_id := v_game.turn_order[v_new_index + 1]; -- 1-based in Postgres

        UPDATE ranked_games SET
            turn_index       = v_new_index,
            active_player_id = v_new_player_id,
            phase_deadline   = now() + interval '15 seconds'
        WHERE id = p_game_id;
    END IF;
END;
$$;


--
-- Name: guard_word_submission(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_word_submission() RETURNS trigger
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
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_game                      ranked_games%ROWTYPE;
    v_removed_player_position   int;
    v_new_players_array         uuid[];
    v_new_turn_index            int;

BEGIN
    -- Decrement player count
    UPDATE ranked_games
    SET player_count = player_count - 1
    WHERE id = OLD.game_id; -- OLD refers to the deleted row

    -- Get game information
    SELECT * INTO v_game
    FROM ranked_games
    WHERE ranked_games.id = OLD.game_id
    FOR UPDATE; -- locks the row until the transaction ends (handles simultaneus disconnections)

    -- If game hasn't started then only decrease the count
    IF v_game.status != 'in_progress' THEN
        RETURN OLD;
    END IF;

    -- Retrieve 0-based index of the deleted player
    -- unnest expands the array into rows, ORDINALITY adds indices, so it returns:
    -- pid   i
    --  A    1
    --  B    2
    SELECT i - 1 INTO v_removed_player_position
    FROM unnest(v_game.turn_order) WITH ORDINALITY AS t(pid, i)
    WHERE pid = OLD.user_id;

    -- Edge case in which player was not in turn_order
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

    -- Update the game with the new turn order, corrected index,
    -- and the new active player derived from the updated array.
    -- Postgres arrays are 1-based, so add 1 to the 0-based index.
    UPDATE ranked_games SET
        turn_order       = v_new_players_array,
        turn_index       = v_new_turn_index,
        active_player_id = v_new_players_array[v_new_turn_index + 1]
    WHERE ranked_games.id = OLD.game_id;

    RETURN OLD;
END;
$$;


--
-- Name: handle_word_submitted(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_word_submitted() RETURNS trigger
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


--
-- Name: join_or_create_ranked_game(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_or_create_ranked_game(p_user_id uuid) RETURNS uuid
    LANGUAGE plpgsql
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
            WHEN 3 THEN 'imposter'
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
            SELECT id
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
    END IF;

    -- Returns the game UUID to the caller (the SvelteKit .rpc() call)
    RETURN v_result_game_id;
END;

-- Double dollar sign marks the end of the function body. LANGUAGE plpgsql tells Postgres
-- this is written in PL/pgSQL (Postgres's procedural language),
-- as opposed to plain SQL or other supported languages.
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: game_words; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_words (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    game_id uuid NOT NULL,
    player_id uuid NOT NULL,
    word text,
    round_number integer NOT NULL
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
    phase text DEFAULT 'word_input'::text NOT NULL,
    phase_deadline timestamp with time zone
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
-- Name: game_words game_words_game_id_player_id_round_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_words
    ADD CONSTRAINT game_words_game_id_player_id_round_number_key UNIQUE (game_id, player_id, round_number);


--
-- Name: game_words game_words_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_words
    ADD CONSTRAINT game_words_pkey PRIMARY KEY (id);


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
-- Name: game_words before_word_submitted; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER before_word_submitted BEFORE INSERT ON public.game_words FOR EACH ROW EXECUTE FUNCTION public.guard_word_submission();


--
-- Name: ranked_game_players on_player_leave; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_player_leave AFTER DELETE ON public.ranked_game_players FOR EACH ROW EXECUTE FUNCTION public.handle_player_leave();


--
-- Name: game_words on_word_submitted; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_word_submitted AFTER INSERT ON public.game_words FOR EACH ROW EXECUTE FUNCTION public.handle_word_submitted();


--
-- Name: game_words game_words_game_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_words
    ADD CONSTRAINT game_words_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.ranked_games(id) ON DELETE CASCADE;


--
-- Name: game_words game_words_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_words
    ADD CONSTRAINT game_words_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;


--
-- Name: players profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON UPDATE CASCADE ON DELETE CASCADE;


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
-- PostgreSQL database dump complete
--

\unrestrict bG5fhBOkXH0ctUwvlF82nBKNtDpwrzRmucbXlJYHVL91ux6idg8Ba0OoqGaaxYR

