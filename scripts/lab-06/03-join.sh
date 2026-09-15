#!/usr/bin/env bash
# ЛР №6, раздел 4: JOIN после шардирования — задачи на шардах, проекты и пользователи в основной базе.
# Результат: docs/lab-06/results/03-join.txt
source "$(dirname "$0")/lib.sh"

UID_=$(user_id gen_user_100)
SHARD=$(api_get "/api/shards/route/$UID_" | jq '.shard')

{
    echo "=== JOIN сервиса: список задач (TaskRepository.GetAllFilteredAsync, EF Core)"
    cat <<'SQL'
SELECT t0.*, p.*, u.*, t1.*
FROM (SELECT t.* FROM tasks AS t WHERE … ORDER BY t.created_at DESC LIMIT $1 OFFSET $2) AS t0
LEFT JOIN projects AS p ON t0.project_id = p.id
INNER JOIN users AS u ON t0.user_id = u.id
LEFT JOIN (SELECT t2.task_id, t2.tag_id, t3.* FROM task_tags AS t2 INNER JOIN tags AS t3 ON t2.tag_id = t3.id) AS t1
       ON t0.id = t1.task_id AND t0.created_at = t1.task_created_at
SQL

    echo
    echo "=== Где лежат таблицы этого JOIN после шардирования"
    for i in 0 1 2; do
        shard_sql "$i" "SELECT 'shard-$i' AS instance, string_agg(tablename, ', ' ORDER BY tablename) AS tables FROM pg_tables WHERE schemaname = 'public'" -tA -F ' | '
    done
    main_sql "SELECT 'main' AS instance, string_agg(tablename, ', ' ORDER BY tablename) AS tables FROM pg_tables WHERE schemaname = 'public' AND tablename IN ('users','projects','tags','task_tags','tasks')" -tA -F ' | '

    echo
    echo "=== Тот же JOIN одним SQL-запросом на шарде пользователя (Shard $SHARD)"
    shard_sql "$SHARD" "SELECT t.title, p.name FROM tasks t LEFT JOIN projects p ON p.id = t.project_id WHERE t.user_id = '$UID_' LIMIT 5" || true

    echo "=== JOIN на стороне сервиса: GET /api/shards/queries/users/{id}/tasks-with-projects"
    api_get "/api/shards/queries/users/$UID_/tasks-with-projects?pageSize=20" > /tmp/lab06-join.json
    jq -r '"Пользователь \(.username), Shard \(.shard), всего \(.totalMilliseconds) мс"' /tmp/lab06-join.json
    jq -r '.steps[] | "  \(.database): \(.query) → строк: \(.rows), \(.milliseconds) мс"' /tmp/lab06-join.json
    echo "--- первые строки результата"
    jq -r '.items[:5][] | "  \(.createdAt[:10])  \(.title)  →  \(.projectName // "без проекта")"' /tmp/lab06-join.json

    echo
    echo "=== Для сравнения: тот же JOIN в одной базе (основная база, все таблицы рядом)"
    main_sql "EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON) SELECT t.title, p.name, u.username FROM tasks t LEFT JOIN projects p ON p.id = t.project_id JOIN users u ON u.id = t.user_id WHERE t.user_id = '$UID_' ORDER BY t.created_at DESC LIMIT 20" | grep -E 'Execution Time|Planning Time'

    echo
    echo "=== Связанные записи на разных шардах: задачи одного проекта"
    echo "По скольким шардам разбросаны задачи каждого проекта (shard key — user_id, а не project_id):"
    for i in 0 1 2; do
        shard_sql "$i" "SELECT DISTINCT project_id FROM tasks WHERE project_id IS NOT NULL" -tA
    done | tr -d '\r' | sort | uniq -c | awk '{ spread[$1]++ } END { for (n in spread) printf "  проектов на %d шард(ах): %d\n", n, spread[n] }' | sort
    echo "--- самый большой проект: сколько его задач на каждом шарде"
    BIG=$(main_sql "SELECT project_id FROM tasks WHERE project_id IS NOT NULL GROUP BY project_id ORDER BY count(*) DESC LIMIT 1" -tA | tr -d '\r')
    for i in 0 1 2; do
        shard_sql "$i" "SELECT 'shard-$i' AS shard, count(*) AS tasks, count(DISTINCT user_id) AS users FROM tasks WHERE project_id = '$BIG'" -tA -F ' | '
    done
} > "$OUT/03-join.txt" 2>&1

echo "Готово: $OUT/03-join.txt"
