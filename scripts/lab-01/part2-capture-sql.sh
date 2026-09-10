#!/usr/bin/env bash
# ЛР №1, часть 2: снимаем реальный SQL, который генерирует EF Core, из лога PostgreSQL,
# и замеряем время ответа API. Нужны запущенный docker compose и сгенерированные данные
# (scripts/generate-data.sql).
#
#   bash scripts/lab-01/part2-capture-sql.sh > docs/lab-01/results/part2-01-captured-sql.txt

set -euo pipefail
cd "$(dirname "$0")/../.."

API=${API:-http://localhost:5000}
PSQL="docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -q"

login() {
    curl -s -X POST "$API/api/auth/login" -H 'Content-Type: application/json' \
         -d "{\"username\":\"$1\",\"password\":\"Password123!\"}" \
        | grep -o '"token":"[^"]*"' | cut -d'"' -f4
}

call() {  # call <token> <path>
    local result
    result=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' -H "Authorization: Bearer $1" "$API$2")
    echo "GET $2 -> HTTP ${result% *}, ${result#* }s"
}

echo "### Профиль данных"
$PSQL -c "SELECT u.username, count(*) AS tasks
          FROM tasks t JOIN users u ON u.id = t.user_id
          WHERE u.username IN ('gen_user_1', 'gen_user_5000')
          GROUP BY u.username ORDER BY tasks DESC"
$PSQL -c "SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY c) AS median_tasks_per_user, max(c) AS max_tasks_per_user
          FROM (SELECT count(*) AS c FROM tasks GROUP BY user_id) s"
$PSQL -c "SELECT status, count(*), round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
          FROM tasks GROUP BY status ORDER BY status"

POWER_TOKEN=$(login gen_user_1)
TYPICAL_TOKEN=$(login gen_user_5000)
ADMIN_TOKEN=$(login gen_admin)

run_calls() {
    echo "--- gen_user_1 (активный пользователь)"
    call "$POWER_TOKEN"   "/api/tasks?page=1&pageSize=10"
    call "$POWER_TOKEN"   "/api/tasks?status=InProgress&priority=High&page=1&pageSize=10"
    call "$POWER_TOKEN"   "/api/tasks/stats"
    echo "--- gen_user_5000 (типичный пользователь)"
    call "$TYPICAL_TOKEN" "/api/tasks?page=1&pageSize=10"
    echo "--- gen_admin (видит все задачи)"
    call "$ADMIN_TOKEN"   "/api/tasks?page=1&pageSize=10"
    call "$ADMIN_TOKEN"   "/api/tasks?status=Pending&page=1&pageSize=10"
    call "$ADMIN_TOKEN"   "/api/tasks/stats"
}

# Прогрев: EF Core компилирует каждую новую форму запроса при первом вызове (~100-300 ms),
# это время не относится к базе данных
docker compose exec -T redis redis-cli FLUSHALL > /dev/null
run_calls > /dev/null

# Кэш Redis не должен скрывать обращения к БД; статистику индексов считаем только по этим запросам
docker compose exec -T redis redis-cli FLUSHALL > /dev/null
$PSQL -c "SELECT pg_stat_reset()" \
      -c "ALTER SYSTEM SET log_min_duration_statement = 0" \
      -c "SELECT pg_reload_conf()" > /dev/null
SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sleep 1

echo
echo "### Время ответа API (после прогрева, кэш Redis очищен)"
run_calls

# Бэкенды PostgreSQL 16 сбрасывают накопленную статистику не сразу, а раз в ~10 с простоя
sleep 11
$PSQL -c "ALTER SYSTEM RESET log_min_duration_statement" -c "SELECT pg_reload_conf()" > /dev/null

echo
echo "### Использование индексов этими запросами (pg_stat_user_indexes)"
$PSQL -c "SELECT relname, indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS size
          FROM pg_stat_user_indexes
          WHERE relname IN ('tasks', 'users', 'projects', 'task_tags', 'tags', 'user_projects')
          ORDER BY relname, idx_scan DESC, indexrelname"

echo
echo "### SQL из лога PostgreSQL"
docker logs --since "$SINCE" taskmanager-postgres 2>&1 \
    | grep -v -e 'pg_reload_conf' -e 'ALTER SYSTEM' -e 'received SIGHUP' -e 'parameter "log_min_duration_statement"' \
              -e 'pg_stat_user_indexes' -e 'relname IN'
