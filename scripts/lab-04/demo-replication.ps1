# ЛР №4: демонстрация Primary + Replica на работающем сервисе.
# Нужен запущенный docker compose (Primary 5432, Replica 5433, API 5000).
#
#   powershell -ExecutionPolicy Bypass -File scripts/lab-04/demo-replication.ps1            # всё подряд
#   powershell -ExecutionPolicy Bypass -File scripts/lab-04/demo-replication.ps1 -Phase basics
#   powershell -ExecutionPolicy Bypass -File scripts/lab-04/demo-replication.ps1 -Phase lag

param(
    [ValidateSet('all', 'basics', 'lag')]
    [string]$Phase = 'all',
    [string]$Api = 'http://localhost:5000',
    [int]$Pause = 3
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Step([string]$text) {
    Write-Output ''
    Write-Output "=== $text"
}

function Primary([string]$sql) {
    docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -c $sql
}

function Replica([string]$sql) {
    docker compose exec -T postgres-replica psql -U taskmanager -d taskmanager_db -X -c $sql
}

if ($Phase -in 'all', 'basics') {
    Step 'Два экземпляра PostgreSQL: pg_is_in_recovery() — f у Primary, t у Replica'
    Primary "SELECT 'primary :5432' AS instance, pg_is_in_recovery() AS in_recovery, pg_current_wal_lsn() AS lsn"
    Replica "SELECT 'replica :5433' AS instance, pg_is_in_recovery() AS in_recovery, pg_last_wal_replay_lsn() AS lsn"
    Start-Sleep $Pause

    Step 'Streaming replication глазами Primary'
    Primary "SELECT application_name, state, sync_state, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes FROM pg_stat_replication"
    Start-Sleep $Pause

    Step 'Пишем на Primary'
    Primary "DELETE FROM tags WHERE name LIKE 'lab04%'; INSERT INTO tags (id, name, color, created_at) VALUES (gen_random_uuid(), 'lab04-demo', '#00ff00', now())"
    Step 'Читаем на Replica: строка уже здесь'
    Replica "SELECT name, color, created_at FROM tags WHERE name = 'lab04-demo'"
    Start-Sleep $Pause

    Step 'Пробуем писать на Replica'
    Replica "INSERT INTO tags (id, name, color, created_at) VALUES (gen_random_uuid(), 'lab04-from-replica', '#ffffff', now())"
}

if ($Phase -in 'all', 'lag') {
    if ($Phase -eq 'all') { Start-Sleep $Pause }

    Step 'Останавливаем применение WAL на Replica: pg_wal_replay_pause()'
    Replica "SELECT pg_wal_replay_pause(), pg_is_wal_replay_paused() AS paused"

    Step 'Меняем цвет тега на Primary'
    Primary "UPDATE tags SET color = '#ff0000' WHERE name = 'lab04-demo'"
    Start-Sleep 1

    Step 'Primary отдаёт новое значение, Replica — старое: это replication lag'
    Primary "SELECT 'primary' AS instance, name, color FROM tags WHERE name = 'lab04-demo'"
    Replica "SELECT 'replica' AS instance, name, color FROM tags WHERE name = 'lab04-demo'"
    Primary "SELECT sent_lsn, replay_lsn, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes FROM pg_stat_replication"
    Start-Sleep $Pause

    Step 'Сервис показывает то же самое: GET /health/replica'
    curl.exe -s "$Api/health/replica"
    Write-Output ''
    Start-Sleep $Pause

    Step 'Возобновляем применение WAL'
    Replica "SELECT pg_wal_replay_resume()"
    Start-Sleep 1
    Replica "SELECT 'replica' AS instance, name, color FROM tags WHERE name = 'lab04-demo'"
    Primary "DELETE FROM tags WHERE name LIKE 'lab04%'"
}
