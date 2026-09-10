-- Задания 3–5: EXPLAIN, EXPLAIN ANALYZE, Sequential Scan. Индексов, кроме PK, нет.

-- прогрев кэша, чтобы первое измерение не читало таблицу с диска
\o /dev/null
SELECT count(*) FROM orders;
\o

\echo '=== Задание 3. EXPLAIN (запрос не выполняется)'
\timing on
EXPLAIN
SELECT * FROM orders WHERE user_id = 123;

\echo '=== Задание 4. EXPLAIN ANALYZE (запрос выполняется)'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE user_id = 123;
\timing off

\echo '--- то же с BUFFERS: сколько страниц прочитано'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123;

\echo '=== Задание 5. Вся таблица'
EXPLAIN ANALYZE
SELECT * FROM orders;

\echo '--- накладные расходы замера времени: то же с TIMING OFF'
EXPLAIN (ANALYZE, TIMING OFF)
SELECT * FROM orders;

\echo '=== Задание 5. amount > 0 (условие истинно почти для всех строк)'
EXPLAIN ANALYZE
SELECT * FROM orders WHERE amount > 0;
