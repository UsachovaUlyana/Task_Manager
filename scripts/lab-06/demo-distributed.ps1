# ЛР №6: запросы после шардирования на работающем сервисе — агрегация, ORDER BY + LIMIT и отказ шарда.
#
#   powershell -ExecutionPolicy Bypass -File scripts/lab-06/demo-distributed.ps1

param([string]$Api = 'http://localhost:5000', [int]$Pause = 2)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Step([string]$text) { Write-Output ''; Write-Output "=== $text" }

$login = Invoke-RestMethod -Method Post -Uri "$Api/api/auth/login" -ContentType 'application/json' `
    -Body '{"username":"gen_admin","password":"Password123!"}'
$headers = @{ Authorization = "Bearer $($login.data.token)" }
function Get-Api([string]$path) { (Invoke-RestMethod -Uri "$Api$path" -Headers $headers).data }
function Get-Raw([string]$path) {
    # curl.exe вместо Invoke-WebRequest: в PowerShell 5.1 тело ответа с ошибкой иначе не прочитать
    $out = @(curl.exe -s -w "`n%{http_code}" -H "Authorization: Bearer $($login.data.token)" "$Api$path")
    $json = ($out[0..($out.Count - 2)] -join "`n") | ConvertFrom-Json
    if ($json.error) { "HTTP $($out[-1]) $($json.error.code)" } else { "HTTP $($out[-1])" }
}

Step 'COUNT по всем шардам: каждый шард считает свою часть, сервис складывает'
$stats = Get-Api '/api/shards/queries/stats'
foreach ($s in $stats.tasksPerShard.PSObject.Properties) { Write-Output ('{0}: {1,7} задач' -f $s.Name, $s.Value) }
Write-Output ('Итого:   {0,7} задач за {1} мс' -f $stats.total, $stats.totalMilliseconds)
Start-Sleep $Pause

Step 'ORDER BY created_at DESC LIMIT 5: top-5 с каждого шарда, слияние в сервисе'
$page = Get-Api '/api/shards/queries/newest?pageSize=5'
foreach ($t in $page.items) { Write-Output ('{0}  Shard {1}  {2}' -f "$($t.createdAt)".Substring(0, 19).Replace('T', ' '), $t.shard, $t.title) }
Start-Sleep $Pause

Step 'Отказ: останавливаем Shard 2'
cmd /c 'docker compose stop postgres-shard-2 >nul 2>&1'
Write-Output 'docker compose stop postgres-shard-2: остановлен'
$users = @{}
foreach ($n in 1..20) {
    $id = (docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -tA -c "SELECT id FROM users WHERE username = 'gen_user_$n'").Trim()
    $shard = (Get-Api "/api/shards/route/$id").shard
    if (-not $users.ContainsKey($shard)) { $users[$shard] = "gen_user_$n|$id" }
}
foreach ($shard in 0, 2) {
    $name, $id = $users[$shard] -split '\|'
    Write-Output ('Задачи {0,-11} (Shard {1}):      {2}' -f $name, $shard, (Get-Raw "/api/shards/users/$id/tasks"))
}
Write-Output ('Статистика по всем шардам:          {0}' -f (Get-Raw '/api/shards/queries/stats'))
$partial = Get-Api '/api/shards/queries/stats?allowPartial=true'
Write-Output ('Статистика, allowPartial=true:      partial={0}, total={1}' -f $partial.partial, $partial.total)
Write-Output ('Проекты (основная база):            {0}' -f (Get-Raw '/api/projects?pageSize=5'))
Start-Sleep $Pause

Step 'Восстановление: запускаем Shard 2'
cmd /c 'docker compose start postgres-shard-2 >nul 2>&1'
Write-Output 'docker compose start postgres-shard-2: запущен'
do { Start-Sleep 1; cmd /c 'docker compose exec -T postgres-shard-2 pg_isready -U taskmanager -d taskmanager_shard >nul 2>&1' } until ($LASTEXITCODE -eq 0)
Start-Sleep 2
Write-Output ('Статистика по всем шардам:          {0}, total={1}' -f (Get-Raw '/api/shards/queries/stats'), (Get-Api '/api/shards/queries/stats').total)
