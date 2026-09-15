# ЛР №5: демонстрация шардирования задач по user_id на работающем сервисе.
# Нужен запущенный docker compose и загруженные на шарды задачи (bash scripts/lab-05/run-all.sh).
#
#   powershell -ExecutionPolicy Bypass -File scripts/lab-05/demo-sharding.ps1

param([string]$Api = 'http://localhost:5000', [int]$Pause = 2)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Step([string]$text) { Write-Output ''; Write-Output "=== $text" }

$login = Invoke-RestMethod -Method Post -Uri "$Api/api/auth/login" -ContentType 'application/json' `
    -Body '{"username":"gen_admin","password":"Password123!"}'
$headers = @{ Authorization = "Bearer $($login.data.token)" }
function Get-Api([string]$path) { (Invoke-RestMethod -Uri "$Api$path" -Headers $headers).data }

Step 'Три независимых PostgreSQL: задачи на каждом шарде (SQL мимо сервиса)'
foreach ($i in 0..2) {
    $row = docker compose exec -T "postgres-shard-$i" psql -U taskmanager -d taskmanager_shard -X -tA -F ' ' `
        -c "SELECT count(*), count(DISTINCT user_id) FROM tasks"
    $parts = $row.Trim() -split ' '
    Write-Output ('Shard {0}: {1,7} задач, {2,5} пользователей' -f $i, $parts[0], $parts[1])
}
Start-Sleep $Pause

Step 'Router: куда попадают задачи пользователя gen_user_1'
$userId = (docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -tA `
    -c "SELECT id FROM users WHERE username = 'gen_user_1'").Trim()
$route = Get-Api "/api/shards/route/$userId"
Write-Output "user_id = $userId"
Write-Output "hash    = $($route.hash)"
Write-Output ("hash % 3 -> Shard {0}    hash % 4 -> Shard {1}" -f $route.modulo.'N=3', $route.modulo.'N=4')
Write-Output ("ring  N=3 -> Shard {0}    ring  N=4 -> Shard {1}" -f $route.consistentHashing.'N=3', $route.consistentHashing.'N=4')
Start-Sleep $Pause

Step 'Добавляем шард: 3 -> 4. Сколько задач меняет shard'
Write-Output ('{0,-22} {1,12} {2,14}  {3}' -f 'Стратегия', 'Перемещено', 'Пользователей', 'Куда уходят задачи')
foreach ($s in 'Modulo', 'ConsistentHashing') {
    $plan = Get-Api "/api/shards/simulate/rebalance?strategy=$s&from=3&to=4&virtualNodes=500"
    $targets = ($plan.moves.PSObject.Properties | ForEach-Object { ($_.Name -split ' ')[-1] } | Sort-Object -Unique) -join ', '
    Write-Output ('{0,-22} {1,10} % {2,14}  на шарды {3}' -f $s, $plan.movedPercent, $plan.movedKeys, $targets)
}
Start-Sleep $Pause

Step 'Удаляем шард: 4 -> 3'
foreach ($s in 'Modulo', 'ConsistentHashing') {
    $plan = Get-Api "/api/shards/simulate/rebalance?strategy=$s&from=4&to=3&virtualNodes=500"
    $sources = ($plan.moves.PSObject.Properties | ForEach-Object { ($_.Name -split ' ')[0] } | Sort-Object -Unique) -join ', '
    Write-Output ('{0,-22} {1,10} %   задачи уходят с шардов {2}' -f $s, $plan.movedPercent, $sources)
}
