#!/usr/bin/env bash
# ЛР №6, раздел 5: ORDER BY created_at DESC LIMIT по трём шардам — слияние результатов и глубокие страницы.
# Результат: docs/lab-06/results/04-order-limit.txt
source "$(dirname "$0")/lib.sh"

{
    echo "=== Запрос сервиса: GET /api/tasks (администратор) — новые задачи первой страницей"
    echo "SELECT … FROM tasks ORDER BY created_at DESC LIMIT 10 OFFSET 0"

    echo
    echo "=== Первая страница, собранная со всех шардов: каждый шард отдаёт свои top-10, сервис сливает"
    api_get "/api/shards/queries/newest?page=1&pageSize=10" > /tmp/lab06-newest.json
    jq -r '.shards[] | "Shard \(.shard): отдал \(.rows) строк за \(.milliseconds) мс"' /tmp/lab06-newest.json
    jq -r '.items[] | "  \(.createdAt)  Shard \(.shard)  \(.title)"' /tmp/lab06-newest.json

    echo
    echo "=== Проверка: те же 10 задач в основной базе, где все задачи в одной таблице"
    main_sql "SELECT id FROM tasks ORDER BY created_at DESC, id DESC LIMIT 10" -tA | tr -d '\r' > /tmp/lab06-main-ids.txt
    jq -r '.items[].id' /tmp/lab06-newest.json | tr -d '\r' > /tmp/lab06-merged-ids.txt
    if diff -q /tmp/lab06-main-ids.txt /tmp/lab06-merged-ids.txt > /dev/null; then echo "Совпадает с основной базой: да, тот же порядок"; else echo "Совпадает с основной базой: НЕТ"; fi

    echo
    echo "=== Ошибка «взять первые 10 только с одного шарда»"
    for s in 0 1 2; do
        api_get "/api/shards/queries/newest/shard/$s?pageSize=10" | jq -r '.items[].id' | tr -d '\r' > /tmp/lab06-one.txt
        common=$(grep -cxFf /tmp/lab06-merged-ids.txt /tmp/lab06-one.txt || true)
        echo "Только Shard $s: из 10 задач в настоящую первую страницу входят $common"
    done

    echo
    echo "=== Глубокие страницы: сколько строк должен отдать каждый шард"
    echo "Страница  Строк с каждого шарда  Передано в сервис  Отдано клиенту  Время, мс"
    for page in 1 10 100 1000 5000; do
        r=$(api_get "/api/shards/queries/newest?page=$page&pageSize=10")
        printf '%-9s %-22s %-18s %-15s %s\n' "$page" "$(jq -r '.rowsRequestedPerShard' <<< "$r")" \
            "$(jq -r '[.shards[].rows] | add' <<< "$r")" "$(jq -r '.items | length' <<< "$r")" "$(jq -r '.totalMilliseconds' <<< "$r")"
    done

    echo
    echo "=== Проверка глубокой страницы 100 на основной базе"
    main_sql "SELECT id FROM tasks ORDER BY created_at DESC, id DESC LIMIT 10 OFFSET 990" -tA | tr -d '\r' > /tmp/lab06-main-p100.txt
    api_get "/api/shards/queries/newest?page=100&pageSize=10" | jq -r '.items[].id' | tr -d '\r' > /tmp/lab06-merged-p100.txt
    if diff -q /tmp/lab06-main-p100.txt /tmp/lab06-merged-p100.txt > /dev/null; then echo "Страница 100 совпадает с основной базой: да"; else echo "Страница 100 совпадает: НЕТ"; fi
} > "$OUT/04-order-limit.txt" 2>&1

echo "Готово: $OUT/04-order-limit.txt"
