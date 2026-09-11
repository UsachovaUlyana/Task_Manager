-- ЛР №3, дополнительно к контрольному вопросу 18: цена большого числа партиций.
-- Одна и та же таблица из 1 млн строк разбита на 10, 100 и 1 000 партиций.
-- Сравниваем время планирования и выполнения запроса с ключом (pruning) и без ключа.

\set ON_ERROR_STOP on
SET search_path = lab03, public;
\pset tuples_only on
\pset format unaligned

CREATE FUNCTION lab03.make_counted(p_parts INT) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    name TEXT := 'counted_' || p_parts;
    step INT := 1000000 / p_parts;
BEGIN
    EXECUTE format('DROP TABLE IF EXISTS lab03.%I', name);
    EXECUTE format('CREATE TABLE lab03.%I (id BIGINT NOT NULL, payload TEXT) PARTITION BY RANGE (id)', name);
    FOR i IN 0 .. p_parts - 1 LOOP
        EXECUTE format('CREATE TABLE lab03.%I PARTITION OF lab03.%I FOR VALUES FROM (%s) TO (%s)',
                       name || '_' || i, name, i * step, (i + 1) * step);
    END LOOP;
    EXECUTE format('INSERT INTO lab03.%I SELECT g, md5(g::text) FROM generate_series(0, 999999) g', name);
    EXECUTE format('ANALYZE lab03.%I', name);
    RETURN format('%s: %s партиций', name, p_parts);
END $$;

\echo '=== Цена количества партиций'
SELECT lab03.make_counted(10);
SELECT lab03.make_counted(100);
SELECT lab03.make_counted(1000);

SELECT * FROM lab03.measure('18', 'id = 500000 (есть ключ)', '10 партиций',
    $q$SELECT * FROM lab03.counted_10 WHERE id = 500000$q$, 'lab03.counted_10');
SELECT * FROM lab03.measure('18', 'id = 500000 (есть ключ)', '100 партиций',
    $q$SELECT * FROM lab03.counted_100 WHERE id = 500000$q$, 'lab03.counted_100');
SELECT * FROM lab03.measure('18', 'id = 500000 (есть ключ)', '1000 партиций',
    $q$SELECT * FROM lab03.counted_1000 WHERE id = 500000$q$, 'lab03.counted_1000');

SELECT * FROM lab03.measure('18', 'payload = ... (ключа нет)', '10 партиций',
    $q$SELECT * FROM lab03.counted_10 WHERE payload = md5('500000')$q$, 'lab03.counted_10');
SELECT * FROM lab03.measure('18', 'payload = ... (ключа нет)', '100 партиций',
    $q$SELECT * FROM lab03.counted_100 WHERE payload = md5('500000')$q$, 'lab03.counted_100');
SELECT * FROM lab03.measure('18', 'payload = ... (ключа нет)', '1000 партиций',
    $q$SELECT * FROM lab03.counted_1000 WHERE payload = md5('500000')$q$, 'lab03.counted_1000');

DROP TABLE lab03.counted_10, lab03.counted_100, lab03.counted_1000;
DROP FUNCTION lab03.make_counted(INT);
