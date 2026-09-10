-- ЛР №2, часть B (задания 14–16, 18): реальные запросы сервиса на текущем объёме tasks.
-- Текст запросов — ровно тот SQL, который EF Core генерирует для GET /api/tasks и
-- GET /api/tasks/stats (снят из лога PostgreSQL), параметры подставлены литералами.
--
--   psql -v variant='схема после ЛР №1' -f /scripts/lab-02/b1-measure.sql

\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

\if :{?variant}
\else
    \set variant 'схема после ЛР №1'
\endif

SELECT count(*) AS volume FROM tasks \gset
SELECT id AS power_user FROM users WHERE username = 'gen_user_1' \gset
SELECT count(*) AS power_user_tasks FROM tasks WHERE user_id = :'power_user' \gset
-- неделя сроков полгода назад: окно фильтра dueDateFrom / dueDateTo
SELECT date_trunc('day', now()) - INTERVAL '180 days' AS due_from,
       date_trunc('day', now()) - INTERVAL '173 days' AS due_to \gset

\echo
\echo '==================== tasks:' :volume 'строк | gen_user_1:' :power_user_tasks 'задач |' :variant
INSERT INTO lab02.sizes (volume, object, bytes)
VALUES (:volume, 'tasks: таблица', pg_relation_size('tasks')),
       (:volume, 'tasks: индексы', pg_indexes_size('tasks')),
       (:volume, 'tasks: всего', pg_total_relation_size('tasks'))
ON CONFLICT (volume, object) DO UPDATE SET bytes = EXCLUDED.bytes;
SELECT format('tasks: таблица %s, индексы %s, всего %s',
              pg_size_pretty(pg_relation_size('tasks')), pg_size_pretty(pg_indexes_size('tasks')),
              pg_size_pretty(pg_total_relation_size('tasks')));

-- Запрос 1. Поиск по внешнему ключу: число задач пользователя для пагинации GET /api/tasks
SELECT * FROM lab02.measure('B', :volume, 'q1_count_user', :'variant', format($q$
SELECT count(*)::int
FROM tasks AS t
WHERE t.user_id = %L$q$, :'power_user'), 'tasks');

-- Запрос 2. Диапазон дат: GET /api/tasks?dueDateFrom=...&dueDateTo=... (Admin) — count и страница
SELECT * FROM lab02.measure('B', :volume, 'q2_due_count', :'variant', format($q$
SELECT count(*)::int
FROM tasks AS t
WHERE t.due_date >= %L AND t.due_date <= %L$q$, :'due_from', :'due_to'), 'tasks');

SELECT * FROM lab02.measure('B', :volume, 'q2_due_page', :'variant', format($q$
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

-- Запрос 3. Фильтрация + сортировка + LIMIT: страница задач активного пользователя
SELECT * FROM lab02.measure('B', :volume, 'q3_user_page', :'variant', format($q$
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id, t0.status, t0.title, t0.updated_at, t0.user_id, p.id, t1.task_id, t1.tag_id, t1.id, t1.color, t1.created_at, t1.name, p.created_at, p.description, p.name, p.updated_at
FROM (
    SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id
    FROM tasks AS t
    WHERE t.user_id = %L
    ORDER BY t.created_at DESC
    LIMIT 10 OFFSET 0
) AS t0
LEFT JOIN projects AS p ON t0.project_id = p.id
LEFT JOIN (
    SELECT t2.task_id, t2.tag_id, t3.id, t3.color, t3.created_at, t3.name
    FROM task_tags AS t2
    INNER JOIN tags AS t3 ON t2.tag_id = t3.id
) AS t1 ON t0.id = t1.task_id
ORDER BY t0.created_at DESC, t0.id, p.id, t1.task_id, t1.tag_id$q$, :'power_user'), 'tasks');

-- Запрос 4. Агрегация: GET /api/tasks/stats (Admin) — статистика по статусам всей таблицы
SELECT * FROM lab02.measure('B', :volume, 'q4_stats', :'variant', $q$
SELECT t.status AS "Status", count(*)::int AS "Count", count(*) FILTER (WHERE t.due_date < now() AND t.status IN (0, 1))::int AS "OverdueCount"
FROM tasks AS t
GROUP BY t.status
ORDER BY t.status$q$, 'tasks');

-- Запрос 5. Общее число задач для пагинации GET /api/tasks (Admin)
SELECT * FROM lab02.measure('B', :volume, 'q5_count_all', :'variant', $q$
SELECT count(*)::int
FROM tasks AS t$q$, 'tasks');
