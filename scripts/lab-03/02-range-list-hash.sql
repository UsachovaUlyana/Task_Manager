-- ЛР №3, части 3–6: RANGE по числу, LIST, DEFAULT-партиция, HASH.

\set ON_ERROR_STOP on
SET search_path = lab03, public;

\echo '=== Часть 3. RANGE по цене'
CREATE TABLE products (
    id BIGINT NOT NULL,
    name TEXT NOT NULL,
    price NUMERIC NOT NULL
) PARTITION BY RANGE (price);

CREATE TABLE products_cheap PARTITION OF products FOR VALUES FROM (0) TO (100);
CREATE TABLE products_medium PARTITION OF products FOR VALUES FROM (100) TO (1000);
CREATE TABLE products_expensive PARTITION OF products FOR VALUES FROM (1000) TO (MAXVALUE);

INSERT INTO products VALUES (1, 'Карандаш', 15), (2, 'Тетрадь', 99.99), (3, 'Рюкзак', 100),
                            (4, 'Наушники', 999.99), (5, 'Монитор', 1000), (6, 'Ноутбук', 85000);
SELECT tableoid::regclass AS partition_name, id, name, price FROM products ORDER BY id;

\echo '--- 300 000 товаров с ценой от 1 до 5 000'
INSERT INTO products SELECT g, 'Товар #' || g, round((1 + random() * 4999)::numeric, 2)
FROM generate_series(7, 300006) g;
ANALYZE products;
SELECT tableoid::regclass AS partition_name, COUNT(*), min(price), max(price)
FROM products GROUP BY tableoid ORDER BY partition_name;
SELECT lab03.try_sql($q$INSERT INTO lab03.products VALUES (0, 'Отрицательная цена', -5)$q$);

\pset tuples_only on
\pset format unaligned
SELECT * FROM lab03.measure('3', 'price от 100 до 500', 'RANGE по цене', $q$
SELECT * FROM lab03.products WHERE price >= 100 AND price < 500$q$, 'lab03.products');
SELECT * FROM lab03.measure('3', 'price от 50 до 150', 'RANGE по цене', $q$
SELECT * FROM lab03.products WHERE price >= 50 AND price < 150$q$, 'lab03.products');
\pset tuples_only off
\pset format aligned

\echo '=== Часть 4. LIST по типу клиента'
CREATE TABLE customers (
    id BIGINT NOT NULL,
    name TEXT NOT NULL,
    customer_type VARCHAR(30) NOT NULL
) PARTITION BY LIST (customer_type);

CREATE TABLE customers_b2c PARTITION OF customers FOR VALUES IN ('B2C');
CREATE TABLE customers_b2b PARTITION OF customers FOR VALUES IN ('B2B');
CREATE TABLE customers_enterprise PARTITION OF customers FOR VALUES IN ('Enterprise');

\echo '--- 300 000 клиентов: B2C 70 %, B2B 25 %, Enterprise 5 %'
INSERT INTO customers
SELECT g, 'Клиент #' || g,
       CASE WHEN r < 0.70 THEN 'B2C' WHEN r < 0.95 THEN 'B2B' ELSE 'Enterprise' END
FROM (SELECT g, random() AS r FROM generate_series(1, 300000) g) s;
ANALYZE customers;
SELECT tableoid::regclass AS partition_name, COUNT(*) FROM customers GROUP BY tableoid ORDER BY partition_name;

\pset tuples_only on
\pset format unaligned
SELECT * FROM lab03.measure('4', 'customer_type = B2B', 'LIST', $q$
SELECT * FROM lab03.customers WHERE customer_type = 'B2B'$q$, 'lab03.customers');
SELECT * FROM lab03.measure('4', 'customer_type IN (B2B, Enterprise)', 'LIST', $q$
SELECT * FROM lab03.customers WHERE customer_type IN ('B2B', 'Enterprise')$q$, 'lab03.customers');
\pset tuples_only off
\pset format aligned

\echo '=== Часть 5. Неизвестное значение и DEFAULT'
SELECT lab03.try_sql($q$INSERT INTO lab03.customers VALUES (100, 'Test User', 'VIP')$q$);
CREATE TABLE customers_default PARTITION OF customers DEFAULT;
SELECT lab03.try_sql($q$INSERT INTO lab03.customers VALUES (100, 'Test User', 'VIP')$q$);
SELECT tableoid::regclass AS partition_name, id, name, customer_type FROM customers WHERE id = 100;

\echo '--- проблема DEFAULT: отдельную партицию для VIP теперь нельзя создать, пока строки лежат в DEFAULT'
SELECT lab03.try_sql($q$CREATE TABLE lab03.customers_vip PARTITION OF lab03.customers FOR VALUES IN ('VIP')$q$);

\echo '--- как исправить: отсоединить DEFAULT, создать партицию, перенести строки, вернуть DEFAULT'
BEGIN;
ALTER TABLE customers DETACH PARTITION customers_default;
CREATE TABLE customers_vip PARTITION OF customers FOR VALUES IN ('VIP');
INSERT INTO customers SELECT * FROM customers_default WHERE customer_type = 'VIP';
DELETE FROM customers_default WHERE customer_type = 'VIP';
ALTER TABLE customers ATTACH PARTITION customers_default DEFAULT;
COMMIT;
SELECT tableoid::regclass AS partition_name, id, name, customer_type FROM customers WHERE id = 100;

\pset tuples_only on
\pset format unaligned
\echo '--- DEFAULT-партиция просматривается запросами по любым значениям, которых нет в списке'
SELECT * FROM lab03.measure('5', 'customer_type = Premium', 'LIST + DEFAULT', $q$
SELECT * FROM lab03.customers WHERE customer_type = 'Premium'$q$, 'lab03.customers');
\pset tuples_only off
\pset format aligned

\echo '=== Часть 6. HASH по user_id'
CREATE TABLE user_events (
    id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    event_type VARCHAR(50),
    created_at TIMESTAMP NOT NULL
) PARTITION BY HASH (user_id);

CREATE TABLE user_events_0 PARTITION OF user_events FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE user_events_1 PARTITION OF user_events FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE user_events_2 PARTITION OF user_events FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE user_events_3 PARTITION OF user_events FOR VALUES WITH (MODULUS 4, REMAINDER 3);

\echo '--- 1 000 000 событий 100 000 пользователей за 3 года'
\timing on
INSERT INTO user_events
SELECT g, (random() * 100000)::bigint,
       (ARRAY['view', 'login', 'purchase', 'click'])[1 + floor(random() * 4)::int],
       TIMESTAMP '2026-09-11' - random() * INTERVAL '3 years'
FROM generate_series(1, 1000000) g;
\timing off
ANALYZE user_events;

SELECT tableoid::regclass AS partition_name, COUNT(*),
       round(100.0 * COUNT(*) / sum(COUNT(*)) OVER (), 2) AS pct,
       COUNT(DISTINCT user_id) AS users
FROM user_events GROUP BY tableoid ORDER BY partition_name;

\pset tuples_only on
\pset format unaligned
SELECT * FROM lab03.measure('6', 'user_id = 42', 'HASH по user_id', $q$
SELECT * FROM lab03.user_events WHERE user_id = 42$q$, 'lab03.user_events');
SELECT * FROM lab03.measure('6', 'события старше 3 лет', 'HASH по user_id', $q$
SELECT COUNT(*) FROM lab03.user_events WHERE created_at < TIMESTAMP '2026-09-11' - INTERVAL '2 years 11 months'$q$,
    'lab03.user_events');
\pset tuples_only off
\pset format aligned

\echo '--- удаление старых данных в HASH — это DELETE по всем партициям, а не DROP одной партиции'
\timing on
BEGIN;
DELETE FROM user_events WHERE created_at < TIMESTAMP '2026-09-11' - INTERVAL '2 years 11 months';
ROLLBACK;
\timing off
