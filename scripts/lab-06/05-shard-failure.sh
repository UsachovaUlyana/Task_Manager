#!/usr/bin/env bash
# ЛР №6, раздел 6: отказ одного шарда. Shard 2 останавливается на работающем сервисе.
# Результат: docs/lab-06/results/05-shard-failure.txt
source "$(dirname "$0")/lib.sh"

# Пользователи, чьи задачи живут на Shard 0 и на Shard 2
pick_user() {
    for n in $(seq 1 100); do
        local id; id=$(user_id "gen_user_$n")
        if [ "$(api_get "/api/shards/route/$id" | jq '.shard' | tr -d '\r')" = "$1" ]; then echo "gen_user_$n $id"; return; fi
    done
}
read -r U0_NAME U0 <<< "$(pick_user 0)"
read -r U2_NAME U2 <<< "$(pick_user 2)"

check() { printf '%-46s %s\n' "$1" "$(http_time "$2" "$3" "${4:-}" | awk '{ printf "HTTP %s, %.3f с", $1, $2 }')"; }

endpoints() {
    check "GET /health (сервис в целом)"          GET  "/health"
    check "POST /api/auth/login (основная база)"  POST "/api/auth/login" '{"username":"gen_admin","password":"Password123!"}'
    check "GET /api/tasks (реплика)"              GET  "/api/tasks?pageSize=5"
    check "GET /api/projects (основная база)"     GET  "/api/projects?pageSize=5"
    check "Задачи $U0_NAME (Shard 0)"             GET  "/api/shards/users/$U0/tasks"
    check "Задачи $U2_NAME (Shard 2)"             GET  "/api/shards/users/$U2/tasks"
    check "Создать задачу $U2_NAME (Shard 2)"     POST "/api/shards/users/$U2/tasks" '{"title":"LR6: task during shard failure"}'
    check "Статистика по всем шардам"             GET  "/api/shards/queries/stats"
    check "Статистика, allowPartial=true"         GET  "/api/shards/queries/stats?allowPartial=true"
    check "Новые задачи по всем шардам"           GET  "/api/shards/queries/newest"
    check "Новые задачи, allowPartial=true"       GET  "/api/shards/queries/newest?allowPartial=true"
}

health() {
    api_get "/api/shards/queries/health" |
        jq -r '.[] | "Shard \(.shard): \(if .available then "доступен" else "НЕДОСТУПЕН" end), \(.milliseconds) мс"'
}

{
    echo "=== Пользователи для проверки: $U0_NAME → Shard 0, $U2_NAME → Shard 2"
    echo
    echo "=== До отказа: все шарды отвечают"
    health
    endpoints

    echo
    echo "=== Отказ: docker compose stop postgres-shard-2"
    docker compose stop postgres-shard-2 2>&1 | tail -1
    health
    echo
    endpoints

    echo
    echo "=== Что возвращает сервис при обращении к недоступному шарду"
    curl -s -H "Authorization: Bearer $TOKEN" "$API/api/shards/users/$U2/tasks" | jq -c '.error'
    echo "--- неполная статистика с явной пометкой"
    api_get "/api/shards/queries/stats?allowPartial=true" | jq -c '{partial, total, tasksPerShard, shards: [.shards[] | {shard, available}]}'

    echo
    echo "=== Восстановление: docker compose start postgres-shard-2"
    docker compose start postgres-shard-2 2>&1 | tail -1
    until docker compose exec -T postgres-shard-2 pg_isready -U taskmanager -d taskmanager_shard > /dev/null 2>&1; do sleep 1; done
    sleep 2
    health
    check "Задачи $U2_NAME (Shard 2) после восстановления" GET "/api/shards/users/$U2/tasks"
    api_get "/api/shards/queries/stats" | jq -r '"Статистика снова полная: \(.total) задач"'
    for i in 0 1 2; do shard_sql "$i" "DELETE FROM tasks WHERE title LIKE 'LR6:%'" -tA > /dev/null; done
} > "$OUT/05-shard-failure.txt" 2>&1

echo "Готово: $OUT/05-shard-failure.txt"
