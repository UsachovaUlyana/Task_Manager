#!/usr/bin/env bash
# ЛР №6, раздел 7: hot shard. Одинаковое число строк на шардах и разная нагрузка на них.
# Сервис выполняет настоящие запросы «задачи пользователя» для пользователей, выбранных по распределению;
# независимая проверка — счётчик транзакций pg_stat_database на самих шардах.
# Результат: docs/lab-06/results/06-hot-shard.txt
source "$(dirname "$0")/lib.sh"

REQUESTS=${REQUESTS:-20000}

xacts() { for i in 0 1 2; do shard_sql "$i" "SELECT xact_commit FROM pg_stat_database WHERE datname = current_database()" -tA | tr -d '\r'; done; }

run() {
    local title=$1 query=$2
    echo "=== $title"
    local before; before=($(xacts))
    api_post "/api/shards/queries/workload?requests=$REQUESTS&$query" > /tmp/lab06-workload.json
    local after; after=($(xacts))
    jq -r '"Запросов: \(.requests), за \(.seconds) с\(if .hotUserId then ", популярный пользователь \(.hotUserId) на Shard \(.hotUserShard), его доля \(.hotSharePercent) %" else "" end)"' /tmp/lab06-workload.json
    echo "Шард  Доля запросов  Доля пользователей  Доля строк  Строк прочитано  Среднее, мс  p95, мс  Транзакций на шарде (pg_stat_database)"
    jq -r '.shards[] | "\(.shard)|\(.requestPercent)|\(.keyPercent)|\(.recordPercent)|\(.rowsRead)|\(.averageMilliseconds)|\(.p95Milliseconds)"' /tmp/lab06-workload.json | tr -d '\r' |
    while IFS='|' read -r shard req keys rec rows avg p95; do
        printf '%-5s %-14s %-19s %-11s %-16s %-12s %-8s %s\n' "$shard" "$req %" "$keys %" "$rec %" "$rows" "$avg" "$p95" "$(( ${after[$shard]} - ${before[$shard]} ))"
    done
    echo
}

{
    echo "=== Данные на шардах"
    shard_counts 3
    echo

    run "Равномерные пользователи: каждый пользователь делает одинаково запросов" "distribution=Uniform"
    run "Активность пропорциональна числу задач пользователя" "distribution=ByTasks"
    run "Популярный пользователь: 50 % всех запросов — gen_user_1" "distribution=HotUser&hotSharePercent=50"
    run "Популярный пользователь: 75 % всех запросов — gen_user_1" "distribution=HotUser&hotSharePercent=75"
} > "$OUT/06-hot-shard.txt" 2>&1

echo "Готово: $OUT/06-hot-shard.txt"
