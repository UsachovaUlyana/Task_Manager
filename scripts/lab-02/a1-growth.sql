-- ЛР №2, часть A (задания 2–8, 10): таблица events растёт до контрольных объёмов,
-- на каждом объёме выполняются одни и те же измерения (a1-step.sql).
-- 10 млн строк можно пропустить: psql -v max_volume=5000000 ...

\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

\if :{?max_volume}
\else
    \set max_volume 10000000
\endif

\set target 10000
\ir a1-step.sql
\set target 100000
\ir a1-step.sql
\set target 1000000
\ir a1-step.sql
\set target 5000000
\ir a1-step.sql

SELECT :max_volume >= 10000000 AS do_10m \gset
\if :do_10m
    \set target 10000000
    \ir a1-step.sql
\endif
