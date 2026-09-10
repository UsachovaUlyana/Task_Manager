#!/usr/bin/env bash
# ЛР №2, часть B: таблица tasks сервиса растёт ступенями, на каждой ступени выполняются
# реальные запросы сервиса (b1-measure.sql). Нужны запущенный docker compose и схема lab02
# (bash scripts/lab-02/run-part-a.sh или a0-setup.sql).
#
#   RESET=1 bash scripts/lab-02/run-part-b.sh            # начать с пустой tasks: 100 тыс. → 1 млн → 5 млн
#   VOLUMES="1000000 2000000" bash scripts/lab-02/run-part-b.sh
#
# RESET=1 удаляет ВСЕ задачи и связи задача–тег — только для тестовой базы.

set -euo pipefail
cd "$(dirname "$0")/../.."
export MSYS_NO_PATHCONV=1

OUT=docs/lab-02/results
mkdir -p "$OUT"
LOG="$OUT/b1-growth.txt"
PSQL="docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -v ON_ERROR_STOP=1"

: > "$LOG"
if [ "${RESET:-0}" = "1" ]; then
    echo ">>> очистка tasks" | tee -a "$LOG"
    $PSQL -c "TRUNCATE task_tags, tasks" >> "$LOG" 2>&1
fi

for target in ${VOLUMES:-100000 1000000 5000000}; do
    current=$($PSQL -tAc "SELECT count(*) FROM tasks")
    if [ "$target" -gt "$current" ]; then
        echo ">>> генерация задач: $current → $target" | tee -a "$LOG"
        $PSQL -v tasks=$((target - current)) -f /scripts/generate-data.sql >> "$LOG" 2>&1
        $PSQL -c "VACUUM (ANALYZE) tasks" -c "VACUUM (ANALYZE) task_tags" >> "$LOG" 2>&1
    fi
    echo ">>> замеры на $target задачах" | tee -a "$LOG"
    $PSQL -v variant="схема после ЛР №1" -f /scripts/lab-02/b1-measure.sql >> "$LOG" 2>&1
done

$PSQL -c "\copy (SELECT volume, query, variant, scan, indexes, actual_rows, rows_removed, has_sort, operations, buffers, execution_ms FROM lab02.measurements WHERE part = 'B' ORDER BY id) TO STDOUT WITH CSV HEADER" > "$OUT/b-measurements.csv"
$PSQL -c "\copy (SELECT volume, object, bytes FROM lab02.sizes WHERE object LIKE 'tasks:%' ORDER BY volume, object) TO STDOUT WITH CSV HEADER" > "$OUT/b-sizes.csv"

echo "Готово: $OUT"
