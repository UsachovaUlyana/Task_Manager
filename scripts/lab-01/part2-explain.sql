-- ЛР №1, часть 2 (задания 24–26, 29): EXPLAIN и EXPLAIN ANALYZE реальных запросов сервиса.
-- Текст запросов взят из лога PostgreSQL (docs/lab-01/results/part2-01-captured-sql.txt):
-- ровно этот SQL генерирует EF Core для GET /api/tasks и GET /api/tasks/stats.
--
--   docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X < scripts/lab-01/part2-explain.sql

-- Npgsql выполняет запросы как неименованные prepared statements, и план строится
-- с реальными значениями параметров. force_custom_plan воспроизводит это поведение.
SET plan_cache_mode = force_custom_plan;

SELECT id AS power_user FROM users WHERE username = 'gen_user_1' \gset
SELECT id AS typical_user FROM users WHERE username = 'gen_user_5000' \gset

\echo '=== Индексы в БД сервиса'
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public' AND tablename <> 'databasechangelog' AND tablename <> 'databasechangeloglock'
ORDER BY tablename, indexname;

\echo '=== Селективность'
SELECT
    (SELECT count(*) FROM tasks) AS total_tasks,
    (SELECT count(*) FROM tasks WHERE user_id = :'power_user') AS power_user_tasks,
    (SELECT count(*) FROM tasks WHERE user_id = :'typical_user') AS typical_user_tasks,
    (SELECT count(*) FROM tasks WHERE user_id = :'power_user' AND status = 1 AND priority = 2) AS power_user_inprogress_high,
    (SELECT count(*) FROM tasks WHERE status = 0) AS pending_tasks;

-- Query 1. GET /api/tasks (обычный пользователь): общее число задач для пагинации
PREPARE q1(uuid) AS
SELECT count(*)::int
FROM tasks AS t
WHERE t.user_id = $1;

-- Query 2. GET /api/tasks?status=InProgress&priority=High: несколько условий
PREPARE q2(uuid, int, int) AS
SELECT count(*)::int
FROM tasks AS t
WHERE t.user_id = $1 AND t.status = $2 AND t.priority = $3;

-- Query 3. GET /api/tasks (обычный пользователь): страница задач — фильтр + сортировка + LIMIT
PREPARE q3(uuid, int, int) AS
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id, t0.status, t0.title, t0.updated_at, t0.user_id, p.id, t1.task_id, t1.tag_id, t1.id, t1.color, t1.created_at, t1.name, p.created_at, p.description, p.name, p.updated_at
FROM (
    SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id
    FROM tasks AS t
    WHERE t.user_id = $1
    ORDER BY t.created_at DESC
    LIMIT $2 OFFSET $3
) AS t0
LEFT JOIN projects AS p ON t0.project_id = p.id
LEFT JOIN (
    SELECT t2.task_id, t2.tag_id, t3.id, t3.color, t3.created_at, t3.name
    FROM task_tags AS t2
    INNER JOIN tags AS t3 ON t2.tag_id = t3.id
) AS t1 ON t0.id = t1.task_id
ORDER BY t0.created_at DESC, t0.id, p.id, t1.task_id, t1.tag_id;

-- Query 3b. GET /api/tasks (Admin / API Key): страница всех задач
PREPARE q3_admin(int, int) AS
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id, t0.status, t0.title, t0.updated_at, t0.user_id, p.id, u.id, t1.task_id, t1.tag_id, t1.id, t1.color, t1.created_at, t1.name, p.created_at, p.description, p.name, p.updated_at, u.created_at, u.email, u.password_hash, u.role, u.updated_at, u.username
FROM (
    SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id
    FROM tasks AS t
    ORDER BY t.created_at DESC
    LIMIT $1 OFFSET $2
) AS t0
LEFT JOIN projects AS p ON t0.project_id = p.id
INNER JOIN users AS u ON t0.user_id = u.id
LEFT JOIN (
    SELECT t2.task_id, t2.tag_id, t3.id, t3.color, t3.created_at, t3.name
    FROM task_tags AS t2
    INNER JOIN tags AS t3 ON t2.tag_id = t3.id
) AS t1 ON t0.id = t1.task_id
ORDER BY t0.created_at DESC, t0.id, p.id, u.id, t1.task_id, t1.tag_id;

-- Query 3c. GET /api/tasks?status=Pending (Admin): страница всех задач с фильтром по статусу
PREPARE q3_admin_status(int, int, int) AS
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id, t0.status, t0.title, t0.updated_at, t0.user_id, p.id, u.id, t1.task_id, t1.tag_id, t1.id, t1.color, t1.created_at, t1.name, p.created_at, p.description, p.name, p.updated_at, u.created_at, u.email, u.password_hash, u.role, u.updated_at, u.username
FROM (
    SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id
    FROM tasks AS t
    WHERE t.status = $1
    ORDER BY t.created_at DESC
    LIMIT $2 OFFSET $3
) AS t0
LEFT JOIN projects AS p ON t0.project_id = p.id
INNER JOIN users AS u ON t0.user_id = u.id
LEFT JOIN (
    SELECT t2.task_id, t2.tag_id, t3.id, t3.color, t3.created_at, t3.name
    FROM task_tags AS t2
    INNER JOIN tags AS t3 ON t2.tag_id = t3.id
) AS t1 ON t0.id = t1.task_id
ORDER BY t0.created_at DESC, t0.id, p.id, u.id, t1.task_id, t1.tag_id;

-- Query 4. GET /api/tasks/stats (Admin): агрегация по всей таблице
PREPARE q4_stats(timestamptz) AS
SELECT t.status AS "Status", count(*)::int AS "Count", count(*) FILTER (WHERE t.due_date < $1 AND t.status IN (0, 1))::int AS "OverdueCount"
FROM tasks AS t
GROUP BY t.status
ORDER BY t.status;

-- Query 5. GET /api/tasks (Admin): общее число задач для пагинации
PREPARE q5_count_all AS
SELECT count(*)::int
FROM tasks AS t;

\echo '=== Query 1. count(*) WHERE user_id — gen_user_1'
\o /dev/null
EXECUTE q1(:'power_user');
\o
EXPLAIN EXECUTE q1(:'power_user');
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q1(:'power_user');

\echo '=== Query 2. count(*) WHERE user_id AND status AND priority — gen_user_1, InProgress, High'
\o /dev/null
EXECUTE q2(:'power_user', 1, 2);
\o
EXPLAIN EXECUTE q2(:'power_user', 1, 2);
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q2(:'power_user', 1, 2);

\echo '=== Query 3. Страница задач пользователя — gen_user_1 (10 041 задача)'
\o /dev/null
EXECUTE q3(:'power_user', 10, 0);
\o
EXPLAIN EXECUTE q3(:'power_user', 10, 0);
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q3(:'power_user', 10, 0);

\echo '=== Query 3. Страница задач пользователя — gen_user_5000 (типичный, ~70 задач)'
\o /dev/null
EXECUTE q3(:'typical_user', 10, 0);
\o
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q3(:'typical_user', 10, 0);

\echo '=== Query 3. Далёкая страница gen_user_1: OFFSET 5000'
\o /dev/null
EXECUTE q3(:'power_user', 10, 5000);
\o
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q3(:'power_user', 10, 5000);

\echo '=== Query 3b. Страница всех задач (Admin)'
\o /dev/null
EXECUTE q3_admin(10, 0);
\o
EXPLAIN EXECUTE q3_admin(10, 0);
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q3_admin(10, 0);

\echo '=== Query 3c. Страница всех задач со status = Pending (Admin)'
\o /dev/null
EXECUTE q3_admin_status(0, 10, 0);
\o
EXPLAIN EXECUTE q3_admin_status(0, 10, 0);
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q3_admin_status(0, 10, 0);

\echo '=== Query 4. Статистика по статусам (Admin, GROUP BY)'
\o /dev/null
EXECUTE q4_stats(now());
\o
EXPLAIN EXECUTE q4_stats(now());
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q4_stats(now());

\echo '=== Query 5. count(*) всех задач (Admin)'
\o /dev/null
EXECUTE q5_count_all;
\o
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q5_count_all;
