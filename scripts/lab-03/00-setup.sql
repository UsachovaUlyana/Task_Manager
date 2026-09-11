-- ЛР №3: схема lab03 и функции измерений с учётом партиций.
-- lab03.measure выполняет EXPLAIN (ANALYZE, BUFFERS), печатает план и сохраняет в lab03.measurements:
-- сколько партиций попало в план, сколько реально читалось, сколько отсечено при выполнении.

\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS lab03 CASCADE;
CREATE SCHEMA lab03;

CREATE TABLE lab03.measurements (
    id SERIAL PRIMARY KEY,
    part TEXT NOT NULL,
    query TEXT NOT NULL,
    variant TEXT NOT NULL,
    partitions_total INT,       -- партиций у таблицы
    partitions_in_plan INT,     -- узлов сканирования партиций в плане (остальные отсечены планировщиком)
    partitions_executed INT,    -- из них реально выполнялись (loops > 0)
    subplans_removed INT,       -- отсечено при выполнении (runtime pruning)
    scan TEXT,
    indexes TEXT,
    actual_rows BIGINT,
    rows_removed BIGINT,
    has_sort BOOLEAN,
    operations TEXT,
    buffers BIGINT,
    planning_ms NUMERIC,
    execution_ms NUMERIC,
    measured_at TIMESTAMPTZ DEFAULT now()
);

CREATE FUNCTION lab03.plan_summary(p_plan JSONB, p_parent REGCLASS)
RETURNS TABLE (partitions_total INT, partitions_in_plan INT, partitions_executed INT, subplans_removed INT,
               scan TEXT, indexes TEXT, actual_rows BIGINT, rows_removed BIGINT, has_sort BOOLEAN, operations TEXT)
LANGUAGE sql AS $$
    WITH RECURSIVE nodes (node, path) AS (
        SELECT p_plan -> 0 -> 'Plan', ARRAY[0]
        UNION ALL
        SELECT child.value, n.path || child.ordinality::int
        FROM nodes n, jsonb_array_elements(n.node -> 'Plans') WITH ORDINALITY AS child (value, ordinality)
    ),
    relations AS (
        SELECT c.relname FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid WHERE i.inhparent = p_parent
        UNION ALL
        SELECT relname FROM pg_class WHERE oid = p_parent
    ),
    scans AS (
        SELECT node FROM nodes WHERE node ->> 'Relation Name' IN (SELECT relname FROM relations)
    )
    SELECT
        (SELECT count(*)::int FROM pg_inherits WHERE inhparent = p_parent),
        (SELECT count(*)::int FROM scans),
        (SELECT count(*)::int FROM scans WHERE (node ->> 'Actual Loops')::numeric > 0),
        (SELECT coalesce(sum((node ->> 'Subplans Removed')::int), 0)::int FROM nodes WHERE node ? 'Subplans Removed'),
        (SELECT string_agg(DISTINCT node ->> 'Node Type', ', ') FROM scans),
        -- индексы партиций называются по партиции: tasks_2026_09_user_id_idx → tasks_*_user_id_idx
        (SELECT string_agg(DISTINCT regexp_replace(node ->> 'Index Name', '_\d{4}_\d{2}(_\d{2})?', '_*'), ', ')
         FROM nodes WHERE node ? 'Index Name'),
        (SELECT coalesce(sum((node ->> 'Actual Rows')::numeric * (node ->> 'Actual Loops')::numeric), 0)::bigint FROM scans),
        (SELECT coalesce(sum(coalesce((node ->> 'Rows Removed by Filter')::numeric, 0)
                             * (node ->> 'Actual Loops')::numeric), 0)::bigint FROM scans),
        EXISTS (SELECT 1 FROM nodes WHERE node ->> 'Node Type' IN ('Sort', 'Incremental Sort')),
        (SELECT string_agg(t, ' → ' ORDER BY p)
         FROM (SELECT node ->> 'Node Type' AS t, min(path) AS p FROM nodes GROUP BY 1) x)
$$;

-- Прогрев, JSON-план для разбора, текстовый план в лог; время берётся из напечатанного прогона
CREATE FUNCTION lab03.measure(p_part TEXT, p_query TEXT, p_variant TEXT, p_sql TEXT, p_parent REGCLASS)
RETURNS SETOF TEXT
LANGUAGE plpgsql AS $$
DECLARE
    plan JSON;
    line TEXT;
    exec_ms NUMERIC;
    plan_ms NUMERIC;
    buffers BIGINT;
BEGIN
    EXECUTE 'EXPLAIN (ANALYZE, TIMING OFF) ' || p_sql;
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || p_sql INTO plan;

    RETURN NEXT format('--- %s | %s', p_query, p_variant);
    RETURN NEXT p_sql;
    FOR line IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS) ' || p_sql LOOP
        RETURN NEXT line;
        IF exec_ms IS NULL AND line ~ '^Execution Time:' THEN
            exec_ms := substring(line FROM 'Execution Time: ([0-9.]+)')::numeric;
        END IF;
        IF plan_ms IS NULL AND line ~ '^Planning Time:' THEN
            plan_ms := substring(line FROM 'Planning Time: ([0-9.]+)')::numeric;
        END IF;
        IF buffers IS NULL AND line ~ 'Buffers: shared' THEN
            buffers := coalesce(substring(line FROM 'hit=([0-9]+)')::bigint, 0)
                     + coalesce(substring(line FROM 'read=([0-9]+)')::bigint, 0);
        END IF;
    END LOOP;

    INSERT INTO lab03.measurements (part, query, variant, partitions_total, partitions_in_plan, partitions_executed,
                                    subplans_removed, scan, indexes, actual_rows, rows_removed, has_sort, operations,
                                    buffers, planning_ms, execution_ms)
    SELECT p_part, p_query, p_variant, s.partitions_total, s.partitions_in_plan, s.partitions_executed,
           s.subplans_removed, s.scan, s.indexes, s.actual_rows, s.rows_removed, s.has_sort, s.operations,
           buffers, plan_ms, exec_ms
    FROM lab03.plan_summary(plan::jsonb, p_parent) s;
    RETURN NEXT '';
END $$;

-- Ошибку вставки печатаем как текст, чтобы скрипт продолжал работу (ON_ERROR_STOP)
CREATE FUNCTION lab03.try_sql(p_sql TEXT) RETURNS TEXT
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RETURN 'OK: ' || p_sql;
EXCEPTION WHEN others THEN
    RETURN format('ОШИБКА [%s]: %s', SQLSTATE, SQLERRM);
END $$;

SELECT 'схема lab03 готова' AS status;
