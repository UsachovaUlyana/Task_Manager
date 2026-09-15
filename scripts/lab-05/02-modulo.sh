#!/usr/bin/env bash
# ЛР №5, задания 3–5: router hash(user_id) % 3, распределение задач и цена перехода на 4 шарда.
# Результат: docs/lab-05/results/02-modulo.txt
source "$(dirname "$0")/lib.sh"

{
    echo "=== Задание 3–4. Загрузка всех задач сервиса на 3 шарда: shard = hash(user_id) % 3"
    api_post "/api/shards/load?strategy=Modulo&shards=3" | jq -r '"Загружено задач: \(.records), за \(.seconds) с"'

    echo
    echo "=== Router: куда попадают задачи конкретных пользователей"
    echo "Пользователь user_id                                hash (64 бита)         % 3        % 4"
    docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -tA -F ' ' \
        -c "SELECT username, id FROM users WHERE username IN ('gen_user_1','gen_user_2','gen_user_3','gen_user_100','gen_admin') ORDER BY username" |
    while read -r name id; do
        api_get "/api/shards/route/$id" |
            jq -r --arg n "$name" '"\($n)|\(.userId)|\(.hash)|Shard \(.modulo["N=3"])|Shard \(.modulo["N=4"])"' |
            awk -F'|' '{ printf "%-12s %-38s %-22s %-10s %-10s\n", $1, $2, $3, $4, $5 }'
    done

    echo
    echo "=== Распределение: SQL на каждом шарде"
    shard_counts 3

    echo
    echo "=== Равномерность по данным сервиса"
    api_get "/api/shards" | jq -r '"Самый большой шард / средний: \(.maxToAverage)\nОтносительное отклонение размеров: \(.deviationPercent) %"'

    echo
    echo "=== Самые «тяжёлые» пользователи каждого шарда"
    for i in 0 1 2; do
        shard_sql "$i" "SELECT 'shard-$i' AS shard, user_id, count(*) AS tasks FROM tasks GROUP BY user_id ORDER BY count(*) DESC LIMIT 2"
    done

    echo "=== Задание 5. Добавляем шард: hash(user_id) % 3 → hash(user_id) % 4"
    api_get "/api/shards/simulate/rebalance?strategy=Modulo&from=3&to=4" > /tmp/lab05-modulo-plan.json
    jq -r '"Всего задач:              \(.totalRecords)
Новый шард:               Shard 3
Изменили shard:           \(.movedRecords)
Не изменили:              \(.totalRecords - .movedRecords)
Перемещено:               \(.movedPercent) %
Пользователей переехало:  \(.movedKeys) из \(.totalKeys)"' /tmp/lab05-modulo-plan.json
    echo
    echo "--- Потоки задач между шардами"
    jq -r '.moves | to_entries[] | "Shard \(.key): \(.value)"' /tmp/lab05-modulo-plan.json
    echo
    echo "--- Распределение после перехода на 4 шарда"
    jq -r '.after.shards[] | "Shard \(.shard): \(.records) задач (\(.percent) %)"' /tmp/lab05-modulo-plan.json
} > "$OUT/02-modulo.txt" 2>&1

cp /tmp/lab05-modulo-plan.json "$OUT/02-modulo-plan.json"
echo "Готово: $OUT/02-modulo.txt"
