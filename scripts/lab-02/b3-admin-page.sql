-- ЛР №2, часть B: контрольный замер списка всех задач без фильтров (GET /api/tasks, Admin).
-- Миграция 011 заменяет idx_tasks_created_at на (created_at DESC, due_date) — проверяем,
-- что оптимизация из ЛР №1 для этого запроса сохранилась.
--
--   psql -v variant='...' -f /scripts/lab-02/b3-admin-page.sql

\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

\if :{?variant}
\else
    \set variant 'схема после ЛР №1'
\endif

SELECT count(*) AS volume FROM tasks \gset

SELECT * FROM lab02.measure('B', :volume, 'q6_admin_page', :'variant', $q$
SELECT t0.id, t0.created_at, t0.description, t0.due_date, t0.priority, t0.project_id, t0.status, t0.title, t0.updated_at, t0.user_id, p.id, u.id, t1.task_id, t1.tag_id, t1.id, t1.color, t1.created_at, t1.name, p.created_at, p.description, p.name, p.updated_at, u.created_at, u.email, u.password_hash, u.role, u.updated_at, u.username
FROM (
    SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id
    FROM tasks AS t
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
ORDER BY t0.created_at DESC, t0.id, p.id, u.id, t1.task_id, t1.tag_id$q$, 'tasks');
