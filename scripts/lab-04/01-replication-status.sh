#!/usr/bin/env bash
# ЛР №4, части 1–2: кто Primary, кто Replica и в каком состоянии streaming replication.
# Результат: docs/lab-04/results/01-status.txt
#
#   bash scripts/lab-04/01-replication-status.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=docs/lab-04/results
mkdir -p "$OUT"
PRIMARY="docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X"
REPLICA="docker compose exec -T postgres-replica psql -U taskmanager -d taskmanager_db -X"

{
    echo "=== Контейнеры"
    docker compose ps --format 'table {{.Name}}\t{{.Service}}\t{{.Status}}'

    echo
    echo "=== Кто есть кто: pg_is_in_recovery() — f у Primary, t у Replica"
    $PRIMARY -c "SELECT 'primary (порт 5432)' AS instance, pg_is_in_recovery() AS in_recovery, pg_current_wal_lsn() AS wal_lsn, current_setting('cluster_name') AS cluster_name"
    $REPLICA -c "SELECT 'replica (порт 5433)' AS instance, pg_is_in_recovery() AS in_recovery, pg_last_wal_replay_lsn() AS replay_lsn, current_setting('cluster_name') AS cluster_name"

    echo "=== Параметры репликации на Primary"
    $PRIMARY -c "SELECT name, setting, unit FROM pg_settings WHERE name IN ('wal_level','max_wal_senders','max_replication_slots','max_slot_wal_keep_size','synchronous_commit','hot_standby') ORDER BY name"

    echo "=== pg_stat_replication на Primary: подключённая Replica"
    $PRIMARY -x -c "SELECT application_name, client_addr, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn, write_lag, flush_lag, replay_lag, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes FROM pg_stat_replication"

    echo "=== Слот репликации на Primary"
    $PRIMARY -c "SELECT slot_name, slot_type, active, restart_lsn, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained FROM pg_replication_slots"

    echo "=== pg_stat_wal_receiver на Replica: приём WAL"
    $REPLICA -x -c "SELECT status, sender_host, sender_port, slot_name, written_lsn, flushed_lsn, latest_end_lsn, last_msg_receipt_time, conninfo FROM pg_stat_wal_receiver"

    echo "=== Данные на обоих экземплярах"
    $PRIMARY -c "SELECT 'primary' AS instance, count(*) AS tasks FROM tasks"
    $REPLICA -c "SELECT 'replica' AS instance, count(*) AS tasks FROM tasks"
} > "$OUT/01-status.txt" 2>&1

echo "Готово: $OUT/01-status.txt"
