#!/usr/bin/env bash
# ЛР №4, контрольный вопрос 7 (продолжение опыта 06): та же читающая нагрузка, но каждый
# экземпляр PostgreSQL ограничен 4 ядрами — так ведут себя два отдельных сервера.
# Результат: docs/lab-04/results/07-cpu-limited.txt
#
#   bash scripts/lab-04/07-cpu-limited-scaling.sh

set -euo pipefail
cd "$(dirname "$0")/../.."
export MSYS_NO_PATHCONV=1

OUT=docs/lab-04/results
mkdir -p "$OUT"
SECONDS_PER_RUN=${SECONDS_PER_RUN:-20}
LIMITED="docker compose -f docker-compose.yml -f docker/lab-04-cpu-limit.yml"
PGB_PRIMARY="docker compose exec -T postgres pgbench -U taskmanager -d taskmanager_db -n -f /scripts/lab-04/read-query.sql -T $SECONDS_PER_RUN"
PGB_REPLICA="docker compose exec -T postgres-replica pgbench -U taskmanager -d taskmanager_db -n -f /scripts/lab-04/read-query.sql -T $SECONDS_PER_RUN"

tps() { grep -E '^tps = ' "$1" | head -1 | sed -E 's/tps = ([0-9.]+).*/\1/'; }

echo "Ограничиваю Primary и Replica четырьмя ядрами"
$LIMITED up -d postgres postgres-replica > /dev/null 2>&1
sleep 20

{
    echo "=== Ограничение ресурсов"
    docker inspect taskmanager-postgres taskmanager-postgres-replica --format '{{.Name}}: NanoCpus={{.HostConfig.NanoCpus}}'

    echo "=== Опыт A: 16 клиентов только на Primary (4 ядра)"
    $PGB_PRIMARY -c 16 -j 4 > /tmp/lab04-cpu-a.txt 2>&1 || true
    cat /tmp/lab04-cpu-a.txt

    echo "=== Опыт B: 8 клиентов на Primary и 8 на Replica (по 4 ядра у каждого)"
    $PGB_PRIMARY -c 8 -j 4 > /tmp/lab04-cpu-b-primary.txt 2>&1 &
    BP_PID=$!
    $PGB_REPLICA -c 8 -j 4 > /tmp/lab04-cpu-b-replica.txt 2>&1 &
    BR_PID=$!
    wait $BP_PID $BR_PID
    echo "--- Primary:"
    cat /tmp/lab04-cpu-b-primary.txt
    echo "--- Replica:"
    cat /tmp/lab04-cpu-b-replica.txt
} > "$OUT/07-cpu-limited.txt" 2>&1

A=$(tps /tmp/lab04-cpu-a.txt)
BP=$(tps /tmp/lab04-cpu-b-primary.txt)
BR=$(tps /tmp/lab04-cpu-b-replica.txt)
{
    echo
    echo "=== Итог (транзакций в секунду, у каждого сервера по 4 ядра)"
    printf 'A. 16 клиентов только на Primary : %s\n' "$A"
    printf 'B. 8 клиентов на Primary         : %s\n' "$BP"
    printf 'B. 8 клиентов на Replica         : %s\n' "$BR"
    printf 'B. суммарно Primary + Replica    : %s\n' "$(awk -v p="$BP" -v r="$BR" 'BEGIN { printf "%.1f", p + r }')"
    printf 'Прирост B к A                    : %s %%\n' "$(awk -v a="$A" -v p="$BP" -v r="$BR" 'BEGIN { printf "%.1f", (p + r - a) / a * 100 }')"
} >> "$OUT/07-cpu-limited.txt"

echo "Снимаю ограничение ресурсов"
docker compose up -d postgres postgres-replica > /dev/null 2>&1
sleep 15

tail -7 "$OUT/07-cpu-limited.txt"
echo "Готово: $OUT/07-cpu-limited.txt"
