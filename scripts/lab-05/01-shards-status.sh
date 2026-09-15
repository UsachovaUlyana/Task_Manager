#!/usr/bin/env bash
# ЛР №5, задание 2: три независимых PostgreSQL и схема шарда.
# Результат: docs/lab-05/results/01-status.txt
source "$(dirname "$0")/lib.sh"

{
    echo "=== Контейнеры PostgreSQL"
    docker compose ps --format 'table {{.Name}}\t{{.Service}}\t{{.Status}}\t{{.Ports}}' | grep -E 'NAME|postgres'

    echo
    echo "=== Каждый шард — отдельный сервер со своими данными"
    for i in 0 1 2; do
        shard_sql "$i" "SELECT 'shard-$i' AS shard, current_database() AS database, inet_server_addr() AS address, pg_postmaster_start_time() AS started, system_identifier FROM pg_control_system()" 
    done

    echo "=== Схема таблицы на шарде (одинакова на всех шардах)"
    shard_sql 0 '\d tasks'

    echo "=== Топология шардов в основной базе (таблица shard_topology)"
    docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -c "SELECT * FROM shard_topology"
} > "$OUT/01-status.txt" 2>&1

echo "Готово: $OUT/01-status.txt"
