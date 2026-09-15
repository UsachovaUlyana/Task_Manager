#!/usr/bin/env bash
# ЛР №5: общие функции скриптов. Подключается через source.
# Нужны запущенный docker compose (API на http://localhost:5000), curl и jq.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

API=http://localhost:5000
OUT=docs/lab-05/results
mkdir -p "$OUT"

TOKEN=$(curl -s -X POST "$API/api/auth/login" -H 'Content-Type: application/json' \
    -d '{"username":"gen_admin","password":"Password123!"}' | jq -r '.data.token')

# GET/POST к API шардирования; ответ — поле data
api_get()  { curl -s -m 900 -H "Authorization: Bearer $TOKEN" "$API$1" | jq '.data'; }
api_post() { curl -s -m 900 -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
                  ${2:+-d "$2"} "$API$1" | jq '.data'; }

# psql прямо на шард: shard_sql 0 "SELECT ..."
shard_sql() { docker compose exec -T "postgres-shard-$1" psql -U taskmanager -d taskmanager_shard -X "${@:3}" -c "$2"; }

# Реальное количество задач на каждом шарде — SQL на самих экземплярах, мимо сервиса
shard_counts() {
    local total=0
    echo "Шард          Задач   Польз.     Доля  Размер"
    local rows=()
    for i in $(seq 0 $(($1 - 1))); do
        rows+=("$i $(shard_sql "$i" "SELECT count(*), count(DISTINCT user_id), pg_size_pretty(pg_total_relation_size('tasks')) FROM tasks" -tA -F ' ')")
    done
    for row in "${rows[@]}"; do total=$((total + $(echo "$row" | awk '{print $2}'))); done
    for row in "${rows[@]}"; do
        echo "$row" | awk -v t="$total" '{ printf "Shard %-2s %10d %10d %7.2f%% %6s %s\n", $1, $2, $3, 100*$2/t, $4, $5 }'
    done
    printf 'Всего    %10d\n' "$total"
}
