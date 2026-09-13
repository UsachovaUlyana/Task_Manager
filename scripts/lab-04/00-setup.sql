-- ЛР №4: схема lab04 на Primary — замеры отставания реплики.
-- lab04.sample_lag выполняется на Primary и раз в p_interval секунд записывает,
-- насколько Replica отстала: в байтах WAL и в секундах (по данным pg_stat_replication).

\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS lab04 CASCADE;
CREATE SCHEMA lab04;

CREATE TABLE lab04.lag_samples (
    id BIGSERIAL PRIMARY KEY,
    label TEXT NOT NULL,
    elapsed_ms NUMERIC NOT NULL,      -- время от начала замера
    lag_bytes BIGINT,                 -- сколько байт WAL Primary записал, а Replica ещё не применила
    write_lag_ms NUMERIC,             -- сколько Primary ждал бы записи WAL на Replica
    flush_lag_ms NUMERIC,             -- ... сброса на диск
    replay_lag_ms NUMERIC,            -- ... применения изменений
    state TEXT                        -- состояние walsender: streaming / catchup
);

CREATE FUNCTION lab04.sample_lag(p_label TEXT, p_seconds NUMERIC, p_interval NUMERIC DEFAULT 0.2)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    t0 TIMESTAMPTZ := clock_timestamp();
    max_lag BIGINT;
    max_replay NUMERIC;
    samples INT;
BEGIN
    DELETE FROM lab04.lag_samples WHERE label = p_label;

    WHILE extract(epoch FROM clock_timestamp() - t0) < p_seconds LOOP
        INSERT INTO lab04.lag_samples (label, elapsed_ms, lag_bytes, write_lag_ms, flush_lag_ms, replay_lag_ms, state)
        SELECT p_label,
               round(extract(epoch FROM clock_timestamp() - t0) * 1000, 1),
               pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn),
               round(extract(epoch FROM write_lag) * 1000, 1),
               round(extract(epoch FROM flush_lag) * 1000, 1),
               round(extract(epoch FROM replay_lag) * 1000, 1),
               state
        FROM pg_stat_replication;
        PERFORM pg_sleep(p_interval);
    END LOOP;

    SELECT count(*), max(lag_bytes), max(replay_lag_ms) INTO samples, max_lag, max_replay
    FROM lab04.lag_samples WHERE label = p_label;

    RETURN format('%s: замеров %s, максимум отставания %s (%s байт), максимум replay_lag %s мс',
                  p_label, samples, pg_size_pretty(max_lag), max_lag, coalesce(max_replay::text, '—'));
END
$$;
