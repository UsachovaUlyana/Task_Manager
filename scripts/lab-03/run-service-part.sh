#!/usr/bin/env bash
# ЛР №3, часть 12: запросы сервиса к tasks до и после партиционирования.
# Результаты: docs/lab-03/results/10-service-<variant>.txt и measurements.csv.
#
#   bash scripts/lab-03/run-service-part.sh before   # tasks ещё обычная таблица (до миграции 012)
#   bash scripts/lab-03/run-service-part.sh after    # после docker compose up: миграция 012 применена

set -euo pipefail
cd "$(dirname "$0")/../.."
export MSYS_NO_PATHCONV=1

VARIANT=${1:?укажите before или after}
OUT=docs/lab-03/results
mkdir -p "$OUT"
PSQL="docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -v ON_ERROR_STOP=1"

$PSQL -v variant="$VARIANT" -f /scripts/lab-03/10-service-queries.sql > "$OUT/10-service-$VARIANT.txt" 2>&1
if [ "$VARIANT" = after ]; then
    # SQL, который EF Core отправляет для endpoint'ов API (см. capture-api-sql.sh)
    $PSQL -f /scripts/lab-03/11-api-queries.sql > "$OUT/11-api-queries.txt" 2>&1
fi
$PSQL -c "\copy (SELECT part, query, variant, partitions_total, partitions_in_plan, partitions_executed, subplans_removed, scan, indexes, actual_rows, rows_removed, has_sort, operations, buffers, planning_ms, execution_ms FROM lab03.measurements ORDER BY id) TO STDOUT WITH CSV HEADER" > "$OUT/measurements.csv"
echo "Готово: $OUT/10-service-$VARIANT.txt"
