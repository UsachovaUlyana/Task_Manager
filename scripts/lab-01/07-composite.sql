-- Задания 12–13: составной индекс и порядок колонок.
--
-- У пользователя 123 всего ~10 заказов, разница между планами тонет в шуме
-- (доли миллисекунды). Поэтому добавляем «крупного» пользователя 100001 с 50 000
-- заказов — так ведёт себя активный клиент в реальном сервисе.

\echo '=== Подготовка: крупный пользователь 100001 (50 000 заказов)'
INSERT INTO orders (user_id, product_id, status, amount, created_at, updated_at)
SELECT 100001,
       (random() * 10000)::BIGINT,
       CASE WHEN r < 0.01 THEN 'NEW'
            WHEN r < 0.05 THEN 'CANCELLED'
            WHEN r < 0.25 THEN 'PAID'
            ELSE 'DELIVERED' END,
       random() * 10000,
       NOW() - (random() * INTERVAL '2 years'),
       NOW()
FROM (SELECT random() AS r FROM generate_series(1, 50000)) s;
ANALYZE orders;

\echo '=== Задание 12. ДО: два отдельных индекса (user_id) и (status)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123 AND status = 'PAID';
\echo '--- крупный пользователь'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 100001 AND status = 'PAID';

CREATE INDEX idx_orders_user_status ON orders(user_id, status);
ANALYZE orders;

\echo '=== Задание 12. ПОСЛЕ: составной индекс (user_id, status)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123 AND status = 'PAID';
\echo '--- крупный пользователь'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 100001 AND status = 'PAID';

\echo '--- размеры индексов'
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes WHERE relname = 'orders' ORDER BY indexrelname;

-- Задание 13. Чистый эксперимент: убираем индексы, которые могут «подменить»
-- исследуемый составной индекс, иначе эффект порядка колонок не виден.
DROP INDEX idx_orders_user_id, idx_orders_created_at, idx_orders_user_status;

\echo '=== Задание 13. Только (user_id, created_at)'
CREATE INDEX idx_orders_user_created_at ON orders(user_id, created_at);
ANALYZE orders;

\echo '--- Запрос 1: user_id = 123'
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 123;
\echo '--- Запрос 2: user_id = 123 AND created_at > NOW() - 30 days'
EXPLAIN ANALYZE SELECT * FROM orders
WHERE user_id = 123 AND created_at > NOW() - INTERVAL '30 days';
\echo '--- Запрос 2 для крупного пользователя'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders
WHERE user_id = 100001 AND created_at > NOW() - INTERVAL '30 days';
\echo '--- Запрос 3: created_at > NOW() - 30 days'
EXPLAIN ANALYZE SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '30 days';

DROP INDEX idx_orders_user_created_at;

\echo '=== Задание 13. Только (created_at, user_id)'
CREATE INDEX idx_orders_created_at_user ON orders(created_at, user_id);
ANALYZE orders;

\echo '--- Запрос 1: user_id = 123'
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 123;
\echo '--- Запрос 2: user_id = 123 AND created_at > NOW() - 30 days'
EXPLAIN ANALYZE SELECT * FROM orders
WHERE user_id = 123 AND created_at > NOW() - INTERVAL '30 days';
\echo '--- Запрос 2 для крупного пользователя'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders
WHERE user_id = 100001 AND created_at > NOW() - INTERVAL '30 days';
\echo '--- Запрос 3: created_at > NOW() - 30 days'
EXPLAIN ANALYZE SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '30 days';

\echo '=== Задание 13. Оба индекса одновременно — что выберет планировщик'
CREATE INDEX idx_orders_user_created_at ON orders(user_id, created_at);
ANALYZE orders;

\echo '--- Запрос 1'
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 123;
\echo '--- Запрос 2'
EXPLAIN ANALYZE SELECT * FROM orders
WHERE user_id = 123 AND created_at > NOW() - INTERVAL '30 days';
\echo '--- Запрос 3'
EXPLAIN ANALYZE SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '30 days';
