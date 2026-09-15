#!/usr/bin/env bash
# ЛР №5, задание 3: router внутри сервиса. Задача создаётся через API, сервис сам выбирает шард;
# SQL на каждом шарде показывает, где она оказалась. Чтение задач пользователя идёт на один шард.
# Результат: docs/lab-05/results/05-api-routing.txt
source "$(dirname "$0")/lib.sh"

USER_ID=$(docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -tA -c "SELECT id FROM users WHERE username = 'gen_user_100'")

{
    echo "=== Топология сервиса"
    docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -c "SELECT strategy, active_shards, virtual_nodes FROM shard_topology"

    echo "=== GET /api/shards/route/{userId}: куда router отправит задачи gen_user_100"
    api_get "/api/shards/route/$USER_ID" | jq '{userId, hash, shard, modulo, consistentHashing}'

    echo
    echo "=== POST /api/shards/users/{userId}/tasks: создание задачи через router"
    CREATED=$(api_post "/api/shards/users/$USER_ID/tasks" '{"title":"LR5: task routed by user_id","priority":"High"}')
    jq '{shard, foundOnShards, task: {id: .task.id, title: .task.title, userId: .task.userId}}' <<< "$CREATED"
    TASK_ID=$(jq -r '.task.id' <<< "$CREATED")

    echo
    echo "=== SQL на каждом шарде: где лежит созданная задача"
    for i in 0 1 2; do
        shard_sql "$i" "SELECT 'shard-$i' AS shard, count(*) AS found FROM tasks WHERE id = '$TASK_ID'" -tA -F ' | '
    done

    echo
    echo "=== GET /api/shards/users/{userId}/tasks: чтение идёт только на шард пользователя"
    api_get "/api/shards/users/$USER_ID/tasks?pageSize=3" |
        jq -r '"Shard \(.shard): всего задач \(.tasks.totalCount)", (.tasks.items[] | "  \(.createdAt)  \(.title)")'

    echo
    echo "=== Запрос по ключу шардирования попадает в индекс одного шарда"
    SHARD=$(api_get "/api/shards/route/$USER_ID" | jq '.shard')
    shard_sql "$SHARD" "EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM tasks WHERE user_id = '$USER_ID' ORDER BY created_at DESC LIMIT 10"

    echo "=== Уборка"
    shard_sql "$SHARD" "DELETE FROM tasks WHERE title LIKE 'LR5:%'"
} > "$OUT/05-api-routing.txt" 2>&1

echo "Готово: $OUT/05-api-routing.txt"
