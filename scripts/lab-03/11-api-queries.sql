-- ЛР №3, часть 12, шаг 6: реальные запросы API к партиционированной tasks.
-- SQL взят из лога PostgreSQL (log_min_duration_statement = 0) при вызове endpoint'ов,
-- см. scripts/lab-03/capture-api-sql.sh; параметры $1, $2, ... подставлены из строк "parameters:" лога.

\set ON_ERROR_STOP on
SET TimeZone = 'UTC';
DELETE FROM lab03.measurements WHERE part = '12' AND variant = 'API (EF Core)';

\pset format unaligned
\pset tuples_only on

\echo '=== A1. GET /api/tasks?createdFrom=2026-08-01&createdTo=2026-08-31T23:59:59 (Admin)'
SELECT * FROM lab03.measure('12', 'A1 месяц, все задачи: COUNT', 'API (EF Core)', $q$
SELECT count(*)::int
FROM tasks AS t
WHERE t.created_at >= '2026-08-01 00:00:00+00' AND t.created_at <= '2026-08-31 23:59:59+00'$q$, 'tasks');

SELECT * FROM lab03.measure('12', 'A1 месяц, все задачи: страница', 'API (EF Core)', $q$
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id, t0.status, t0.title, t0.updated_at, t0.user_id, p.id, u.id, t1.task_id, t1.tag_id, t1.task_created_at, t1.id, t1.color, t1.created_at, t1.name, p.created_at, p.description, p.name, p.updated_at, u.created_at, u.email, u.password_hash, u.role, u.updated_at, u.username
FROM (
    SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id
    FROM tasks AS t
    WHERE t.created_at >= '2026-08-01 00:00:00+00' AND t.created_at <= '2026-08-31 23:59:59+00'
    ORDER BY t.created_at DESC
    LIMIT 10 OFFSET 0
) AS t0
LEFT JOIN projects AS p ON t0.project_id = p.id
INNER JOIN users AS u ON t0.user_id = u.id
LEFT JOIN (
    SELECT t2.task_id, t2.tag_id, t2.task_created_at, t3.id, t3.color, t3.created_at, t3.name
    FROM task_tags AS t2
    INNER JOIN tags AS t3 ON t2.tag_id = t3.id
) AS t1 ON t0.id = t1.task_id AND t0.created_at = t1.task_created_at
ORDER BY t0.created_at DESC, t0.id, p.id, u.id, t1.task_id, t1.tag_id$q$, 'tasks');

\echo '=== A2. GET /api/tasks?status=Pending&createdFrom=2026-09-01&createdTo=2026-09-07T23:59:59 (Admin)'
SELECT * FROM lab03.measure('12', 'A2 неделя + статус: COUNT', 'API (EF Core)', $q$
SELECT count(*)::int
FROM tasks AS t
WHERE t.status = 0 AND t.created_at >= '2026-09-01 00:00:00+00' AND t.created_at <= '2026-09-07 23:59:59+00'$q$, 'tasks');

\echo '=== A3. GET /api/tasks?createdFrom=2026-08-01&createdTo=2026-08-31T23:59:59 (пользователь)'
SELECT * FROM lab03.measure('12', 'A3 месяц, задачи пользователя: страница', 'API (EF Core)', $q$
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id, t0.status, t0.title, t0.updated_at, t0.user_id, p.id, t1.task_id, t1.tag_id, t1.task_created_at, t1.id, t1.color, t1.created_at, t1.name, p.created_at, p.description, p.name, p.updated_at
FROM (
    SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id
    FROM tasks AS t
    WHERE t.user_id = '335fc496-f143-433c-b8b5-48277f10419e'
      AND t.created_at >= '2026-08-01 00:00:00+00' AND t.created_at <= '2026-08-31 23:59:59+00'
    ORDER BY t.created_at DESC
    LIMIT 10 OFFSET 0
) AS t0
LEFT JOIN projects AS p ON t0.project_id = p.id
LEFT JOIN (
    SELECT t2.task_id, t2.tag_id, t2.task_created_at, t3.id, t3.color, t3.created_at, t3.name
    FROM task_tags AS t2
    INNER JOIN tags AS t3 ON t2.tag_id = t3.id
) AS t1 ON t0.id = t1.task_id AND t0.created_at = t1.task_created_at
ORDER BY t0.created_at DESC, t0.id, p.id, t1.task_id, t1.tag_id$q$, 'tasks');

\echo '=== A4. GET /api/tasks/{id}: ключа партиционирования в запросе нет'
SELECT * FROM lab03.measure('12', 'A4 задача по id', 'API (EF Core)', $q$
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id, t0.status, t0.title, t0.updated_at, t0.user_id, t0.id0, t0.id1, t1.task_id, t1.tag_id, t1.task_created_at, t1.id, t1.color, t1.created_at, t1.name, t0.created_at0, t0.description0, t0.name, t0.updated_at0, t0.created_at1, t0.email, t0.password_hash, t0.role, t0.updated_at1, t0.username
FROM (
    SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id, p.id AS id0, p.created_at AS created_at0, p.description AS description0, p.name, p.updated_at AS updated_at0, u.id AS id1, u.created_at AS created_at1, u.email, u.password_hash, u.role, u.updated_at AS updated_at1, u.username
    FROM tasks AS t
    LEFT JOIN projects AS p ON t.project_id = p.id
    INNER JOIN users AS u ON t.user_id = u.id
    WHERE t.id = '12da2e3e-ad6c-4c92-88b8-1f2dc6f40cdd'
    LIMIT 1
) AS t0
LEFT JOIN (
    SELECT t2.task_id, t2.tag_id, t2.task_created_at, t3.id, t3.color, t3.created_at, t3.name
    FROM task_tags AS t2
    INNER JOIN tags AS t3 ON t2.tag_id = t3.id
) AS t1 ON t0.id = t1.task_id AND t0.created_at = t1.task_created_at
ORDER BY t0.id, t0.id0, t0.id1, t1.task_id, t1.tag_id$q$, 'tasks');

\echo '=== A5. GET /api/tasks/stats (Admin): все задачи'
SELECT * FROM lab03.measure('12', 'A5 статистика по статусам', 'API (EF Core)', $q$
SELECT t.status AS "Status", count(*)::int AS "Count", count(*) FILTER (WHERE t.due_date < '2026-09-11 21:23:15.995856+00' AND t.status IN (0, 1))::int AS "OverdueCount"
FROM tasks AS t
GROUP BY t.status
ORDER BY t.status$q$, 'tasks');

\echo '=== A6. GET /api/tasks без фильтров (Admin): страница'
SELECT * FROM lab03.measure('12', 'A6 без фильтров: страница', 'API (EF Core)', $q$
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id, t0.status, t0.title, t0.updated_at, t0.user_id, p.id, u.id, t1.task_id, t1.tag_id, t1.task_created_at, t1.id, t1.color, t1.created_at, t1.name, p.created_at, p.description, p.name, p.updated_at, u.created_at, u.email, u.password_hash, u.role, u.updated_at, u.username
FROM (
    SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id
    FROM tasks AS t
    ORDER BY t.created_at DESC
    LIMIT 10 OFFSET 0
) AS t0
LEFT JOIN projects AS p ON t0.project_id = p.id
INNER JOIN users AS u ON t0.user_id = u.id
LEFT JOIN (
    SELECT t2.task_id, t2.tag_id, t2.task_created_at, t3.id, t3.color, t3.created_at, t3.name
    FROM task_tags AS t2
    INNER JOIN tags AS t3 ON t2.tag_id = t3.id
) AS t1 ON t0.id = t1.task_id AND t0.created_at = t1.task_created_at
ORDER BY t0.created_at DESC, t0.id, p.id, u.id, t1.task_id, t1.tag_id$q$, 'tasks');

\pset format aligned
\pset tuples_only off

\echo '=== Итог: запросы API'
SELECT query, partitions_total AS total, partitions_in_plan AS in_plan, partitions_executed AS executed,
       subplans_removed AS removed, scan, actual_rows, buffers, planning_ms, execution_ms
FROM lab03.measurements
WHERE part = '12' AND variant = 'API (EF Core)'
ORDER BY id;
