-- ЛР №2, часть B, задание 18: варианты ускорения узких мест на максимальном объёме tasks.
-- Исходные замеры — b1-measure.sql (вариант «схема после ЛР №1»).

\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

SELECT count(*) AS volume FROM tasks \gset
SELECT date_trunc('day', now()) - INTERVAL '180 days' AS due_from,
       date_trunc('day', now()) - INTERVAL '173 days' AS due_to \gset
DELETE FROM lab02.measurements WHERE part = 'B' AND volume = :volume AND variant LIKE 'вариант%';

\echo '=== Запрос 2: страница с фильтром по сроку,' :volume 'задач'

\echo '--- вариант A: индекс (created_at DESC, due_date) — срок проверяется прямо в индексе'
CREATE INDEX idx_tasks_created_at_due_date ON tasks (created_at DESC, due_date);
ANALYZE tasks;
SELECT * FROM lab02.measure('B', :volume, 'q2_due_page', 'вариант A: индекс (created_at DESC, due_date)', format($q$
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id, t0.status, t0.title, t0.updated_at, t0.user_id, p.id, u.id, t1.task_id, t1.tag_id, t1.id, t1.color, t1.created_at, t1.name, p.created_at, p.description, p.name, p.updated_at, u.created_at, u.email, u.password_hash, u.role, u.updated_at, u.username
FROM (
    SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id
    FROM tasks AS t
    WHERE t.due_date >= %L AND t.due_date <= %L
    ORDER BY t.created_at DESC
    LIMIT 10 OFFSET 0
) AS t0
LEFT JOIN projects AS p ON t0.project_id = p.id
INNER JOIN users AS u ON t0.user_id = u.id
LEFT JOIN (
    SELECT t2.task_id, t2.tag_id, t3.id, t3.color, t3.created_at, t3.name
    FROM task_tags AS t2
    INNER JOIN tags AS t3 ON t2.tag_id = t3.id
) AS t1 ON t0.id = t1.task_id
ORDER BY t0.created_at DESC, t0.id, p.id, u.id, t1.task_id, t1.tag_id$q$, :'due_from', :'due_to'), 'tasks');
DROP INDEX idx_tasks_created_at_due_date;
ANALYZE tasks;

\echo '--- вариант B: сначала фильтр по сроку, потом сортировка (подзапрос с OFFSET 0 — барьер для планировщика)'
SELECT * FROM lab02.measure('B', :volume, 'q2_due_page', 'вариант B: фильтр до сортировки (OFFSET 0)', format($q$
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id, t0.status, t0.title, t0.updated_at, t0.user_id, p.id, u.id, t1.task_id, t1.tag_id, t1.id, t1.color, t1.created_at, t1.name, p.created_at, p.description, p.name, p.updated_at, u.created_at, u.email, u.password_hash, u.role, u.updated_at, u.username
FROM (
    SELECT f.id, f.created_at, f.description, f.due_date, f.priority, f.project_id, f.status, f.title, f.updated_at, f.user_id
    FROM (
        SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id
        FROM tasks AS t
        WHERE t.due_date >= %L AND t.due_date <= %L
        OFFSET 0
    ) AS f
    ORDER BY f.created_at DESC
    LIMIT 10 OFFSET 0
) AS t0
LEFT JOIN projects AS p ON t0.project_id = p.id
INNER JOIN users AS u ON t0.user_id = u.id
LEFT JOIN (
    SELECT t2.task_id, t2.tag_id, t3.id, t3.color, t3.created_at, t3.name
    FROM task_tags AS t2
    INNER JOIN tags AS t3 ON t2.tag_id = t3.id
) AS t1 ON t0.id = t1.task_id
ORDER BY t0.created_at DESC, t0.id, p.id, u.id, t1.task_id, t1.tag_id$q$, :'due_from', :'due_to'), 'tasks');

\echo '--- вариант C: сортировка по сроку (?sort=due_date) — порядок совпадает с idx_tasks_due_date'
SELECT * FROM lab02.measure('B', :volume, 'q2_due_page', 'вариант C: сортировка по сроку (sort=due_date)', format($q$
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id, t0.status, t0.title, t0.updated_at, t0.user_id, p.id, u.id, t1.task_id, t1.tag_id, t1.id, t1.color, t1.created_at, t1.name, p.created_at, p.description, p.name, p.updated_at, u.created_at, u.email, u.password_hash, u.role, u.updated_at, u.username
FROM (
    SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id
    FROM tasks AS t
    WHERE t.due_date >= %L AND t.due_date <= %L
    ORDER BY t.due_date, t.created_at DESC
    LIMIT 10 OFFSET 0
) AS t0
LEFT JOIN projects AS p ON t0.project_id = p.id
INNER JOIN users AS u ON t0.user_id = u.id
LEFT JOIN (
    SELECT t2.task_id, t2.tag_id, t3.id, t3.color, t3.created_at, t3.name
    FROM task_tags AS t2
    INNER JOIN tags AS t3 ON t2.tag_id = t3.id
) AS t1 ON t0.id = t1.task_id
ORDER BY t0.due_date, t0.created_at DESC, t0.id, p.id, u.id, t1.task_id, t1.tag_id$q$, :'due_from', :'due_to'), 'tasks');

\echo '=== Запрос 4: статистика — другой способ получения данных (материализованное представление)'
DROP MATERIALIZED VIEW IF EXISTS lab02.task_status_stats;
SELECT lab02.timed_write('построение task_status_stats', :volume, 0, $q$
CREATE MATERIALIZED VIEW lab02.task_status_stats AS
SELECT t.status AS "Status", count(*)::int AS "Count",
       count(*) FILTER (WHERE t.due_date < now() AND t.status IN (0, 1))::int AS "OverdueCount"
FROM tasks AS t
GROUP BY t.status$q$);
SELECT * FROM lab02.measure('B', :volume, 'q4_stats', 'вариант: материализованное представление',
    $q$SELECT "Status", "Count", "OverdueCount" FROM lab02.task_status_stats ORDER BY "Status"$q$,
    'task_status_stats');
SELECT lab02.timed_write('REFRESH task_status_stats', :volume, 0,
    $q$REFRESH MATERIALIZED VIEW lab02.task_status_stats$q$);
DROP MATERIALIZED VIEW lab02.task_status_stats;
