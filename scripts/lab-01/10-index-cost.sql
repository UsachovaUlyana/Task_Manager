-- Задания 19–20: цена индексов на запись и статистика использования.

\echo '=== Задание 19. Таблица orders_insert_test только с PRIMARY KEY'
DROP TABLE IF EXISTS orders_insert_test;
CREATE TABLE orders_insert_test (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    status VARCHAR(20) NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

-- одинаковое зерно — одинаковые данные в обоих прогонах
SELECT setseed(0.42);
\echo '--- INSERT 1 000 000 строк: только PK'
\timing on
INSERT INTO orders_insert_test (user_id, product_id, status, amount, created_at, updated_at)
SELECT (random() * 100000)::BIGINT, (random() * 10000)::BIGINT,
       (ARRAY['NEW', 'PAID', 'DELIVERED', 'CANCELLED'])[floor(random() * 4 + 1)],
       random() * 10000, NOW() - (random() * INTERVAL '2 years'), NOW()
FROM generate_series(1, 1000000);
\echo '--- UPDATE 100 000 строк (меняем индексируемую колонку status): только PK'
UPDATE orders_insert_test SET status = 'PAID' WHERE id <= 100000;
\echo '--- DELETE 100 000 строк: только PK'
DELETE FROM orders_insert_test WHERE id > 900000;
\timing off
SELECT pg_size_pretty(pg_relation_size('orders_insert_test')) AS table_size,
       pg_size_pretty(pg_indexes_size('orders_insert_test')) AS indexes_size;

TRUNCATE orders_insert_test RESTART IDENTITY;
CREATE INDEX ON orders_insert_test(user_id);
CREATE INDEX ON orders_insert_test(status);
CREATE INDEX ON orders_insert_test(created_at);
CREATE INDEX ON orders_insert_test(user_id, created_at DESC);
CREATE INDEX ON orders_insert_test(status, created_at);

SELECT setseed(0.42);
\echo '--- INSERT 1 000 000 строк: PK + 5 индексов'
\timing on
INSERT INTO orders_insert_test (user_id, product_id, status, amount, created_at, updated_at)
SELECT (random() * 100000)::BIGINT, (random() * 10000)::BIGINT,
       (ARRAY['NEW', 'PAID', 'DELIVERED', 'CANCELLED'])[floor(random() * 4 + 1)],
       random() * 10000, NOW() - (random() * INTERVAL '2 years'), NOW()
FROM generate_series(1, 1000000);
\echo '--- UPDATE 100 000 строк: PK + 5 индексов'
UPDATE orders_insert_test SET status = 'PAID' WHERE id <= 100000;
\echo '--- DELETE 100 000 строк: PK + 5 индексов'
DELETE FROM orders_insert_test WHERE id > 900000;
\timing off
SELECT pg_size_pretty(pg_relation_size('orders_insert_test')) AS table_size,
       pg_size_pretty(pg_indexes_size('orders_insert_test')) AS indexes_size;

DROP TABLE orders_insert_test;

\echo '=== Задание 20. Статистика использования индексов (pg_stat_user_indexes)'
SELECT schemaname, relname, indexrelname, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
ORDER BY idx_scan;
