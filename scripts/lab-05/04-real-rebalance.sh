#!/usr/bin/env bash
# ЛР №5: настоящий перенос данных. Hash ring (500 виртуальных узлов), запуск четвёртого PostgreSQL,
# переход 3 → 4 шарда с переносом задач, затем удаление шарда 4 → 3.
# Результат: docs/lab-05/results/04-real-rebalance.txt
source "$(dirname "$0")/lib.sh"

{
    echo "=== Исходное состояние: hash ring, 3 шарда, 500 виртуальных узлов"
    api_post "/api/shards/load?strategy=ConsistentHashing&shards=3&virtualNodes=500" | jq -r '"Загружено задач: \(.records), за \(.seconds) с"'
    shard_counts 3

    echo
    echo "=== Прогноз переноса 3 → 4"
    api_get "/api/shards/simulate/rebalance?strategy=ConsistentHashing&from=3&to=4&virtualNodes=500" |
        jq -r '"Переедет задач: \(.movedRecords) (\(.movedPercent) %), пользователей: \(.movedKeys)"'

    # Пользователь, чьи задачи переедут на новый шард: на нём покажем, что сервис их находит
    for n in $(seq 1 200); do
        USER_ID=$(docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -tA -c "SELECT id FROM users WHERE username = 'gen_user_$n'")
        if [ "$(api_get "/api/shards/route/$USER_ID" | jq '.consistentHashing["N=4"]')" = "3" ]; then
            USER_NAME="gen_user_$n"
            break
        fi
    done
    echo
    echo "=== Пользователь для проверки: $USER_NAME ($USER_ID)"
    api_get "/api/shards/users/$USER_ID/tasks?pageSize=1" | jq -r '"До переноса: задачи читаются с Shard \(.shard), всего \(.tasks.totalCount)"'

    echo
    echo "=== Запускаем четвёртый PostgreSQL"
    docker compose --profile scale up -d postgres-shard-3 2>&1 | tail -1
    until docker compose exec -T postgres-shard-3 pg_isready -U taskmanager -d taskmanager_shard > /dev/null 2>&1; do sleep 2; done
    sleep 3
    shard_sql 3 "SELECT 'shard-3' AS shard, count(*) AS tasks FROM tasks"

    echo "=== POST /api/shards/rebalance?shards=4 — перенос задач"
    api_post "/api/shards/rebalance?shards=4" |
        jq -r '"Перенесено задач: \(.records), пользователей: \(.keys), за \(.seconds) с\nТопология: \(.topology.strategy), шардов \(.topology.activeShards)"'
    echo "--- SQL на каждом шарде после переноса"
    shard_counts 4
    api_get "/api/shards/users/$USER_ID/tasks?pageSize=1" | jq -r '"После переноса: задачи $USER_NAME читаются с Shard \(.shard), всего \(.tasks.totalCount)"' | sed "s/\$USER_NAME/$USER_NAME/"

    echo
    echo "=== Удаляем шард: POST /api/shards/rebalance?shards=3"
    api_post "/api/shards/rebalance?shards=3" |
        jq -r '"Перенесено задач: \(.records), пользователей: \(.keys), за \(.seconds) с"'
    shard_counts 3
    shard_sql 3 "SELECT 'shard-3' AS shard, count(*) AS tasks_left FROM tasks"
    api_get "/api/shards/users/$USER_ID/tasks?pageSize=1" | jq -r '"После удаления шарда: задачи читаются с Shard \(.shard), всего \(.tasks.totalCount)"'

    docker compose --profile scale stop postgres-shard-3 2>&1 | tail -1
} > "$OUT/04-real-rebalance.txt" 2>&1

echo "Готово: $OUT/04-real-rebalance.txt"
