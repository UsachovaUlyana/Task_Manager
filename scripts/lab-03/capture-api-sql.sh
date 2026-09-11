#!/usr/bin/env bash
# ЛР №3, часть 12: какой SQL отправляет EF Core для запросов API к tasks.
# Включает логирование всех запросов PostgreSQL, вызывает endpoint'ы, выключает логирование
# и сохраняет лог в docs/lab-03/results/api-sql.log. Из него собран scripts/lab-03/11-api-queries.sql.
#
#   bash scripts/lab-03/capture-api-sql.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

API=http://localhost:5000
OUT=docs/lab-03/results/api-sql.log
PSQL="docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -At"

login() {
    curl -s -X POST "$API/api/auth/login" -H 'Content-Type: application/json' \
        -d "{\"username\":\"$1\",\"password\":\"Password123!\"}" | sed -E 's/.*"token":"([^"]+)".*/\1/'
}

# Пользователь с наибольшим числом задач и его последняя задача (те же, что в 10-service-queries.sql)
USER_ID=$($PSQL -c "SELECT user_id FROM tasks GROUP BY user_id ORDER BY count(*) DESC, user_id LIMIT 1")
TASK_ID=$($PSQL -c "SELECT id FROM tasks WHERE user_id = '$USER_ID' ORDER BY created_at DESC, id LIMIT 1")
ADMIN=$(login gen_admin)
USER_TOKEN=$(login "$($PSQL -c "SELECT username FROM users WHERE id = '$USER_ID'")")

call() {
    printf '%-4s %-80s ' "$1" "$2"
    curl -s -o /dev/null -w "HTTP %{http_code}, %{time_total} s\n" -H "Authorization: Bearer $3" "$API$2"
}

# Списки задач кэшируются в Redis: без очистки кэша запрос не дойдёт до базы
docker exec taskmanager-redis redis-cli FLUSHALL > /dev/null
$PSQL -c "ALTER SYSTEM SET log_min_duration_statement = 0" -c "SELECT pg_reload_conf()" > /dev/null
sleep 1
SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

call A1 "/api/tasks?createdFrom=2026-08-01&createdTo=2026-08-31T23:59:59" "$ADMIN"
call A2 "/api/tasks?status=Pending&createdFrom=2026-09-01&createdTo=2026-09-07T23:59:59" "$ADMIN"
call A3 "/api/tasks?createdFrom=2026-08-01&createdTo=2026-08-31T23:59:59" "$USER_TOKEN"
call A4 "/api/tasks/$TASK_ID" "$ADMIN"
call A5 "/api/tasks/stats" "$ADMIN"
call A6 "/api/tasks" "$ADMIN"

sleep 1
$PSQL -c "ALTER SYSTEM RESET log_min_duration_statement" -c "SELECT pg_reload_conf()" > /dev/null
docker logs --since "$SINCE" taskmanager-postgres > "$OUT" 2>&1
echo "Лог запросов: $OUT"
