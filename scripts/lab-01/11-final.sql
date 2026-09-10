-- Задание 21: оптимизация итогового запроса.

-- Исходное состояние: «наивный» набор одиночных индексов, как часто бывает в проекте.
DROP INDEX IF EXISTS idx_orders_user_created_at_desc, idx_orders_user_id_include, idx_orders_new;
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
VACUUM ANALYZE orders;

\echo '=== Задание 21. Индексы до оптимизации'
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'orders' ORDER BY indexname;

PREPARE q21(BIGINT) AS
SELECT id, amount, status, created_at
FROM orders
WHERE user_id = $1
  AND status = 'PAID'
  AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC
LIMIT 50;

\echo '=== Задание 21. ДО: user_id = 123'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q21(123);
\echo '=== Задание 21. ДО: крупный пользователь 100001'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q21(100001);

\echo '=== Промежуточный вариант: (user_id, created_at DESC) — статус проверяется фильтром'
CREATE INDEX idx_orders_user_created_at_desc ON orders(user_id, created_at DESC);
ANALYZE orders;
DEALLOCATE q21;
PREPARE q21(BIGINT) AS
SELECT id, amount, status, created_at
FROM orders
WHERE user_id = $1
  AND status = 'PAID'
  AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC
LIMIT 50;
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q21(100001);
DROP INDEX idx_orders_user_created_at_desc;

\echo '=== Итоговый индекс: равенства -> диапазон/сортировка, остальное в INCLUDE'
CREATE INDEX idx_orders_user_status_created_at
    ON orders(user_id, status, created_at DESC)
    INCLUDE (amount);
VACUUM ANALYZE orders;
DEALLOCATE q21;
PREPARE q21(BIGINT) AS
SELECT id, amount, status, created_at
FROM orders
WHERE user_id = $1
  AND status = 'PAID'
  AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC
LIMIT 50;

\echo '=== Задание 21. ПОСЛЕ: user_id = 123'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q21(123);
\echo '=== Задание 21. ПОСЛЕ: крупный пользователь 100001'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q21(100001);

\echo '--- id тоже в INCLUDE: полностью Index Only Scan'
DROP INDEX idx_orders_user_status_created_at;
CREATE INDEX idx_orders_user_status_created_at
    ON orders(user_id, status, created_at DESC)
    INCLUDE (id, amount);
VACUUM ANALYZE orders;
DEALLOCATE q21;
PREPARE q21(BIGINT) AS
SELECT id, amount, status, created_at
FROM orders
WHERE user_id = $1
  AND status = 'PAID'
  AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC
LIMIT 50;
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q21(100001);

SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes WHERE relname = 'orders' ORDER BY indexrelname;
