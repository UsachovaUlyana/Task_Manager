-- Задания 7–8: индекс по status и селективность.

\echo '=== Задание 7. Создание idx_orders_status'
CREATE INDEX idx_orders_status ON orders(status);
ANALYZE orders;

\echo '--- status = PAID'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'PAID';
\echo '--- status = NEW'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'NEW';
\echo '--- status = DELIVERED'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'DELIVERED';
\echo '--- status = CANCELLED'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'CANCELLED';

\echo '--- для сравнения: status = PAID последовательным сканированием (индексы запрещены)'
SET enable_bitmapscan = off;
SET enable_indexscan = off;
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'PAID';
RESET enable_bitmapscan;
RESET enable_indexscan;

\echo '=== Задание 8. Распределение status (генератор из задания 2 — равномерный)'
SELECT status, count(*) AS cnt,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM orders GROUP BY status ORDER BY cnt;

\echo '--- что знает планировщик (pg_stats)'
SELECT most_common_vals, most_common_freqs
FROM pg_stats WHERE tablename = 'orders' AND attname = 'status';

\echo '=== Задание 8. Делаем распределение реалистичным: NEW 1%, CANCELLED 4%, PAID 20%, DELIVERED 75%'
UPDATE orders o
SET status = s.new_status
FROM (
    SELECT id,
           CASE WHEN r < 0.01 THEN 'NEW'
                WHEN r < 0.05 THEN 'CANCELLED'
                WHEN r < 0.25 THEN 'PAID'
                ELSE 'DELIVERED' END AS new_status
    FROM (SELECT id, random() AS r FROM orders) x
) s
WHERE o.id = s.id;

-- UPDATE оставил 1 млн мёртвых версий строк: пересобираем таблицу и индексы
VACUUM FULL orders;
ANALYZE orders;

SELECT status, count(*) AS cnt,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM orders GROUP BY status ORDER BY cnt;

\echo '--- NEW (~1%)'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'NEW';
\echo '--- CANCELLED (~4%)'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'CANCELLED';
\echo '--- PAID (~20%)'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'PAID';
\echo '--- DELIVERED (~75%)'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'DELIVERED';
