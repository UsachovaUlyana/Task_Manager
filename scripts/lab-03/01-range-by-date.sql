-- ЛР №3, части 1–2, 8–9: RANGE-партиционирование events по дням, partition pruning, индексы.

\set ON_ERROR_STOP on
SET search_path = lab03, public;

\echo '=== Часть 1. Таблица events, партиции по дням'
CREATE TABLE events (
    id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    payload TEXT,
    created_at TIMESTAMP NOT NULL
) PARTITION BY RANGE (created_at);

CREATE TABLE events_2026_09_09 PARTITION OF events FOR VALUES FROM ('2026-09-09') TO ('2026-09-10');
CREATE TABLE events_2026_09_10 PARTITION OF events FOR VALUES FROM ('2026-09-10') TO ('2026-09-11');
CREATE TABLE events_2026_09_11 PARTITION OF events FOR VALUES FROM ('2026-09-11') TO ('2026-09-12');

\echo '--- 1 500 000 событий за 3 дня: view 60 %, login 25 %, purchase 13 %, click 2 %'
\timing on
INSERT INTO events (id, user_id, event_type, payload, created_at)
SELECT g,
       (random() * 100000)::bigint,
       CASE WHEN r < 0.60 THEN 'view' WHEN r < 0.85 THEN 'login' WHEN r < 0.98 THEN 'purchase' ELSE 'click' END,
       'payload #' || g,
       TIMESTAMP '2026-09-09' + random() * INTERVAL '3 days'
FROM (SELECT g, random() AS r FROM generate_series(1, 1500000) g) s;
\timing off
VACUUM (ANALYZE) events;

SELECT tableoid::regclass AS partition_name, COUNT(*)
FROM events
GROUP BY tableoid
ORDER BY partition_name;

\echo '--- Вопросы 1–2: граничные значения'
INSERT INTO events VALUES (2000001, 1, 'click', 'boundary', '2026-09-10 12:00:00'),
                          (2000002, 1, 'click', 'boundary', '2026-09-11 00:00:00');
SELECT tableoid::regclass AS partition_name, id, created_at FROM events WHERE id IN (2000001, 2000002) ORDER BY id;

\echo '--- Вопрос 3: запись за 2026-09-12 (партиции нет)'
SELECT lab03.try_sql($q$INSERT INTO lab03.events VALUES (2000003, 1, 'click', 'no partition', '2026-09-12 10:00:00')$q$);

\echo '--- Как PostgreSQL хранит границы партиций'
SELECT c.relname AS partition_name, pg_get_expr(c.relpartbound, c.oid) AS bounds
FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'lab03.events'::regclass ORDER BY 1;

\pset tuples_only on
\pset format unaligned

\echo '=== Часть 2. Partition pruning'
SELECT * FROM lab03.measure('1-2', 'count за 10 сентября', 'партиции по дням', $q$
SELECT COUNT(*) FROM lab03.events WHERE created_at >= '2026-09-10' AND created_at < '2026-09-11'$q$, 'lab03.events');

SELECT * FROM lab03.measure('1-2', 'count event_type = click', 'партиции по дням, без индекса', $q$
SELECT COUNT(*) FROM lab03.events WHERE event_type = 'click'$q$, 'lab03.events');

\echo '--- дополнительно: граница вычисляется при выполнении (now()) — отсечение на старте исполнения'
SELECT * FROM lab03.measure('1-2', 'count за последние сутки от now()', 'партиции по дням', $q$
SELECT COUNT(*) FROM lab03.events WHERE created_at >= now()::timestamp - INTERVAL '1 day'$q$, 'lab03.events');

\echo '--- для сравнения: та же выборка из обычной таблицы без партиций'
\pset tuples_only off
\pset format aligned
CREATE TABLE events_flat AS SELECT * FROM events;
VACUUM (ANALYZE) events_flat;
\pset tuples_only on
\pset format unaligned
SELECT * FROM lab03.measure('1-2', 'count за 10 сентября', 'обычная таблица', $q$
SELECT COUNT(*) FROM lab03.events_flat WHERE created_at >= '2026-09-10' AND created_at < '2026-09-11'$q$, 'lab03.events_flat');

\echo '=== Часть 8. Партиционирование и индексы'
\pset tuples_only off
\pset format aligned
CREATE INDEX idx_events_user_id ON events (user_id);
ANALYZE events;
\echo '--- индекс создан на родителе, PostgreSQL создал по индексу в каждой партиции'
SELECT i.inhrelid::regclass AS partition_index, pg_size_pretty(pg_relation_size(i.inhrelid)) AS size
FROM pg_inherits i WHERE i.inhparent = 'lab03.idx_events_user_id'::regclass ORDER BY 1;
\pset tuples_only on
\pset format unaligned
SELECT * FROM lab03.measure('8', 'сутки + user_id', 'партиции + индекс user_id', $q$
SELECT * FROM lab03.events WHERE created_at >= '2026-09-10' AND created_at < '2026-09-11' AND user_id = 12345$q$,
    'lab03.events');
SELECT * FROM lab03.measure('8', 'только user_id', 'партиции + индекс user_id', $q$
SELECT * FROM lab03.events WHERE user_id = 12345$q$, 'lab03.events');
\echo '--- для сравнения: обычная таблица с тем же индексом'
CREATE INDEX idx_events_flat_user_id ON events_flat (user_id);
ANALYZE events_flat;
SELECT * FROM lab03.measure('8', 'сутки + user_id', 'обычная таблица + индекс user_id', $q$
SELECT * FROM lab03.events_flat WHERE created_at >= '2026-09-10' AND created_at < '2026-09-11' AND user_id = 12345$q$,
    'lab03.events_flat');

\echo '=== Часть 9. Когда партиционирование не помогает: event_type = click'
SELECT * FROM lab03.measure('9', 'count event_type = click', 'партиции, без индекса event_type', $q$
SELECT COUNT(*) FROM lab03.events WHERE event_type = 'click'$q$, 'lab03.events');
CREATE INDEX idx_events_event_type ON events (event_type);
ANALYZE events;
SELECT * FROM lab03.measure('9', 'count event_type = click', 'партиции + индекс event_type', $q$
SELECT COUNT(*) FROM lab03.events WHERE event_type = 'click'$q$, 'lab03.events');
SELECT * FROM lab03.measure('9', 'count click за 10 сентября', 'партиции + индекс event_type', $q$
SELECT COUNT(*) FROM lab03.events WHERE event_type = 'click' AND created_at >= '2026-09-10' AND created_at < '2026-09-11'$q$,
    'lab03.events');

DROP TABLE events_flat;
