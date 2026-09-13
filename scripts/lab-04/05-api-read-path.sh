#!/usr/bin/env bash
# ЛР №4, часть 5: доказательство, что чтение сервиса идёт на Replica, а запись — на Primary.
# Включает логирование запросов на обоих экземплярах, дёргает API и показывает, в чьём логе
# оказался SELECT, а в чьём INSERT. Затем ловит устаревшее чтение через API (часть 6).
# Результат: docs/lab-04/results/05-api.txt
#
#   bash scripts/lab-04/05-api-read-path.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=docs/lab-04/results
mkdir -p "$OUT"
API=http://localhost:5000
PRIMARY="docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X"
REPLICA="docker compose exec -T postgres-replica psql -U taskmanager -d taskmanager_db -X"

TOKEN=$(curl -s -X POST "$API/api/auth/login" -H 'Content-Type: application/json' \
    -d '{"username":"gen_admin","password":"Password123!"}' | sed -E 's/.*"token":"([^"]+)".*/\1/')

log_on()  { $PRIMARY -q -c "ALTER SYSTEM SET log_min_duration_statement = 0" -c "SELECT pg_reload_conf()" > /dev/null
            $REPLICA -q -c "ALTER SYSTEM SET log_min_duration_statement = 0" -c "SELECT pg_reload_conf()" > /dev/null; }
log_off() { $PRIMARY -q -c "ALTER SYSTEM RESET log_min_duration_statement" -c "SELECT pg_reload_conf()" > /dev/null
            $REPLICA -q -c "ALTER SYSTEM RESET log_min_duration_statement" -c "SELECT pg_reload_conf()" > /dev/null; }

{
    echo "=== Состояние репликации по данным сервиса: GET /api/replication"
    curl -s -H "Authorization: Bearer $TOKEN" "$API/api/replication" | tr ',' '\n' | head -12
    echo
    echo "=== GET /health/replica"
    curl -s -w '\nHTTP %{http_code}\n' "$API/health/replica"

    # Списки кэшируются в Redis: без очистки кэша запрос не дойдёт до базы
    docker exec taskmanager-redis redis-cli FLUSHALL > /dev/null
    log_on
    SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    echo "=== GET /api/tasks?pageSize=5 — чтение списка задач"
    curl -s -o /dev/null -w 'HTTP %{http_code}, %{time_total} s\n' -H "Authorization: Bearer $TOKEN" "$API/api/tasks?pageSize=5"

    echo "=== POST /api/tasks — создание задачи"
    curl -s -o /dev/null -w 'HTTP %{http_code}, %{time_total} s\n' -X POST "$API/api/tasks" \
        -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
        -d '{"title":"LR4: task created through API","description":"the write must go to the Primary","status":"Pending","priority":"High"}'
    sleep 1
    log_off

    echo
    echo "--- SELECT списка задач в логе REPLICA (значит, чтение ушло на Replica):"
    (docker logs --since "$SINCE" taskmanager-postgres-replica 2>&1 | grep -c "FROM tasks AS t") || true
    (docker logs --since "$SINCE" taskmanager-postgres-replica 2>&1 | grep -A 3 "execute <unnamed>: SELECT t0.id" | head -12) || true

    echo "--- INSERT в логе PRIMARY (значит, запись ушла на Primary):"
    (docker logs --since "$SINCE" taskmanager-postgres 2>&1 | grep -B 1 -A 2 "INSERT INTO tasks" | head -12) || true

    echo "--- INSERT в логе REPLICA (должно быть пусто):"
    (docker logs --since "$SINCE" taskmanager-postgres-replica 2>&1 | grep -c "INSERT INTO tasks") || true

    echo
    echo "=== Устаревшее чтение через API: останавливаем применение WAL на Replica"
    $REPLICA -c "SELECT pg_wal_replay_pause()" > /dev/null
    echo "--- POST /api/tasks (Primary принимает запись)"
    curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST "$API/api/tasks" \
        -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
        -d '{"title":"LR4: created while replay is paused","description":"the Replica has not applied the WAL yet","status":"Pending","priority":"High"}'
    docker exec taskmanager-redis redis-cli FLUSHALL > /dev/null

    echo "--- GET /api/tasks?sort=-created_at&pageSize=1 — первая задача списка по версии Replica:"
    curl -s -H "Authorization: Bearer $TOKEN" "$API/api/tasks?pageSize=1&sort=-created_at" | grep -o '"title":"[^"]*"' | head -1
    echo "--- та же задача на Primary:"
    $PRIMARY -tAc "SELECT title FROM tasks ORDER BY created_at DESC LIMIT 1"

    echo "--- возобновляем применение WAL и повторяем GET"
    $REPLICA -c "SELECT pg_wal_replay_resume()" > /dev/null
    sleep 1
    docker exec taskmanager-redis redis-cli FLUSHALL > /dev/null
    curl -s -H "Authorization: Bearer $TOKEN" "$API/api/tasks?pageSize=1&sort=-created_at" | grep -o '"title":"[^"]*"' | head -1

    $PRIMARY -q -c "DELETE FROM tasks WHERE title LIKE 'ЛР4:%' OR title LIKE 'LR4%'" > /dev/null
} > "$OUT/05-api.txt" 2>&1

echo "Готово: $OUT/05-api.txt"
