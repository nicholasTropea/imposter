SELECT cron.schedule(
    'advance-expired-turns',
    '5 seconds',
    $$
        SELECT public.advance_turn(id)
        FROM ranked_games
        WHERE phase = 'word_input'
        AND phase_deadline < now()
        AND active_player_id IS NOT NULL;
    $$
);