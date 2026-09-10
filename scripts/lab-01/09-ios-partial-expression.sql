-- Задания 16–18: Index Only Scan, частичный индекс, индекс по выражению.

-- Visibility map после VACUUM FULL и вставок не заполнена — Index Only Scan без неё
-- всё равно ходил бы в таблицу. Обычный VACUUM её строит.
VACUUM ANALYZE orders;

\echo '=== Задание 16. ДО: SELECT id, user_id при индексе (user_id)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id FROM orders WHERE user_id = 123;
\echo '--- крупный пользователь'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id FROM orders WHERE user_id = 100001;

\echo '=== Задание 16. Индекс с INCLUDE'
CREATE INDEX idx_orders_user_id_include ON orders(user_id) INCLUDE (id, status, created_at);
VACUUM ANALYZE orders;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id FROM orders WHERE user_id = 123;
\echo '--- крупный пользователь'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id FROM orders WHERE user_id = 100001;
\echo '--- колонки из INCLUDE тоже читаются из индекса'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, status, created_at FROM orders WHERE user_id = 100001;
\echo '--- amount в индексе нет — Index Only Scan невозможен'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, amount FROM orders WHERE user_id = 100001;

\echo '--- меняем часть строк без VACUUM: страницы перестают быть all-visible'
UPDATE orders SET updated_at = NOW() WHERE user_id = 100001 AND status = 'CANCELLED';
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id FROM orders WHERE user_id = 100001;
VACUUM orders;
\echo '--- после VACUUM'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id FROM orders WHERE user_id = 100001;

\echo '=== Задание 17. ДО: WHERE status = NEW ORDER BY created_at (есть только idx_orders_status)'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE status = 'NEW' ORDER BY created_at;
\echo '--- типичный запрос очереди: первые 20 новых заказов'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE status = 'NEW' ORDER BY created_at LIMIT 20;

\echo '=== Задание 17. Вариант А: обычный составной индекс (status, created_at)'
CREATE INDEX idx_orders_status_created_at ON orders(status, created_at);
ANALYZE orders;
EXPLAIN ANALYZE
SELECT * FROM orders WHERE status = 'NEW' ORDER BY created_at;
EXPLAIN ANALYZE
SELECT * FROM orders WHERE status = 'NEW' ORDER BY created_at LIMIT 20;
SELECT pg_size_pretty(pg_relation_size('idx_orders_status_created_at')) AS regular_index_size;
DROP INDEX idx_orders_status_created_at;

\echo '=== Задание 17. Вариант Б: частичный индекс idx_orders_new'
CREATE INDEX idx_orders_new ON orders(created_at) WHERE status = 'NEW';
ANALYZE orders;
EXPLAIN ANALYZE
SELECT * FROM orders WHERE status = 'NEW' ORDER BY created_at;
EXPLAIN ANALYZE
SELECT * FROM orders WHERE status = 'NEW' ORDER BY created_at LIMIT 20;
SELECT pg_size_pretty(pg_relation_size('idx_orders_new')) AS partial_index_size;

\echo '--- частичный индекс не подходит для других статусов'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE status = 'PAID' ORDER BY created_at LIMIT 20;

\echo '=== Задание 18. Таблица users (500 000 email в разном регистре)'
DROP TABLE IF EXISTS users;
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL
);
INSERT INTO users (email)
SELECT CASE WHEN g % 2 = 0 THEN 'User' || g || '@Example.com'
            ELSE 'user' || g || '@example.com' END
FROM generate_series(1, 500000) g;
INSERT INTO users (email) VALUES ('Test@Example.com');

CREATE INDEX idx_users_email ON users(email);
ANALYZE users;

\echo '--- LOWER(email) = ... при индексе по email'
EXPLAIN ANALYZE
SELECT * FROM users WHERE LOWER(email) = 'test@example.com';
\echo '--- тот же индекс работает для точного сравнения email = ...'
EXPLAIN ANALYZE
SELECT * FROM users WHERE email = 'Test@Example.com';

CREATE INDEX idx_users_lower_email ON users(LOWER(email));
ANALYZE users;

\echo '--- ПОСЛЕ индекса по выражению LOWER(email)'
EXPLAIN ANALYZE
SELECT * FROM users WHERE LOWER(email) = 'test@example.com';
