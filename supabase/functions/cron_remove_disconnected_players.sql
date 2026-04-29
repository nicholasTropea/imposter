SELECT cron.schedule(
    'remove-disconnected-players',
    '15 seconds',
    $$
    DELETE FROM ranked_game_players
    WHERE last_seen < now() - interval '45 seconds';
    $$
);