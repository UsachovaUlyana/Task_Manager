#!/usr/bin/env bash
# ЛР №6, раздел 3: агрегирующий запрос по всем шардам — COUNT, AVG, GROUP BY status.
# Результат: docs/lab-06/results/02-aggregation.txt
source "$(dirname "$0")/lib.sh"

stats() { api_get "/api/shards/queries/stats?parallel=$1"; }

{
    echo "=== Запрос сервиса: GET /api/tasks/stats (TaskRepository.GetStatusStatsAsync)"
    echo "SELECT status, count(*), count(*) FILTER (WHERE due_date < now() AND status IN (0, 1)) FROM tasks GROUP BY status"

    echo
    echo "=== Что вернул каждый шард и что получилось после объединения"
    stats true > /tmp/lab06-stats.json
    jq -r '.shards[] | "Shard \(.shard): строк результата \(.rows), \(.milliseconds) мс"' /tmp/lab06-stats.json
    jq -r '.tasksPerShard | to_entries[] | "\(.key): \(.value) задач"' /tmp/lab06-stats.json
    jq -r '"Сумма после объединения: \(.total) задач"' /tmp/lab06-stats.json
    echo "--- по статусам после объединения"
    jq -r '.statuses[] | "\(.status): count=\(.count), overdue=\(.overdue), avg_age=\(.averageAgeDays) дн. (среднее средних шардов: \(.averageOfShardAveragesDays))"' /tmp/lab06-stats.json

    echo
    echo "=== Проверка на основной базе, где лежат все задачи одной таблицей"
    main_sql "SELECT count(*) AS total FROM tasks"
    main_sql "SELECT status, count(*), round(avg(extract(epoch FROM (now() - created_at)) / 86400)::numeric, 3) AS avg_age FROM tasks GROUP BY status ORDER BY status"

    echo "=== Одного шарда недостаточно: COUNT только на Shard 0"
    shard_sql 0 "SELECT count(*) AS only_shard_0 FROM tasks"

    echo "=== Время: шарды параллельно и по очереди (5 прогонов)"
    echo "прогон  параллельно, мс  по очереди, мс  шарды по очереди, мс"
    for run in 1 2 3 4 5; do
        p=$(stats true | jq -r '.totalMilliseconds')
        s=$(stats false)
        printf '%-7s %-16s %-15s %s\n' "$run" "$p" "$(jq -r '.totalMilliseconds' <<< "$s")" "$(jq -r '[.shards[].milliseconds] | join(" + ")' <<< "$s")"
    done

    echo
    echo "=== Больше шардов: та же агрегация на 4 шардах"
    docker compose --profile scale up -d postgres-shard-3 2>&1 | tail -1
    until docker compose exec -T postgres-shard-3 pg_isready -U taskmanager -d taskmanager_shard > /dev/null 2>&1; do sleep 2; done
    sleep 3
    api_post "/api/shards/rebalance?shards=4" | jq -r '"Перенесено на 4 шарда: \(.records) задач за \(.seconds) с"'
    echo "прогон  шардов  параллельно, мс  по очереди, мс"
    for run in 1 2 3 4 5; do
        printf '%-7s %-7s %-16s %s\n' "$run" 4 "$(stats true | jq -r '.totalMilliseconds')" "$(stats false | jq -r '.totalMilliseconds')"
    done
    stats true | jq -r '"Сумма на 4 шардах: \(.total)"'
    api_post "/api/shards/rebalance?shards=3" | jq -r '"Возврат на 3 шарда: \(.records) задач за \(.seconds) с"'
    docker compose --profile scale stop postgres-shard-3 2>&1 | tail -1
} > "$OUT/02-aggregation.txt" 2>&1

echo "Готово: $OUT/02-aggregation.txt"
