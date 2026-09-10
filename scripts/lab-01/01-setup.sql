-- Лабораторная работа №1. Задания 1–2: тестовая таблица orders и 1 000 000 строк.
-- Выполняется в отдельной БД lab01 (см. scripts/lab-01/run-all.sh).

\echo '=== Задание 1. Создание таблицы orders'
DROP TABLE IF EXISTS orders;

CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    status VARCHAR(20) NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

\echo '=== Задание 2. Генерация 1 000 000 записей'
\timing on
INSERT INTO orders (user_id, product_id, status, amount, created_at, updated_at)
SELECT
    (random() * 100000)::BIGINT,
    (random() * 10000)::BIGINT,
    (ARRAY['NEW', 'PAID', 'DELIVERED', 'CANCELLED'])[floor(random() * 4 + 1)],
    random() * 10000,
    NOW() - (random() * INTERVAL '2 years'),
    NOW()
FROM generate_series(1, 1000000);
\timing off

ANALYZE orders;

SELECT count(*) AS rows,
       pg_size_pretty(pg_relation_size('orders')) AS table_size,
       pg_size_pretty(pg_indexes_size('orders')) AS indexes_size
FROM orders;

\echo '--- среда выполнения'
SELECT version();
SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('shared_buffers', 'work_mem', 'effective_cache_size', 'random_page_cost',
               'seq_page_cost', 'max_parallel_workers_per_gather')
ORDER BY name;
