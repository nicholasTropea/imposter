SELECT cron.schedule(
    'remove-disconnected-players',
    '15 seconds',
    $$
    DELETE FROM ranked_game_players
    USING ranked_games -- this is a join
    WHERE ranked_game_players.game_id = ranked_games.id
    AND ranked_game_players.last_seen < now() - interval '45 seconds'
    AND ranked_games.status != 'finished';
    $$
);