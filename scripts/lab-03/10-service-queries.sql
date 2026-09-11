-- ЛР №3, часть 12: запросы сервиса к tasks до и после партиционирования по created_at.
-- Запускается дважды через run-service-part.sh: variant=before (до миграции 012), variant=after (после).
-- Запросы повторяют форму SQL, который строит EF Core для endpoint'ов API (часть по таблице tasks).

\set ON_ERROR_STOP on
SET TimeZone = 'UTC';
DELETE FROM lab03.measurements WHERE part = '12' AND variant = :'variant';

\echo '=== Таблица tasks (' :variant ')'
SELECT count(*) AS partitions FROM pg_inherits WHERE inhparent = 'tasks'::regclass;
SELECT pg_size_pretty(pg_total_relation_size('tasks')
       + COALESCE((SELECT sum(pg_total_relation_size(inhrelid)) FROM pg_inherits WHERE inhparent = 'tasks'::regclass), 0))
       AS total_size;
SELECT tableoid::regclass AS partition_name, count(*) AS rows
FROM tasks GROUP BY tableoid ORDER BY tableoid::regclass::text;

-- Пользователь с наибольшим числом задач и его последняя задача: одни и те же в обоих вариантах
SELECT user_id AS uid FROM tasks GROUP BY user_id ORDER BY count(*) DESC, user_id LIMIT 1 \gset
SELECT id AS task_id FROM tasks WHERE user_id = :'uid' ORDER BY created_at DESC, id LIMIT 1 \gset
\echo 'user_id =' :uid ', task_id =' :task_id

\pset format unaligned
\pset tuples_only on

\echo '=== Q1. GET /api/tasks?createdFrom=2026-08-01&createdTo=2026-08-31T23:59:59 (Admin): COUNT'
SELECT * FROM lab03.measure('12', 'Q1 месяц, все задачи: COUNT', :'variant', $q$
SELECT count(*)::int FROM tasks AS t
WHERE t.created_at >= '2026-08-01 00:00:00+00' AND t.created_at <= '2026-08-31 23:59:59+00'$q$, 'tasks');

\echo '=== Q2. Тот же запрос: первая страница'
SELECT * FROM lab03.measure('12', 'Q2 месяц, все задачи: страница', :'variant', $q$
SELECT t.id, t.title, t.status, t.priority, t.due_date, t.user_id, t.project_id, t.created_at
FROM tasks AS t
WHERE t.created_at >= '2026-08-01 00:00:00+00' AND t.created_at <= '2026-08-31 23:59:59+00'
ORDER BY t.created_at DESC
LIMIT 10$q$, 'tasks');

\echo '=== Q3. GET /api/tasks?status=Pending&createdFrom=2026-09-01&createdTo=2026-09-07T23:59:59 (Admin): COUNT'
SELECT * FROM lab03.measure('12', 'Q3 неделя + статус: COUNT', :'variant', $q$
SELECT count(*)::int FROM tasks AS t
WHERE t.status = 0
  AND t.created_at >= '2026-09-01 00:00:00+00' AND t.created_at <= '2026-09-07 23:59:59+00'$q$, 'tasks');

\echo '=== Q4. GET /api/tasks?createdFrom=2026-08-01&createdTo=2026-08-31T23:59:59 (пользователь): COUNT'
SELECT * FROM lab03.measure('12', 'Q4 месяц, задачи пользователя: COUNT', :'variant', format($q$
SELECT count(*)::int FROM tasks AS t
WHERE t.user_id = %L
  AND t.created_at >= '2026-08-01 00:00:00+00' AND t.created_at <= '2026-08-31 23:59:59+00'$q$, :'uid'), 'tasks');

\echo '=== Q5. Тот же запрос пользователя: первая страница'
SELECT * FROM lab03.measure('12', 'Q5 месяц, задачи пользователя: страница', :'variant', format($q$
SELECT t.id, t.title, t.status, t.priority, t.due_date, t.user_id, t.project_id, t.created_at
FROM tasks AS t
WHERE t.user_id = %L
  AND t.created_at >= '2026-08-01 00:00:00+00' AND t.created_at <= '2026-08-31 23:59:59+00'
ORDER BY t.created_at DESC
LIMIT 10$q$, :'uid'), 'tasks');

\echo '=== Q6. GET /api/tasks без фильтров (Admin): первая страница, ключ только в ORDER BY'
SELECT * FROM lab03.measure('12', 'Q6 без фильтров: страница', :'variant', $q$
SELECT t.id, t.title, t.status, t.priority, t.due_date, t.user_id, t.project_id, t.created_at
FROM tasks AS t
ORDER BY t.created_at DESC
LIMIT 10$q$, 'tasks');

\echo '=== Q7. GET /api/tasks/{id}: ключа партиционирования в запросе нет'
SELECT * FROM lab03.measure('12', 'Q7 задача по id', :'variant', format($q$
SELECT t.id, t.title, t.status, t.priority, t.due_date, t.user_id, t.project_id, t.created_at
FROM tasks AS t
WHERE t.id = %L
LIMIT 1$q$, :'task_id'), 'tasks');

\echo '=== Q8. GET /api/tasks/stats (Admin): группировка по всем задачам'
SELECT * FROM lab03.measure('12', 'Q8 статистика по статусам', :'variant', $q$
SELECT t.status, count(*)::int,
       count(*) FILTER (WHERE t.due_date < now() AND t.status IN (0, 1))::int
FROM tasks AS t
GROUP BY t.status
ORDER BY t.status$q$, 'tasks');

\pset format aligned
\pset tuples_only off

\echo '=== Итог (' :variant ')'
SELECT query, partitions_total AS total, partitions_in_plan AS in_plan, partitions_executed AS executed,
       scan, actual_rows, buffers, planning_ms, execution_ms
FROM lab03.measurements
WHERE part = '12' AND variant = :'variant'
ORDER BY id;
