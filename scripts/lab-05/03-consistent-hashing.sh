#!/usr/bin/env bash
# ЛР №5, задания 6–7: consistent hashing (hash ring, 100 виртуальных узлов на шард) и сравнение с hash % N.
# Результат: docs/lab-05/results/03-consistent-hashing.txt
source "$(dirname "$0")/lib.sh"

summary() { jq -r '"\(.strategy) \(.fromShards) → \(.toShards): перемещено \(.movedRecords) из \(.totalRecords) задач (\(.movedPercent) %), пользователей \(.movedKeys)"'; }

{
    echo "=== Задание 6. Загрузка на 3 шарда через hash ring (100 виртуальных узлов на шард)"
    api_post "/api/shards/load?strategy=ConsistentHashing&shards=3&virtualNodes=100" | jq -r '"Загружено задач: \(.records), за \(.seconds) с"'

    echo
    echo "=== Router: те же пользователи, что и для hash % N"
    echo "Пользователь user_id                                ring N=3   ring N=4"
    docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -tA -F ' ' \
        -c "SELECT username, id FROM users WHERE username IN ('gen_user_1','gen_user_2','gen_user_3','gen_user_100','gen_admin') ORDER BY username" |
    while read -r name id; do
        api_get "/api/shards/route/$id" |
            jq -r --arg n "$name" '"\($n)|\(.userId)|Shard \(.consistentHashing["N=3"])|Shard \(.consistentHashing["N=4"])"' |
            awk -F'|' '{ printf "%-12s %-38s %-10s %-10s\n", $1, $2, $3, $4 }'
    done

    echo
    echo "=== Распределение: SQL на каждом шарде"
    shard_counts 3
    api_get "/api/shards" | jq -r '"Самый большой шард / средний: \(.maxToAverage), отклонение: \(.deviationPercent) %"'

    echo
    echo "=== Задание 7. Добавляем шард: 3 → 4"
    api_get "/api/shards/simulate/rebalance?strategy=ConsistentHashing&from=3&to=4&virtualNodes=100" > /tmp/lab05-ring-plan.json
    summary < /tmp/lab05-ring-plan.json
    echo "--- Потоки задач между шардами (все идут только на новый Shard 3)"
    jq -r '.moves | to_entries[] | "Shard \(.key): \(.value)"' /tmp/lab05-ring-plan.json
    echo "--- Распределение после перехода"
    jq -r '.after.shards[] | "Shard \(.shard): \(.records) задач (\(.percent) %)"' /tmp/lab05-ring-plan.json

    echo
    echo "=== Сравнение стратегий: 3 → 4 шарда"
    echo "Стратегия                Перемещено задач   Пользователей"
    for s in Modulo ConsistentHashing; do
        api_get "/api/shards/simulate/rebalance?strategy=$s&from=3&to=4&virtualNodes=100" |
            jq -r '"\(.strategy)|\(.movedPercent) %|\(.movedKeys)"' | awk -F'|' '{ printf "%-24s %-18s %s\n", $1, $2, $3 }'
    done

    echo
    echo "=== Что будет дальше: ещё один шард и удаление шарда"
    for change in "4 5" "5 6" "4 3" "3 2"; do
        set -- $change
        for s in Modulo ConsistentHashing; do
            api_get "/api/shards/simulate/rebalance?strategy=$s&from=$1&to=$2&virtualNodes=100" | summary
        done
    done
    echo "--- удаление Shard 3 из 4: откуда уходят задачи в hash ring"
    api_get "/api/shards/simulate/rebalance?strategy=ConsistentHashing&from=4&to=3&virtualNodes=100" |
        jq -r '.moves | to_entries[] | "Shard \(.key): \(.value)"'

    echo
    echo "=== Виртуальные узлы: равномерность 3 шардов и перенос при 3 → 4"
    echo "Узлов/шард   Макс/средний   Отклонение   Перемещено 3→4"
    for v in 1 10 50 100 500 1000; do
        d=$(api_get "/api/shards/simulate/distribution?strategy=ConsistentHashing&shards=3&virtualNodes=$v")
        m=$(api_get "/api/shards/simulate/rebalance?strategy=ConsistentHashing&from=3&to=4&virtualNodes=$v")
        printf '%-12s %-14s %-12s %s\n' "$v" "$(jq -r '.maxToAverage' <<< "$d")" "$(jq -r '.deviationPercent' <<< "$d") %" "$(jq -r '.movedPercent' <<< "$m") %"
    done
    echo "hash % 3     $(api_get '/api/shards/simulate/distribution?strategy=Modulo&shards=3' | jq -r '"\(.maxToAverage)          \(.deviationPercent) %"')"
} > "$OUT/03-consistent-hashing.txt" 2>&1

cp /tmp/lab05-ring-plan.json "$OUT/03-ring-plan.json"
echo "Готово: $OUT/03-consistent-hashing.txt"
