#!/usr/bin/env bash
# Прогон всех экспериментов Части 1 ЛР №1 на отдельной БД lab01.
# Скрипты зависят друг от друга (набор индексов переходит из шага в шаг),
# поэтому выполняются строго по порядку.
#
# Запуск из корня репозитория (нужен запущенный docker compose):
#   bash scripts/lab-01/run-all.sh
# Результаты: docs/lab-01/results/*.txt

set -euo pipefail

cd "$(dirname "$0")/../.."
OUT=docs/lab-01/results
mkdir -p "$OUT"

PSQL="docker compose exec -T postgres psql -U taskmanager -X -v ON_ERROR_STOP=1"

$PSQL -d taskmanager_db -c "DROP DATABASE IF EXISTS lab01" -c "CREATE DATABASE lab01"

for f in scripts/lab-01/[0-9]*.sql; do
    name=$(basename "$f" .sql)
    echo ">>> $name"
    $PSQL -d lab01 < "$f" > "$OUT/$name.txt" 2>&1
done

echo "Готово: $OUT"
