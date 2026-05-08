SELECT cron.schedule(
    'game-tick',
    '5 seconds',
    $$
        SELECT public.game_tick();
    $$
);