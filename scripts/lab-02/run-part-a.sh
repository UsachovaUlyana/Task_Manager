#!/usr/bin/env bash
# ЛР №2, часть A: полный прогон экспериментов с таблицей lab02.events.
# Нужен запущенный docker compose. Занимает 10–20 минут, на пике ~2 ГБ на диске.
#
#   bash scripts/lab-02/run-part-a.sh                  # объёмы до 10 млн
#   MAX_VOLUME=5000000 bash scripts/lab-02/run-part-a.sh
#
# Результаты: docs/lab-02/results/a*.txt (планы) и a-*.csv (сводные таблицы).

set -euo pipefail
cd "$(dirname "$0")/../.."
export MSYS_NO_PATHCONV=1   # Git Bash на Windows не должен переписывать пути /scripts/...

OUT=docs/lab-02/results
mkdir -p "$OUT"
PSQL="docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -v ON_ERROR_STOP=1"

$PSQL -f /scripts/lab-02/a0-setup.sql > "$OUT/a0-setup.txt" 2>&1
echo ">>> рост данных и замеры"
$PSQL -v max_volume="${MAX_VOLUME:-10000000}" -f /scripts/lab-02/a1-growth.sql > "$OUT/a1-growth.txt" 2>&1
echo ">>> цена индексов на запись"
$PSQL -f /scripts/lab-02/a2-write-cost.sql > "$OUT/a2-write-cost.txt" 2>&1
echo ">>> когда индекса недостаточно"
$PSQL -f /scripts/lab-02/a3-beyond-indexes.sql > "$OUT/a3-beyond-indexes.txt" 2>&1

$PSQL -c "\copy (SELECT volume, query, variant, scan, indexes, actual_rows, rows_removed, has_sort, operations, buffers, execution_ms FROM lab02.measurements WHERE part = 'A' ORDER BY id) TO STDOUT WITH CSV HEADER" > "$OUT/a-measurements.csv"
$PSQL -c "\copy (SELECT volume, object, bytes, build_ms FROM lab02.sizes ORDER BY volume, object) TO STDOUT WITH CSV HEADER" > "$OUT/a-sizes.csv"
$PSQL -c "\copy (SELECT experiment, rows, indexes, duration_ms FROM lab02.writes ORDER BY id) TO STDOUT WITH CSV HEADER" > "$OUT/a-writes.csv"

echo "Готово: $OUT"
