#!/usr/bin/env bash
# ЛР №6, раздел 2: single-shard query — задачи одного пользователя.
# Результат: docs/lab-06/results/01-single-shard.txt
source "$(dirname "$0")/lib.sh"

USER=gen_user_100
UID_=$(user_id "$USER")
SHARD=$(api_get "/api/shards/route/$UID_" | jq '.shard')

{
    echo "=== Запрос сервиса: список задач пользователя (TaskRepository.GetByUserIdAsync, EF Core)"
    cat <<'SQL'
SELECT t.id, t.created_at, t.description, t.due_date, t.priority, t.project_id, t.status, t.title, t.updated_at, t.user_id
FROM tasks AS t
WHERE t.user_id = $1
ORDER BY t.created_at DESC
LIMIT $2 OFFSET $3
SQL

    echo
    echo "=== Router: $USER ($UID_) → Shard $SHARD"
    api_get "/api/shards/route/$UID_" | jq -c '{hash, shard, topology: .topology.strategy}'

    echo
    echo "=== Сколько задач пользователя на каждом шарде (SQL на шардах)"
    for i in 0 1 2; do
        shard_sql "$i" "SELECT 'shard-$i' AS shard, count(*) AS tasks_of_user FROM tasks WHERE user_id = '$UID_'" -tA -F ' | '
    done

    echo
    echo "=== GET /api/shards/users/{id}/tasks — сервис идёт только на Shard $SHARD"
    for run in 1 2 3; do
        echo "прогон $run: HTTP и время ответа, с: $(http_time GET "/api/shards/users/$UID_/tasks?pageSize=20")"
    done
    api_get "/api/shards/users/$UID_/tasks?pageSize=3" | jq -r '"Shard \(.shard), задач у пользователя: \(.tasks.totalCount)"'

    echo
    echo "=== План запроса на шарде пользователя"
    shard_sql "$SHARD" "EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT * FROM tasks WHERE user_id = '$UID_' ORDER BY created_at DESC LIMIT 20"
} > "$OUT/01-single-shard.txt" 2>&1

echo "Готово: $OUT/01-single-shard.txt"
