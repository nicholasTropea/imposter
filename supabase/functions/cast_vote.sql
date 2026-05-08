CREATE OR REPLACE FUNCTION public.cast_vote(
    p_game_id    uuid, -- the game being played
    p_voter_id   uuid, -- the player casting the vote
    p_target_id  uuid  -- the player being voted against (NULL = skip)
) RETURNS void
LANGUAGE plpgsql
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