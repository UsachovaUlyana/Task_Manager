#!/usr/bin/env bash
# ЛР №3, части 1–9: партиционирование на учебных таблицах в схеме lab03 базы сервиса.
# Нужен запущенный docker compose. Результаты: docs/lab-03/results/0*.txt и measurements.csv.
#
#   bash scripts/lab-03/run-sql-part.sh

set -euo pipefail
cd "$(dirname "$0")/../.."
export MSYS_NO_PATHCONV=1

OUT=docs/lab-03/results
mkdir -p "$OUT"
PSQL="docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -v ON_ERROR_STOP=1"

for f in 00-setup 01-range-by-date 02-range-list-hash 03-partition-count; do
    echo ">>> $f"
    $PSQL -f "/scripts/lab-03/$f.sql" > "$OUT/$f.txt" 2>&1
done

$PSQL -c "\copy (SELECT part, query, variant, partitions_total, partitions_in_plan, partitions_executed, subplans_removed, scan, indexes, actual_rows, rows_removed, has_sort, operations, buffers, planning_ms, execution_ms FROM lab03.measurements ORDER BY id) TO STDOUT WITH CSV HEADER" > "$OUT/measurements.csv"
echo "Готово: $OUT"
