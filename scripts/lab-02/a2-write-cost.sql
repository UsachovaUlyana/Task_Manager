-- ЛР №2, часть A, задание 9: цена индексов на запись.
-- Одни и те же данные (setseed) пишутся в таблицу только с PK и в таблицу с тремя индексами.
-- В обоих случаях в таблице заранее лежит 1 млн строк, чтобы индексы были не пустыми.

\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

DROP TABLE IF EXISTS lab02.events_write;
CREATE TABLE lab02.events_write (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    payload JSONB,
    created_at TIMESTAMP NOT NULL
);

\echo '=== Задание 9. Только PRIMARY KEY'
SELECT setseed(0.42);
SELECT 'базовый 1 млн строк: ' || lab02.generate_events('lab02.events_write', 1000000) || ' мс';
SELECT setseed(0.17);
SELECT lab02.timed_write('INSERT 1 000 000 строк', 1000000, 0,
    $q$SELECT lab02.generate_events('lab02.events_write', 1000000)$q$);
SELECT lab02.timed_write('UPDATE 100 000 строк (created_at)', 100000, 0,
    $q$UPDATE lab02.events_write SET created_at = created_at + INTERVAL '1 second' WHERE id <= 100000$q$);
SELECT lab02.timed_write('DELETE 100 000 строк', 100000, 0,
    $q$DELETE FROM lab02.events_write WHERE id > 1900000$q$);
SELECT 'таблица ' || pg_size_pretty(pg_relation_size('lab02.events_write'))
    || ', индексы ' || pg_size_pretty(pg_indexes_size('lab02.events_write'));

TRUNCATE lab02.events_write RESTART IDENTITY;
CREATE INDEX idx_events_write_user_id ON lab02.events_write (user_id);
CREATE INDEX idx_events_write_created_at ON lab02.events_write (created_at);
CREATE INDEX idx_events_write_user_created ON lab02.events_write (user_id, created_at DESC);

\echo '=== Задание 9. PRIMARY KEY + idx_events_user_id, idx_events_created_at, idx_events_user_created'
SELECT setseed(0.42);
SELECT 'базовый 1 млн строк: ' || lab02.generate_events('lab02.events_write', 1000000) || ' мс';
SELECT setseed(0.17);
SELECT lab02.timed_write('INSERT 1 000 000 строк', 1000000, 3,
    $q$SELECT lab02.generate_events('lab02.events_write', 1000000)$q$);
SELECT lab02.timed_write('UPDATE 100 000 строк (created_at)', 100000, 3,
    $q$UPDATE lab02.events_write SET created_at = created_at + INTERVAL '1 second' WHERE id <= 100000$q$);
SELECT lab02.timed_write('DELETE 100 000 строк', 100000, 3,
    $q$DELETE FROM lab02.events_write WHERE id > 1900000$q$);
SELECT 'таблица ' || pg_size_pretty(pg_relation_size('lab02.events_write'))
    || ', индексы ' || pg_size_pretty(pg_indexes_size('lab02.events_write'));

DROP TABLE lab02.events_write;
