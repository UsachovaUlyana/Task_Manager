-- Массовая генерация тестовых данных TaskManager.
--
-- Запуск из корня репозитория после `docker compose up -d`:
--   docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -f /scripts/generate-data.sql
-- Объёмы задаются переменными psql (по умолчанию: 10 000 пользователей, 1 000 проектов,
-- 50 тегов, 1 000 000 задач), например:
--   docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -v tasks=5000000 -f /scripts/generate-data.sql
--
-- Создаются пользователи gen_user_1 .. gen_user_N и администратор gen_admin, пароль у всех: Password123!
-- Задачи распределены по пользователям неравномерно, как в реальном сервисе:
-- gen_user_1 получает ~1% всех задач, gen_user_2 ~0.4%, у типичного пользователя — около сотни.

\set ON_ERROR_STOP on

\if :{?users}
\else
    \set users 10000
\endif
\if :{?projects}
\else
    \set projects 1000
\endif
\if :{?tags}
\else
    \set tags 50
\endif
\if :{?tasks}
\else
    \set tasks 1000000
\endif

\timing on
SET synchronous_commit = off;

BEGIN;

\echo '>>> users'
INSERT INTO users (id, username, email, password_hash, role, created_at, updated_at)
SELECT gen_random_uuid(),
       'gen_user_' || g,
       'gen_user_' || g || '@example.com',
       encode(sha256('Password123!'::bytea), 'base64'),
       'User',
       now() - random() * interval '2 years',
       now()
FROM generate_series(1, :users) g
ON CONFLICT DO NOTHING;

INSERT INTO users (id, username, email, password_hash, role, created_at, updated_at)
VALUES (gen_random_uuid(), 'gen_admin', 'gen_admin@example.com',
        encode(sha256('Password123!'::bytea), 'base64'), 'Admin', now(), now())
ON CONFLICT DO NOTHING;

-- Нумерация 1..N нужна, чтобы выбирать случайного пользователя через JOIN по номеру
CREATE TEMP TABLE gen_users ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY substring(username FROM 10)::int) AS n, id
FROM users
WHERE username ~ '^gen_user_[0-9]+$';
SELECT count(*) AS gen_users_count FROM gen_users \gset

\echo '>>> projects'
CREATE TEMP TABLE gen_projects (n serial, id uuid) ON COMMIT DROP;
WITH inserted AS (
    INSERT INTO projects (id, name, description, created_at, updated_at)
    SELECT gen_random_uuid(),
           'Project ' || g,
           'Generated project #' || g,
           now() - random() * interval '2 years',
           now()
    FROM generate_series(1, :projects) g
    RETURNING id
)
INSERT INTO gen_projects (id) SELECT id FROM inserted;
SELECT count(*) AS gen_projects_count FROM gen_projects \gset

\echo '>>> tags'
INSERT INTO tags (id, name, color, created_at)
SELECT gen_random_uuid(),
       'gen-tag-' || g,
       '#' || lpad(to_hex((random() * 16777215)::int), 6, '0'),
       now()
FROM generate_series(1, :tags) g
ON CONFLICT DO NOTHING;

CREATE TEMP TABLE gen_tags ON COMMIT DROP AS
SELECT row_number() OVER () AS n, id FROM tags WHERE name LIKE 'gen-tag-%';
SELECT count(*) AS gen_tags_count FROM gen_tags \gset

\echo '>>> user_projects (M:M): каждый пользователь в 1-3 проектах'
INSERT INTO user_projects (user_id, project_id, role, joined_at)
SELECT s.user_id, p.id, s.role, now() - random() * interval '1 year'
FROM (
    SELECT gu.id AS user_id,
           1 + floor(random() * :gen_projects_count)::int AS pn,
           CASE WHEN k = 1 THEN 1 ELSE 0 END AS role  -- 1 = Owner, 0 = Member
    FROM gen_users gu, generate_series(1, 3) k
    WHERE k = 1 OR random() < 0.5
) s
JOIN gen_projects p ON p.n = s.pn
ON CONFLICT DO NOTHING;

\echo '>>> tasks'
-- status:   Pending 20%, InProgress 20%, Completed 55%, Cancelled 5%
-- priority: Low 30%, Medium 40%, High 22%, Critical 8%
-- power(random(), 2) смещает выбор к пользователям с малыми номерами
INSERT INTO tasks (id, title, description, status, priority, due_date,
                   user_id, project_id, created_at, updated_at)
SELECT gen_random_uuid(),
       'Task #' || s.g,
       CASE WHEN s.r_descr < 0.5 THEN 'Generated task description #' || s.g END,
       CASE WHEN s.r_status < 0.20 THEN 0
            WHEN s.r_status < 0.40 THEN 1
            WHEN s.r_status < 0.95 THEN 2
            ELSE 3 END,
       CASE WHEN s.r_prio < 0.30 THEN 0
            WHEN s.r_prio < 0.70 THEN 1
            WHEN s.r_prio < 0.92 THEN 2
            ELSE 3 END,
       CASE WHEN s.r_due < 0.7 THEN s.created_at + s.r_due * interval '90 days' END,
       u.id,
       p.id,
       s.created_at,
       LEAST(now(), s.created_at + random() * interval '30 days')
FROM (
    SELECT g,
           random() AS r_descr,
           random() AS r_status,
           random() AS r_prio,
           random() AS r_due,
           1 + floor(power(random(), 2) * :gen_users_count)::int AS un,
           CASE WHEN random() < 0.8 THEN 1 + floor(random() * :gen_projects_count)::int END AS pn,
           now() - random() * interval '2 years' AS created_at
    FROM generate_series(1, :tasks) g
) s
JOIN gen_users u ON u.n = s.un
LEFT JOIN gen_projects p ON p.n = s.pn;

\echo '>>> task_tags (M:M): у ~64% задач 1-2 тега'
INSERT INTO task_tags (task_id, tag_id)
SELECT s.task_id, t.id
FROM (
    SELECT tk.id AS task_id, 1 + floor(random() * :gen_tags_count)::int AS tn
    FROM tasks tk
    JOIN gen_users gu ON gu.id = tk.user_id,
    generate_series(1, 2) k
    WHERE random() < 0.4
) s
JOIN gen_tags t ON t.n = s.tn
ON CONFLICT DO NOTHING;

COMMIT;

ANALYZE users;
ANALYZE projects;
ANALYZE tags;
ANALYZE user_projects;
ANALYZE tasks;
ANALYZE task_tags;

\timing off
\echo '>>> итог'
SELECT 'users' AS table_name, count(*) AS rows FROM users
UNION ALL SELECT 'projects', count(*) FROM projects
UNION ALL SELECT 'tags', count(*) FROM tags
UNION ALL SELECT 'user_projects', count(*) FROM user_projects
UNION ALL SELECT 'tasks', count(*) FROM tasks
UNION ALL SELECT 'task_tags', count(*) FROM task_tags;

SELECT pg_size_pretty(pg_relation_size('tasks')) AS tasks_table,
       pg_size_pretty(pg_indexes_size('tasks')) AS tasks_indexes;
