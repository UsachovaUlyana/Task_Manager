-- ЛР №2, часть A, задание 11: запрос за весь год на максимальном объёме.
-- Индекс по created_at не может сократить объём работы: нужны все строки за год.
-- Для сравнения — другой способ получения данных: заранее посчитанная дневная сводка.

\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

-- повторный запуск не должен падать на остатках прошлого
DROP INDEX IF EXISTS lab02.idx_events_created_at;
DROP INDEX IF EXISTS lab02.idx_events_user_created;
DROP TABLE IF EXISTS lab02.events_daily;
DELETE FROM lab02.measurements
WHERE part = 'A'
  AND ((query = 'agg365' AND variant NOT IN ('без индекса', 'индексы'))
       OR (query = 'order' AND variant LIKE 'только составной%'));

SELECT count(*) AS volume FROM lab02.events \gset
\echo '=== Задание 11. GROUP BY DATE(created_at) за 365 дней,' :volume 'строк'

SELECT lab02.create_index(:volume, 'idx_events_created_at', 'CREATE INDEX idx_events_created_at ON lab02.events (created_at)');
VACUUM (ANALYZE) lab02.events;

\echo '--- индекс по created_at есть, VACUUM выполнен: план выбирает планировщик'
SELECT * FROM lab02.measure('A', :volume, 'agg365', 'индекс created_at после VACUUM',
    $q$SELECT DATE(created_at), COUNT(*) FROM lab02.events WHERE created_at >= NOW() - INTERVAL '365 days' GROUP BY DATE(created_at)$q$);

\echo '--- запрещаем Seq Scan: читаем только индекс (Index Only Scan)'
SET enable_seqscan = off;
SELECT * FROM lab02.measure('A', :volume, 'agg365', 'только индекс (enable_seqscan = off)',
    $q$SELECT DATE(created_at), COUNT(*) FROM lab02.events WHERE created_at >= NOW() - INTERVAL '365 days' GROUP BY DATE(created_at)$q$);
RESET enable_seqscan;

\echo '--- другой способ: дневная сводка events_daily (строится один раз, дальше дописывается)'
SELECT lab02.timed_write('построение сводки events_daily', :volume, 0,
    $q$CREATE TABLE lab02.events_daily AS
       SELECT DATE(created_at) AS day, event_type, count(*) AS cnt
       FROM lab02.events GROUP BY 1, 2$q$);
ALTER TABLE lab02.events_daily ADD PRIMARY KEY (day, event_type);
ANALYZE lab02.events_daily;
SELECT 'строк в сводке: ' || count(*) || ', размер ' || pg_size_pretty(pg_total_relation_size('lab02.events_daily'))
FROM lab02.events_daily;
SELECT * FROM lab02.measure('A', :volume, 'agg365', 'дневная сводка events_daily',
    $q$SELECT day, sum(cnt) FROM lab02.events_daily WHERE day >= (NOW() - INTERVAL '365 days')::date GROUP BY day$q$,
    'events_daily');

DROP INDEX lab02.idx_events_created_at;

\echo '=== Задание 7 на максимальном объёме: только составной индекс (без idx_events_user_id)'
SELECT lab02.create_index(:volume, 'idx_events_user_created',
    'CREATE INDEX idx_events_user_created ON lab02.events (user_id, created_at DESC)');
ANALYZE lab02.events;
SELECT * FROM lab02.measure('A', :volume, 'order', 'только составной индекс',
    $q$SELECT * FROM lab02.events WHERE user_id = 123 ORDER BY created_at DESC LIMIT 100$q$);
\echo '--- запрещаем bitmap: чтение индекса в порядке created_at DESC, без Sort'
SET enable_bitmapscan = off;
SELECT * FROM lab02.measure('A', :volume, 'order', 'только составной индекс, enable_bitmapscan = off',
    $q$SELECT * FROM lab02.events WHERE user_id = 123 ORDER BY created_at DESC LIMIT 100$q$);
RESET enable_bitmapscan;
DROP INDEX lab02.idx_events_user_created;
