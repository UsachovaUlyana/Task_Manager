#!/usr/bin/env bash
# ЛР №4, часть 4: Replica доступна только на чтение.
# Результат: docs/lab-04/results/03-read-only.txt
#
#   bash scripts/lab-04/03-read-only.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=docs/lab-04/results
mkdir -p "$OUT"
# VERBOSITY=verbose печатает код ошибки SQLSTATE
REPLICA="docker compose exec -T postgres-replica psql -U taskmanager -d taskmanager_db -X -v VERBOSITY=verbose"

{
    echo "=== Режим экземпляра"
    $REPLICA -c "SELECT pg_is_in_recovery() AS in_recovery, current_setting('transaction_read_only') AS transaction_read_only, current_setting('hot_standby') AS hot_standby"

    echo "=== SELECT на Replica работает"
    $REPLICA -c "SELECT count(*) AS tasks FROM tasks"

    echo "=== INSERT на Replica"
    $REPLICA -c "INSERT INTO tags (id, name, color, created_at) VALUES (gen_random_uuid(), 'from-replica', '#ffffff', now())" || true

    echo "=== UPDATE на Replica"
    $REPLICA -c "UPDATE tasks SET title = 'изменено на Replica' WHERE id = (SELECT id FROM tasks LIMIT 1)" || true

    echo "=== DELETE на Replica"
    $REPLICA -c "DELETE FROM tags WHERE name = 'from-replica'" || true

    echo "=== CREATE TABLE на Replica"
    $REPLICA -c "CREATE TABLE replica_test (id int)" || true

    echo "=== Даже явная транзакция на запись не открывается"
    $REPLICA -c "BEGIN READ WRITE; SELECT 1;" || true
} > "$OUT/03-read-only.txt" 2>&1

echo "Готово: $OUT/03-read-only.txt"
