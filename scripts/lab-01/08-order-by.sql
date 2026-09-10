-- Задания 14–15: WHERE + ORDER BY и пагинация.

-- Исходное состояние «как у типичного сервиса»: одиночные индексы, без составных.
DROP INDEX IF EXISTS idx_orders_user_created_at, idx_orders_created_at_user;
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
ANALYZE orders;

\echo '=== Задание 14. ДО: WHERE user_id = 123 ORDER BY created_at DESC'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 123 ORDER BY created_at DESC;
\echo '--- крупный пользователь'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 100001 ORDER BY created_at DESC;

CREATE INDEX idx_orders_user_created_at_desc ON orders(user_id, created_at DESC);
ANALYZE orders;

\echo '=== Задание 14. ПОСЛЕ: (user_id, created_at DESC)'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 123 ORDER BY created_at DESC;
\echo '--- крупный пользователь (все 50 000 строк, без LIMIT)'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 100001 ORDER BY created_at DESC;

\echo '--- крупный пользователь: план через индекс без Sort (bitmap запрещён) — сравниваем фактическое время'
SET enable_bitmapscan = off;
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 100001 ORDER BY created_at DESC;
RESET enable_bitmapscan;

\echo '--- random_page_cost = 1.1 (типичная настройка для SSD): планировщик сам выбирает индекс'
SET random_page_cost = 1.1;
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 100001 ORDER BY created_at DESC;
RESET random_page_cost;

\echo '--- обратный порядок колонок (created_at DESC, user_id): индекс не помогает, снова Sort'
DROP INDEX idx_orders_user_created_at_desc;
CREATE INDEX idx_orders_created_at_desc_user ON orders(created_at DESC, user_id);
ANALYZE orders;
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 123 ORDER BY created_at DESC;
DROP INDEX idx_orders_created_at_desc_user;

\echo '--- ASC-индекс (user_id, created_at) тоже подходит: B-tree читается в обратную сторону'
CREATE INDEX idx_orders_user_created_at_asc ON orders(user_id, created_at);
ANALYZE orders;
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 100001 ORDER BY created_at DESC LIMIT 20;
DROP INDEX idx_orders_user_created_at_asc;
ANALYZE orders;

\echo '=== Задание 15. ДО: GET /users/{id}/orders — LIMIT 20'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123 ORDER BY created_at DESC LIMIT 20;
\echo '--- крупный пользователь'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 100001 ORDER BY created_at DESC LIMIT 20;

CREATE INDEX idx_orders_user_created_at_desc ON orders(user_id, created_at DESC);
ANALYZE orders;

\echo '=== Задание 15. ПОСЛЕ: (user_id, created_at DESC)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123 ORDER BY created_at DESC LIMIT 20;
\echo '--- крупный пользователь'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 100001 ORDER BY created_at DESC LIMIT 20;

\echo '--- далёкая страница: OFFSET 20000 (индекс есть, но 20 000 строк всё равно читаются и выбрасываются)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 100001
ORDER BY created_at DESC LIMIT 20 OFFSET 20000;

\echo '--- та же страница через keyset-пагинацию (WHERE created_at < последнее значение предыдущей страницы)'
SELECT created_at AS cursor_ts
FROM orders WHERE user_id = 100001
ORDER BY created_at DESC OFFSET 19999 LIMIT 1 \gset
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 100001 AND created_at < :'cursor_ts'
ORDER BY created_at DESC LIMIT 20;
