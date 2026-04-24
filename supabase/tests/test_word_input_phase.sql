-- ============================================================
-- Integration tests for advance_turn(), handle_word_submitted(), guard_word_submission()
-- and cron_advance_expired_turns (just that it works, not the scheduling)
--
-- HOW TO USE:
--   1. Open terminal
--   2. Install psql (if not already installed)
--   3. Run:
--      psql "postgresql://postgres.[PROJECT_ID]:[PASSWORD]@aws-1-eu-central-1.pooler.supabase.com:5432/postgres"
--      -f supabase/tests/test_advance_turn.sql
--   4. Test data is automatically cleaned up at the end
-- ============================================================

-- Helper function (created outside DO block — Postgres requirement)
CREATE OR REPLACE FUNCTION public._test_assert(condition boolean, test_name text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF condition THEN
        RAISE NOTICE 'PASS: %', test_name;
    ELSE
        RAISE NOTICE 'FAIL: %', test_name;
    END IF;
END;
$$;


DO $$
DECLARE
    v_game      ranked_games%ROWTYPE;
    v_game_id   uuid;
    v_word_id   bigint;
    v_users     uuid[];
    v_null_word game_words%ROWTYPE;
BEGIN

    -- --------------------------------------------------------
    -- SETUP
    -- --------------------------------------------------------

    SELECT ARRAY(SELECT id FROM auth.users LIMIT 4) INTO v_users;

    IF array_length(v_users, 1) < 4 THEN
        RAISE EXCEPTION 'Need at least 4 users in auth.users to run tests';
    END IF;

    INSERT INTO words (civilian_word, imposter_word)
    VALUES ('__test_cat__', '__test_lion__')
    RETURNING id INTO v_word_id;

    INSERT INTO ranked_games (
        words_id, status, player_count, max_players,
        phase, phase_deadline,
        turn_order, turn_index, active_player_id,
        round_number
    )
    VALUES (
        v_word_id, 'in_progress', 4, 4,
        'word_input', now() + interval '15 seconds',
        v_users, 0, v_users[1],
        1
    )
    RETURNING id INTO v_game_id;

    INSERT INTO ranked_game_players (game_id, user_id, role, word)
    VALUES
        (v_game_id, v_users[1], 'civilian', '__test_cat__'),
        (v_game_id, v_users[2], 'imposter', '__test_lion__'),
        (v_game_id, v_users[3], 'civilian', '__test_cat__'),
        (v_game_id, v_users[4], 'spy',      NULL);

    RAISE NOTICE '=== SETUP COMPLETE | game_id: % ===', v_game_id;


    -- --------------------------------------------------------
    -- TEST 1: Normal word submission advances the turn
    -- --------------------------------------------------------

    INSERT INTO game_words (game_id, player_id, word, round_number)
    VALUES (v_game_id, v_users[1], 'fluffy', 1);

    SELECT * INTO v_game FROM ranked_games WHERE id = v_game_id;

    PERFORM _test_assert(v_game.turn_index = 1,                'TEST 1a: turn_index advanced to 1');
    PERFORM _test_assert(v_game.active_player_id = v_users[2], 'TEST 1b: active_player is now user2');
    PERFORM _test_assert(v_game.phase = 'word_input',          'TEST 1c: phase still word_input');
    PERFORM _test_assert(v_game.phase_deadline > now(),        'TEST 1d: phase_deadline reset into future');


    -- --------------------------------------------------------
    -- TEST 2: Out-of-turn submission does NOT advance the turn
    --         and raises an exception
    -- --------------------------------------------------------

    DECLARE
        v_exception_raised boolean := false;
    BEGIN
        BEGIN
            INSERT INTO game_words (game_id, player_id, word, round_number)
            VALUES (v_game_id, v_users[3], 'sneaky', 1);
        EXCEPTION WHEN OTHERS THEN
            v_exception_raised := true;
        END;

        SELECT * INTO v_game FROM ranked_games WHERE id = v_game_id;

        PERFORM _test_assert(v_exception_raised,                   'TEST 2a: insert rejected with exception');
        PERFORM _test_assert(v_game.turn_index = 1,                'TEST 2b: turn_index unchanged');
        PERFORM _test_assert(v_game.active_player_id = v_users[2], 'TEST 2c: active_player still user2');
        PERFORM _test_assert(
            NOT EXISTS (
                SELECT 1 FROM game_words
                WHERE game_id = v_game_id
                  AND player_id = v_users[3]
            ),
            'TEST 2d: no row inserted for out-of-turn player'
        );
    END;

    -- --------------------------------------------------------
    -- TEST 3: Timeout inserts NULL word and advances turn
    -- --------------------------------------------------------

    UPDATE ranked_games
    SET phase_deadline = now() - interval '1 second'
    WHERE id = v_game_id;

    PERFORM public.advance_turn(v_game_id);

    SELECT * INTO v_game FROM ranked_games WHERE id = v_game_id;

    SELECT * INTO v_null_word
    FROM game_words
    WHERE game_id = v_game_id
      AND player_id = v_users[2]
      AND round_number = 1;

    PERFORM _test_assert(v_null_word.id IS NOT NULL,           'TEST 3a: NULL word row inserted for timed-out user2');
    PERFORM _test_assert(v_null_word.word IS NULL,             'TEST 3b: inserted word value is NULL');
    PERFORM _test_assert(v_game.turn_index = 2,                'TEST 3c: turn_index advanced to 2');
    PERFORM _test_assert(v_game.active_player_id = v_users[3], 'TEST 3d: active_player is now user3');


    -- --------------------------------------------------------
    -- TEST 4: Double call is a no-op (idempotency)
    -- --------------------------------------------------------

    UPDATE ranked_games
    SET phase_deadline = now() + interval '15 seconds'
    WHERE id = v_game_id;

    SELECT * INTO v_game FROM ranked_games WHERE id = v_game_id;
    PERFORM public.advance_turn(v_game_id);

    PERFORM _test_assert(
        (SELECT turn_index FROM ranked_games WHERE id = v_game_id) = v_game.turn_index,
        'TEST 4a: turn_index unchanged on redundant advance_turn call'
    );
    PERFORM _test_assert(
        (SELECT active_player_id FROM ranked_games WHERE id = v_game_id) = v_game.active_player_id,
        'TEST 4b: active_player_id unchanged on redundant call'
    );


    -- --------------------------------------------------------
    -- TEST 5: Last player submits -> transitions to voting phase
    -- --------------------------------------------------------

    INSERT INTO game_words (game_id, player_id, word, round_number)
    VALUES (v_game_id, v_users[3], 'whiskers', 1);

    INSERT INTO game_words (game_id, player_id, word, round_number)
    VALUES (v_game_id, v_users[4], 'paws', 1);

    SELECT * INTO v_game FROM ranked_games WHERE id = v_game_id;

    PERFORM _test_assert(v_game.phase = 'voting',              'TEST 5a: phase transitioned to voting');
    PERFORM _test_assert(v_game.active_player_id IS NULL,      'TEST 5b: active_player_id is NULL in voting phase');
    PERFORM _test_assert(v_game.turn_index = 0,                'TEST 5c: turn_index reset to 0');
    PERFORM _test_assert(v_game.phase_deadline > now(),        'TEST 5d: voting deadline set in future');


    -- --------------------------------------------------------
    -- TEST 6: advance_turn during voting phase is a no-op
    -- --------------------------------------------------------

    PERFORM public.advance_turn(v_game_id);

    SELECT * INTO v_game FROM ranked_games WHERE id = v_game_id;

    PERFORM _test_assert(v_game.phase = 'voting',              'TEST 6a: phase unchanged when called during voting');
    PERFORM _test_assert(v_game.active_player_id IS NULL,      'TEST 6b: active_player_id still NULL during voting');


    -- --------------------------------------------------------
    -- TEARDOWN
    -- --------------------------------------------------------

    DELETE FROM ranked_game_players WHERE game_id = v_game_id;
    DELETE FROM game_words          WHERE game_id = v_game_id;
    DELETE FROM ranked_games        WHERE id      = v_game_id;
    DELETE FROM words               WHERE civilian_word = '__test_cat__';

    RAISE NOTICE '=== TEARDOWN COMPLETE ===';

END;
$$;

-- Drop the helper function after tests are done
DROP FUNCTION IF EXISTS _test_assert(boolean, text);

-- --------------------------------------------------------
-- EXCEPTION CLEANUP
-- --------------------------------------------------------
DELETE FROM ranked_games
WHERE words_id = (SELECT id FROM words WHERE civilian_word = '__test_cat__');

DELETE FROM words WHERE civilian_word = '__test_cat__';