#!/usr/bin/env bash
# ЛР №4, часть 6: replication lag — задержка между записью на Primary и её появлением на Replica.
# Три опыта: без нагрузки, под нагрузкой и с намеренно остановленным применением WAL.
# Результат: docs/lab-04/results/04-lag.txt, docs/lab-04/results/04-lag-samples.csv
#
#   bash scripts/lab-04/04-lag.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=docs/lab-04/results
mkdir -p "$OUT"
PRIMARY="docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X"
REPLICA="docker compose exec -T postgres-replica psql -U taskmanager -d taskmanager_db -X"
MARK="ЛР4: замер задержки $(date -u '+%H:%M:%S')"

$PRIMARY -q -c "DELETE FROM tasks WHERE title LIKE 'ЛР4:%'" > /dev/null

{
    echo "=== Опыт 1. Без нагрузки: сколько идёт одна строка от Primary до Replica"
    echo "Replica в цикле ждёт строку и сравнивает своё время с created_at, проставленным на Primary."

    for i in 1 2 3 4 5; do
        # Ожидание запускается заранее, чтобы в замер не попало время запуска psql
        $REPLICA -q -c "
            DO \$\$
            DECLARE created TIMESTAMPTZ;
            BEGIN
                LOOP
                    SELECT created_at INTO created FROM tasks WHERE title = '$MARK #$i';
                    EXIT WHEN created IS NOT NULL;
                    PERFORM pg_sleep(0.002);
                END LOOP;
                RAISE NOTICE 'замер %: строка появилась на Replica через % мс после коммита на Primary',
                    $i, round(extract(epoch FROM clock_timestamp() - created) * 1000, 1);
            END \$\$;" 2>&1 &
        WAITER=$!
        sleep 2

        $PRIMARY -q -c "
            INSERT INTO tasks (id, title, description, status, priority, user_id, created_at, updated_at)
            SELECT gen_random_uuid(), '$MARK #$i', 'замер задержки', 0, 1, id, clock_timestamp(), now()
            FROM users WHERE username = 'gen_admin'"
        wait $WAITER
    done

    echo
    echo "=== Опыт 2. Под нагрузкой: UPDATE ~240 тысяч задач на Primary"
    $PRIMARY -q -c "UPDATE tasks SET updated_at = now() WHERE created_at >= now() - INTERVAL '6 months'" &
    LOAD=$!
    $PRIMARY -tAc "SELECT lab04.sample_lag('нагрузка: UPDATE 6 месяцев задач', 25, 0.2)"
    wait $LOAD || true

    echo "--- отставание по ходу нагрузки (каждый пятый замер)"
    $PRIMARY -c "SELECT elapsed_ms AS ms, pg_size_pretty(lag_bytes) AS lag, lag_bytes, replay_lag_ms, state FROM lab04.lag_samples WHERE id % 5 = 0 ORDER BY id"

    echo "=== Опыт 3. Останавливаем применение WAL на Replica: pg_wal_replay_pause()"
    $REPLICA -c "SELECT pg_wal_replay_pause(), pg_is_wal_replay_paused() AS paused"

    $PRIMARY -q -c "
        INSERT INTO tasks (id, title, description, status, priority, user_id, created_at, updated_at)
        SELECT gen_random_uuid(), 'ЛР4: строка во время паузы', 'записана, пока Replica не применяет WAL', 0, 1, id, now(), now()
        FROM users WHERE username = 'gen_admin'"

    echo "--- Primary новую строку видит"
    $PRIMARY -c "SELECT count(*) AS rows_on_primary FROM tasks WHERE title = 'ЛР4: строка во время паузы'"
    echo "--- Replica ещё нет: вот он, replication lag"
    $REPLICA -c "SELECT count(*) AS rows_on_replica FROM tasks WHERE title = 'ЛР4: строка во время паузы'"
    $PRIMARY -x -c "SELECT sent_lsn, replay_lsn, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes, replay_lag FROM pg_stat_replication"

    echo "--- Возобновляем применение WAL"
    $REPLICA -c "SELECT pg_wal_replay_resume()"
    sleep 1
    $REPLICA -c "SELECT count(*) AS rows_on_replica FROM tasks WHERE title = 'ЛР4: строка во время паузы'"

    $PRIMARY -q -c "DELETE FROM tasks WHERE title LIKE 'ЛР4:%'" > /dev/null
} > "$OUT/04-lag.txt" 2>&1

docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -c "\copy (SELECT label, elapsed_ms, lag_bytes, write_lag_ms, flush_lag_ms, replay_lag_ms, state FROM lab04.lag_samples ORDER BY id) TO STDOUT WITH CSV HEADER" > "$OUT/04-lag-samples.csv"

echo "Готово: $OUT/04-lag.txt"
