-- Задание 6: первый B-tree индекс по user_id.

\echo '=== Задание 6. ДО индекса'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 123;

\echo '=== Задание 6. Создание idx_orders_user_id'
\timing on
CREATE INDEX idx_orders_user_id ON orders(user_id);
\timing off
ANALYZE orders;

\echo '=== Задание 6. ПОСЛЕ индекса'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 123;

\echo '--- с BUFFERS'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123;

SELECT pg_size_pretty(pg_relation_size('idx_orders_user_id')) AS idx_orders_user_id_size;
