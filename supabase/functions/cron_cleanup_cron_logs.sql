SELECT cron.schedule(
    'cleanup-cron-logs',
    '0 0 * * *', -- daily at midnight
    $$
    DELETE FROM cron.job_run_details
    WHERE end_time < now() - interval '1 days';
    $$
);