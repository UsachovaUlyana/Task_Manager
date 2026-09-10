-- Задание 9: индекс для диапазонного запроса по created_at.

\echo '=== Задание 9. ДО индекса: последние 7 дней'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '7 days';

CREATE INDEX idx_orders_created_at ON orders(created_at);
ANALYZE orders;

\echo '=== Задание 9. ПОСЛЕ индекса: 7 дней'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '7 days';
\echo '--- 1 день'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '1 day';
\echo '--- 1 месяц'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '1 month';
\echo '--- 1 год'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '1 year';

\echo '--- доля таблицы, попадающая в каждый диапазон'
SELECT
    count(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 day')   AS day_1,
    count(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days')  AS days_7,
    count(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 month') AS month_1,
    count(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 year')  AS year_1,
    count(*) AS total
FROM orders;
