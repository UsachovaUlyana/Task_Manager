-- ЛР №2, часть A: все измерения для одного объёма данных (psql-переменная :target).
-- Вызывается из a1-growth.sql. В конце шага дополнительные индексы удаляются, чтобы
-- следующий объём снова измерялся «без индекса» и вставка шла без их обслуживания.

\echo
\echo '==================== Объём:' :target 'строк'
SELECT lab02.grow(:target);
VACUUM (ANALYZE) lab02.events;
SELECT lab02.record_sizes(:target, 'только PK');

\echo '--- Без дополнительных индексов (задания 4, 6, 7, 8, 11)'
SELECT * FROM lab02.measure('A', :target, 'user_eq', 'без индекса',
    $q$SELECT * FROM lab02.events WHERE user_id = 123$q$);
SELECT * FROM lab02.measure('A', :target, 'day', 'без индекса',
    $q$SELECT * FROM lab02.events WHERE created_at >= NOW() - INTERVAL '1 day'$q$);
SELECT * FROM lab02.measure('A', :target, 'half_year', 'без индекса',
    $q$SELECT * FROM lab02.events WHERE created_at >= NOW() - INTERVAL '180 days'$q$);
SELECT * FROM lab02.measure('A', :target, 'order', 'без индекса',
    $q$SELECT * FROM lab02.events WHERE user_id = 123 ORDER BY created_at DESC LIMIT 100$q$);
SELECT * FROM lab02.measure('A', :target, 'agg30', 'без индекса',
    $q$SELECT event_type, COUNT(*) FROM lab02.events WHERE created_at >= NOW() - INTERVAL '30 days' GROUP BY event_type$q$);
SELECT * FROM lab02.measure('A', :target, 'agg365', 'без индекса',
    $q$SELECT DATE(created_at), COUNT(*) FROM lab02.events WHERE created_at >= NOW() - INTERVAL '365 days' GROUP BY DATE(created_at)$q$);

\echo '--- Индексы (user_id) и (created_at) (задания 5, 6, 8)'
SELECT lab02.create_index(:target, 'idx_events_user_id', 'CREATE INDEX idx_events_user_id ON lab02.events (user_id)');
SELECT lab02.create_index(:target, 'idx_events_created_at', 'CREATE INDEX idx_events_created_at ON lab02.events (created_at)');
ANALYZE lab02.events;
SELECT * FROM lab02.measure('A', :target, 'user_eq', 'индексы',
    $q$SELECT * FROM lab02.events WHERE user_id = 123$q$);
SELECT * FROM lab02.measure('A', :target, 'day', 'индексы',
    $q$SELECT * FROM lab02.events WHERE created_at >= NOW() - INTERVAL '1 day'$q$);
SELECT * FROM lab02.measure('A', :target, 'half_year', 'индексы',
    $q$SELECT * FROM lab02.events WHERE created_at >= NOW() - INTERVAL '180 days'$q$);
SELECT * FROM lab02.measure('A', :target, 'order', 'индексы',
    $q$SELECT * FROM lab02.events WHERE user_id = 123 ORDER BY created_at DESC LIMIT 100$q$);
SELECT * FROM lab02.measure('A', :target, 'agg30', 'индексы',
    $q$SELECT event_type, COUNT(*) FROM lab02.events WHERE created_at >= NOW() - INTERVAL '30 days' GROUP BY event_type$q$);
SELECT * FROM lab02.measure('A', :target, 'agg365', 'индексы',
    $q$SELECT DATE(created_at), COUNT(*) FROM lab02.events WHERE created_at >= NOW() - INTERVAL '365 days' GROUP BY DATE(created_at)$q$);

\echo '--- Составной индекс (user_id, created_at DESC) (задание 7)'
SELECT lab02.create_index(:target, 'idx_events_user_created',
    'CREATE INDEX idx_events_user_created ON lab02.events (user_id, created_at DESC)');
ANALYZE lab02.events;
SELECT * FROM lab02.measure('A', :target, 'order', 'составной индекс',
    $q$SELECT * FROM lab02.events WHERE user_id = 123 ORDER BY created_at DESC LIMIT 100$q$);

SELECT lab02.record_sizes(:target, 'PK + 3 индекса');
DROP INDEX lab02.idx_events_user_id, lab02.idx_events_created_at, lab02.idx_events_user_created;
