#!/usr/bin/env bash
# ЛР №4, часть 3: доказательство, что изменения с Primary доезжают до Replica.
# Результат: docs/lab-04/results/02-prove.txt
#
#   bash scripts/lab-04/02-prove-replication.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=docs/lab-04/results
mkdir -p "$OUT"
PRIMARY="docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X"
REPLICA="docker compose exec -T postgres-replica psql -U taskmanager -d taskmanager_db -X"

MARK="ЛР4: проверка репликации $(date -u '+%Y-%m-%d %H:%M:%S') UTC"

# Убираем строки прошлых запусков, чтобы скрипт можно было выполнять повторно
$PRIMARY -q -c "DELETE FROM tasks WHERE title LIKE 'ЛР4:%'" > /dev/null

# Задача создаётся на Primary от имени администратора, созданного генератором данных
TASK_ID=$($PRIMARY -q -tAc "
    INSERT INTO tasks (id, title, description, status, priority, user_id, created_at, updated_at)
    SELECT gen_random_uuid(), '$MARK', 'строка создана на Primary', 0, 1, id, now(), now()
    FROM users WHERE username = 'gen_admin'
    RETURNING id" | head -1 | tr -d '\r')

{
    echo "=== 1. Запись на Primary: INSERT в tasks (id = $TASK_ID)"
    $PRIMARY -x -c "SELECT id, title, status, created_at FROM tasks WHERE id = '$TASK_ID'"
    $PRIMARY -c "SELECT pg_current_wal_lsn() AS primary_wal_lsn"

    echo "=== 2. Чтение на Replica: та же строка"
    $REPLICA -x -c "SELECT id, title, status, created_at FROM tasks WHERE id = '$TASK_ID'"
    $REPLICA -c "SELECT pg_last_wal_replay_lsn() AS replica_replay_lsn, pg_last_xact_replay_timestamp() AS last_xact_replayed"

    echo "=== 3. UPDATE на Primary"
    $PRIMARY -c "UPDATE tasks SET title = title || ' (изменено на Primary)', status = 1, updated_at = now() WHERE id = '$TASK_ID'"

    echo "=== 4. Чтение на Replica после UPDATE"
    $REPLICA -x -c "SELECT title, status, updated_at FROM tasks WHERE id = '$TASK_ID'"

    echo "=== 5. DELETE на Primary"
    $PRIMARY -c "DELETE FROM tasks WHERE id = '$TASK_ID'"

    echo "=== 6. Чтение на Replica после DELETE (0 строк — удаление тоже приехало)"
    $REPLICA -c "SELECT count(*) AS rows_on_replica FROM tasks WHERE id = '$TASK_ID'"

    echo "=== 7. Позиции WAL совпали, отставания нет"
    $PRIMARY -x -c "SELECT application_name, state, sent_lsn, replay_lsn, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes FROM pg_stat_replication"
} > "$OUT/02-prove.txt" 2>&1

echo "Готово: $OUT/02-prove.txt"
