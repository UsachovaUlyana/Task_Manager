-- Задания 10–11: Bitmap Scan и комбинирование нескольких индексов.

\echo '=== Задание 10. status = CANCELLED (~4% таблицы)'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'CANCELLED';

\echo '--- created_at за последний месяц (~4%)'
EXPLAIN ANALYZE SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '1 month';

\echo '--- amount BETWEEN 1000 AND 3000 (индекса по amount нет)'
EXPLAIN ANALYZE SELECT * FROM orders WHERE amount BETWEEN 1000 AND 3000;

\echo '--- для сравнения: запрещаем bitmap — планировщик выбирает между Index Scan и Seq Scan'
SET enable_bitmapscan = off;
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'CANCELLED';
\echo '--- запрещаем и Seq Scan: остаётся только обычный Index Scan'
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE status = 'CANCELLED';
\echo '--- тот же запрос через Bitmap (для сравнения BUFFERS)'
RESET enable_bitmapscan;
RESET enable_seqscan;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE status = 'CANCELLED';

\echo '=== Задание 11. Индексы на таблице orders'
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'orders' ORDER BY indexname;

\echo '=== Задание 11. user_id = 123 AND status = PAID'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 123 AND status = 'PAID';

\echo '--- запрос, где оба условия умеренно селективны: BitmapAnd'
EXPLAIN ANALYZE
SELECT * FROM orders
WHERE status = 'NEW' AND created_at > NOW() - INTERVAL '1 month';

\echo '--- OR по двум индексам: BitmapOr'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 123 OR user_id = 456;
