-- ЛР №2, часть A: схема lab02 в базе сервиса, экспериментальная таблица events
-- и функции, которые выполняют EXPLAIN ANALYZE и сохраняют результаты в таблицы.

\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS lab02 CASCADE;
CREATE SCHEMA lab02;

-- Задание 1
CREATE TABLE lab02.events (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    payload JSONB,
    created_at TIMESTAMP NOT NULL
);

-- Одна строка на каждый прогон EXPLAIN ANALYZE (часть A и часть B)
CREATE TABLE lab02.measurements (
    id SERIAL PRIMARY KEY,
    part TEXT NOT NULL,
    volume BIGINT NOT NULL,
    query TEXT NOT NULL,
    variant TEXT NOT NULL,
    scan TEXT,              -- узел плана, который читает исследуемую таблицу
    indexes TEXT,           -- индексы, встретившиеся в плане
    actual_rows BIGINT,     -- строк вернул этот узел (rows × loops)
    rows_removed BIGINT,    -- Rows Removed by Filter (× loops)
    has_sort BOOLEAN,       -- есть ли в плане Sort / Incremental Sort
    operations TEXT,        -- все узлы плана сверху вниз
    buffers BIGINT,         -- shared hit + read корневого узла
    execution_ms NUMERIC,
    measured_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE lab02.sizes (
    volume BIGINT NOT NULL,
    object TEXT NOT NULL,
    bytes BIGINT NOT NULL,
    build_ms NUMERIC,
    PRIMARY KEY (volume, object)
);

CREATE TABLE lab02.writes (
    id SERIAL PRIMARY KEY,
    experiment TEXT NOT NULL,
    rows BIGINT NOT NULL,
    indexes INT NOT NULL,
    duration_ms NUMERIC NOT NULL
);

-- Задание 2: генератор из методички, вставляет n строк в указанную таблицу, возвращает время в мс
CREATE FUNCTION lab02.generate_events(p_target REGCLASS, p_rows BIGINT) RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE
    t0 TIMESTAMPTZ := clock_timestamp();
BEGIN
    EXECUTE format($sql$
        INSERT INTO %s (user_id, event_type, payload, created_at)
        SELECT
            (random() * 100000)::bigint,
            CASE
                WHEN random() < 0.4 THEN 'MESSAGE'
                WHEN random() < 0.7 THEN 'LOGIN'
                WHEN random() < 0.9 THEN 'PURCHASE'
                ELSE 'OTHER'
            END,
            '{}'::jsonb,
            NOW() - (random() * INTERVAL '365 days')
        FROM generate_series(1, %s)
    $sql$, p_target, p_rows);
    RETURN round(extract(epoch FROM clock_timestamp() - t0) * 1000, 1);
END $$;

-- Дописывает в events строки до нужного объёма
CREATE FUNCTION lab02.grow(p_target BIGINT) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    current_rows BIGINT;
    ms NUMERIC;
BEGIN
    SELECT count(*) INTO current_rows FROM lab02.events;
    IF p_target <= current_rows THEN
        RETURN format('в таблице уже %s строк', current_rows);
    END IF;
    ms := lab02.generate_events('lab02.events', p_target - current_rows);
    INSERT INTO lab02.writes (experiment, rows, indexes, duration_ms)
    VALUES (format('рост %s → %s', current_rows, p_target), p_target - current_rows, 0, ms);
    RETURN format('вставлено %s строк за %s мс', p_target - current_rows, ms);
END $$;

-- Задание 3: размер таблицы и общий размер вместе с индексами
CREATE FUNCTION lab02.record_sizes(p_volume BIGINT, p_label TEXT) RETURNS SETOF TEXT
LANGUAGE sql AS $$
    INSERT INTO lab02.sizes (volume, object, bytes)
    VALUES (p_volume, 'таблица', pg_relation_size('lab02.events')),
           (p_volume, 'всего: ' || p_label, pg_total_relation_size('lab02.events'))
    ON CONFLICT (volume, object) DO UPDATE SET bytes = EXCLUDED.bytes
    RETURNING format('%s: %s', object, pg_size_pretty(bytes));
$$;

-- Задание 10: создаёт индекс и запоминает его размер и время построения
CREATE FUNCTION lab02.create_index(p_volume BIGINT, p_name TEXT, p_ddl TEXT) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    t0 TIMESTAMPTZ := clock_timestamp();
    ms NUMERIC;
    size BIGINT;
BEGIN
    EXECUTE p_ddl;
    ms := round(extract(epoch FROM clock_timestamp() - t0) * 1000, 1);
    size := pg_relation_size(('lab02.' || p_name)::regclass);
    INSERT INTO lab02.sizes (volume, object, bytes, build_ms)
    VALUES (p_volume, p_name, size, ms)
    ON CONFLICT (volume, object) DO UPDATE SET bytes = EXCLUDED.bytes, build_ms = EXCLUDED.build_ms;
    RETURN format('%s: %s, построен за %s мс', p_name, pg_size_pretty(size), ms);
END $$;

-- Задание 9: выполняет операцию записи и запоминает её время
CREATE FUNCTION lab02.timed_write(p_experiment TEXT, p_rows BIGINT, p_indexes INT, p_sql TEXT) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    t0 TIMESTAMPTZ := clock_timestamp();
    ms NUMERIC;
BEGIN
    EXECUTE p_sql;
    ms := round(extract(epoch FROM clock_timestamp() - t0) * 1000, 1);
    INSERT INTO lab02.writes (experiment, rows, indexes, duration_ms) VALUES (p_experiment, p_rows, p_indexes, ms);
    RETURN format('%s, доп. индексов %s: %s мс', p_experiment, p_indexes, ms);
END $$;

-- Разбор JSON-плана: узел, читающий таблицу p_rel, индексы, Sort, список операций
CREATE FUNCTION lab02.plan_summary(p_plan JSONB, p_rel TEXT)
RETURNS TABLE (scan TEXT, indexes TEXT, actual_rows BIGINT, rows_removed BIGINT, has_sort BOOLEAN, operations TEXT)
LANGUAGE sql AS $$
    WITH RECURSIVE nodes (node, path) AS (
        SELECT p_plan -> 0 -> 'Plan', ARRAY[0]
        UNION ALL
        SELECT child.value, n.path || child.ordinality::int
        FROM nodes n, jsonb_array_elements(n.node -> 'Plans') WITH ORDINALITY AS child (value, ordinality)
    ),
    scan_node AS (
        SELECT node FROM nodes WHERE node ->> 'Relation Name' = p_rel ORDER BY path LIMIT 1
    )
    SELECT
        (SELECT node ->> 'Node Type' FROM scan_node),
        (SELECT string_agg(DISTINCT node ->> 'Index Name', ', ') FROM nodes WHERE node ? 'Index Name'),
        (SELECT ((node ->> 'Actual Rows')::numeric * (node ->> 'Actual Loops')::numeric)::bigint FROM scan_node),
        (SELECT (coalesce((node ->> 'Rows Removed by Filter')::numeric, 0)
                 * (node ->> 'Actual Loops')::numeric)::bigint FROM scan_node),
        EXISTS (SELECT 1 FROM nodes WHERE node ->> 'Node Type' IN ('Sort', 'Incremental Sort')),
        (SELECT string_agg(node ->> 'Node Type', ' → ' ORDER BY path) FROM nodes)
$$;

-- Один замер: прогрев, JSON-план для разбора, текстовый план в лог.
-- В таблицу попадают Execution Time и Buffers именно того прогона, который напечатан.
CREATE FUNCTION lab02.measure(p_part TEXT, p_volume BIGINT, p_query TEXT, p_variant TEXT, p_sql TEXT,
                              p_rel TEXT DEFAULT 'events')
RETURNS SETOF TEXT
LANGUAGE plpgsql AS $$
DECLARE
    plan JSON;
    line TEXT;
    exec_ms NUMERIC;
    buffers BIGINT;
BEGIN
    EXECUTE 'EXPLAIN (ANALYZE, TIMING OFF) ' || p_sql;
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || p_sql INTO plan;

    RETURN NEXT format('--- %s | %s строк | %s', p_query, p_volume, p_variant);
    RETURN NEXT p_sql;
    FOR line IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS) ' || p_sql LOOP
        RETURN NEXT line;
        IF exec_ms IS NULL AND line ~ '^Execution Time:' THEN
            exec_ms := substring(line FROM 'Execution Time: ([0-9.]+)')::numeric;
        END IF;
        IF buffers IS NULL AND line ~ 'Buffers: shared' THEN
            buffers := coalesce(substring(line FROM 'hit=([0-9]+)')::bigint, 0)
                     + coalesce(substring(line FROM 'read=([0-9]+)')::bigint, 0);
        END IF;
    END LOOP;

    INSERT INTO lab02.measurements (part, volume, query, variant, scan, indexes, actual_rows, rows_removed,
                                    has_sort, operations, buffers, execution_ms)
    SELECT p_part, p_volume, p_query, p_variant, s.scan, s.indexes, s.actual_rows, s.rows_removed,
           s.has_sort, s.operations, buffers, exec_ms
    FROM lab02.plan_summary(plan::jsonb, p_rel) s;
    RETURN NEXT '';
END $$;

SELECT 'схема lab02 готова' AS status;
