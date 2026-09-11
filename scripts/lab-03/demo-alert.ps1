# ЛР №3, части 10–11: сбой ночной задачи, alert в Telegram, восстановление и recovery.
# Нужен запущенный docker compose (API на http://localhost:5000). Пользователь gen_admin создаётся
# генератором scripts/generate-data.sql. Без .env с TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID
# сообщения только пишутся в лог API.
#
#   powershell -ExecutionPolicy Bypass -File scripts/lab-03/demo-alert.ps1                  # весь сценарий
#   powershell -ExecutionPolicy Bypass -File scripts/lab-03/demo-alert.ps1 -Phase break     # только сбой
#   powershell -ExecutionPolicy Bypass -File scripts/lab-03/demo-alert.ps1 -Phase restore   # только восстановление

param(
    [ValidateSet('all', 'break', 'restore')]
    [string]$Phase = 'all',
    [string]$Api = 'http://localhost:5000',
    [string]$Partition = 'events_2026_09_14',
    [int]$Pause = 3
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Step([string]$text) {
    Write-Output ''
    Write-Output "=== $text"
}

function Psql([string]$sql) {
    docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -At -c $sql
}

function Show($response) {
    foreach ($t in $response.data.tables) {
        $missing = if ($t.missingPartitions.Count) { $t.missingPartitions -join ', ' } else { '-' }
        $line = '{0,-13} {1,-9} missing: {2}' -f $t.table, $t.status, $missing
        if ($t.createdPartitions.Count) { $line += '   created: ' + ($t.createdPartitions -join ', ') }
        if ($t.alert) { $line += '   alert: ' + $t.alert }
        Write-Output $line
    }
}

function Health {
    $raw = @(curl.exe -s -w "`n%{http_code}" "$Api/health/partitions")
    $json = ($raw[0..($raw.Count - 2)] -join "`n") | ConvertFrom-Json
    $data = $json.checks[0].data.PSObject.Properties | ForEach-Object { "$($_.Name) = $($_.Value)" }
    Write-Output ('HTTP {0} {1}: {2}' -f $raw[-1], $json.status, ($data -join '; '))
}

$login = Invoke-RestMethod -Method Post -Uri "$Api/api/auth/login" -ContentType 'application/json' `
    -Body '{"username":"gen_admin","password":"Password123!"}'
$headers = @{ Authorization = "Bearer $($login.data.token)" }

function Call([string]$method, [string]$path) {
    Invoke-RestMethod -Method $method -Uri "$Api$path" -Headers $headers
}

if ($Phase -in 'all', 'break') {
    Step 'Партиции lab03.events: сегодня + 3 дня вперёд + 1 день запаса'
    Psql "SELECT string_agg(relname, ', ' ORDER BY relname) FROM pg_inherits JOIN pg_class ON oid = inhrelid WHERE inhparent = 'lab03.events'::regclass"
    Step 'GET /health/partitions'
    Health
    Start-Sleep $Pause

    Step "Сбой: ночная задача не отработала, партиции $Partition нет"
    Psql "DROP TABLE lab03.$Partition"
    Step 'GET /health/partitions'
    Health
    Step 'PartitionHealthCheck: POST /api/partitions/check'
    Show (Call Post '/api/partitions/check')
    Start-Sleep $Pause

    Step 'Через 5 минут проблема та же: POST /api/partitions/check'
    Show (Call Post '/api/partitions/check')
}

if ($Phase -in 'all', 'restore') {
    if ($Phase -eq 'all') { Start-Sleep $Pause }

    Step 'Восстановление: CreatePartitionsJob, POST /api/partitions/ensure'
    Show (Call Post '/api/partitions/ensure')
    Step 'Лог задачи в API'
    docker logs --since 5s taskmanager-api | Select-String 'Partition job|Creating|created successfully' |
        ForEach-Object { $_.Line -replace ' \{"SourceContext".*$', '' }
    Start-Sleep $Pause

    Step 'Повторная проверка: POST /api/partitions/check'
    Show (Call Post '/api/partitions/check')
    Step 'GET /health/partitions'
    Health
    Step 'Состояние алертов (partition_alert_state)'
    Psql "SELECT table_name || ': ' || status || ', изменено ' || to_char(changed_at, 'HH24:MI:SS') || ', оповещение ' || coalesce(to_char(notified_at, 'HH24:MI:SS'), '-') FROM partition_alert_state ORDER BY 1"
}
