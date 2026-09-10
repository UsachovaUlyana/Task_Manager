#!/usr/bin/env bash
# ЛР №2, часть B: время ответа API для запросов, которые исследуются в работе.
# Каждый вызов сначала выполняется вхолостую (EF Core компилирует запрос), затем кэш Redis
# очищается и вызов повторяется — в вывод попадает второй, «тёплый» замер.
#
#   bash scripts/lab-02/api-timing.sh "подпись замера" >> docs/lab-02/results/b-api-timing.txt

set -euo pipefail
cd "$(dirname "$0")/../.."

API=${API:-http://localhost:5000}
FROM=$(date -u -d '-180 days' +%F)
TO=$(date -u -d '-173 days' +%F)

token() {
    curl -s -X POST "$API/api/auth/login" -H 'Content-Type: application/json' \
         -d "{\"username\":\"$1\",\"password\":\"Password123!\"}" | grep -o '"token":"[^"]*"' | cut -d'"' -f4
}

# Тело ответа отбрасывает сам shell: `curl -o /dev/null` ломается в Git Bash при MSYS_NO_PATHCONV=1
timed() {  # timed <token> <path>
    docker compose exec -T redis redis-cli FLUSHALL > /dev/null
    curl -s -H "Authorization: Bearer $1" "$API$2" > /dev/null
    docker compose exec -T redis redis-cli FLUSHALL > /dev/null
    local result
    result=$(curl -s -w '\n%{http_code} %{time_total}' -H "Authorization: Bearer $1" "$API$2" | tail -n 1)
    echo "GET $2 -> HTTP ${result% *}, ${result#* }s"
}

ADMIN=$(token gen_admin)
USER=$(token gen_user_1)

echo "### ${1:-замер} ($(date -u '+%F %T') UTC), задач: $(docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -tAc 'SELECT count(*) FROM tasks')"
timed "$USER"  "/api/tasks?page=1&pageSize=10"
timed "$ADMIN" "/api/tasks?page=1&pageSize=10"
timed "$ADMIN" "/api/tasks?dueDateFrom=$FROM&dueDateTo=$TO&page=1&pageSize=10"
timed "$ADMIN" "/api/tasks?dueDateFrom=$FROM&dueDateTo=$TO&sort=due_date&page=1&pageSize=10"
timed "$ADMIN" "/api/tasks/stats"
echo
