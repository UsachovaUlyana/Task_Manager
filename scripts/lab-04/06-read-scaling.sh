#!/usr/bin/env bash
# ЛР №4, контрольный вопрос 7: что даёт Read Scaling.
# Одна и та же читающая нагрузка (pgbench, 16 клиентов) сначала целиком на Primary,
# затем поровну между Primary и Replica. Сравниваем суммарную пропускную способность.
# Результат: docs/lab-04/results/06-read-scaling.txt
#
#   bash scripts/lab-04/06-read-scaling.sh

set -euo pipefail
cd "$(dirname "$0")/../.."
# Git Bash иначе превращает /scripts/... в путь Windows
export MSYS_NO_PATHCONV=1

OUT=docs/lab-04/results
mkdir -p "$OUT"
SECONDS_PER_RUN=${SECONDS_PER_RUN:-20}
# pgbench запускается внутри контейнера и ходит в свой сервер через unix-сокет
PGB_PRIMARY="docker compose exec -T postgres pgbench -U taskmanager -d taskmanager_db -n -f /scripts/lab-04/read-query.sql -T $SECONDS_PER_RUN"
PGB_REPLICA="docker compose exec -T postgres-replica pgbench -U taskmanager -d taskmanager_db -n -f /scripts/lab-04/read-query.sql -T $SECONDS_PER_RUN"

tps() { grep -E '^tps = ' "$1" | head -1 | sed -E 's/tps = ([0-9.]+).*/\1/'; }

{
    echo "=== Запрос нагрузки"
    cat scripts/lab-04/read-query.sql

    echo "=== Опыт A: 16 клиентов только на Primary"
    $PGB_PRIMARY -c 16 -j 4 > /tmp/lab04-a-primary.txt 2>&1 || true
    cat /tmp/lab04-a-primary.txt

    echo "=== Опыт B: 8 клиентов на Primary и 8 на Replica одновременно"
    $PGB_PRIMARY -c 8 -j 4 > /tmp/lab04-b-primary.txt 2>&1 &
    B_PRIMARY=$!
    $PGB_REPLICA -c 8 -j 4 > /tmp/lab04-b-replica.txt 2>&1 &
    B_REPLICA=$!
    wait $B_PRIMARY $B_REPLICA
    echo "--- Primary:"
    cat /tmp/lab04-b-primary.txt
    echo "--- Replica:"
    cat /tmp/lab04-b-replica.txt

    echo "=== Опыт C: то же чтение, но на Primary идёт постоянная запись"
    echo "Фоновая нагрузка: UPDATE задач за последние 3 месяца в цикле."
    (
        END=$((SECONDS + 2 * SECONDS_PER_RUN + 10))
        while [ $SECONDS -lt $END ]; do
            docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -q                 -c "UPDATE tasks SET updated_at = now() WHERE created_at >= now() - INTERVAL '3 months'" > /dev/null 2>&1 || true
        done
    ) &
    WRITER=$!
    sleep 3

    echo "--- 8 клиентов читают Primary, который занят записью:"
    $PGB_PRIMARY -c 8 -j 4 > /tmp/lab04-c-primary.txt 2>&1 || true
    cat /tmp/lab04-c-primary.txt
    echo "--- 8 клиентов читают Replica, пока Primary занят той же записью:"
    $PGB_REPLICA -c 8 -j 4 > /tmp/lab04-c-replica.txt 2>&1 || true
    cat /tmp/lab04-c-replica.txt

    wait $WRITER 2>/dev/null || true
} > "$OUT/06-read-scaling.txt" 2>&1

A=$(tps /tmp/lab04-a-primary.txt)
BP=$(tps /tmp/lab04-b-primary.txt)
BR=$(tps /tmp/lab04-b-replica.txt)
CP=$(tps /tmp/lab04-c-primary.txt)
CR=$(tps /tmp/lab04-c-replica.txt)
{
    echo
    echo "=== Итог (транзакций в секунду)"
    printf 'A. 16 клиентов только на Primary : %s\n' "$A"
    printf 'B. 8 клиентов на Primary         : %s\n' "$BP"
    printf 'B. 8 клиентов на Replica         : %s\n' "$BR"
    printf 'B. суммарно Primary + Replica    : %s\n' "$(awk -v p="$BP" -v r="$BR" 'BEGIN { printf "%.1f", p + r }')"
    printf 'Прирост B к A                    : %s %%\n' "$(awk -v a="$A" -v p="$BP" -v r="$BR" 'BEGIN { printf "%.1f", (p + r - a) / a * 100 }')"
    printf 'C. 8 клиентов на Primary под записью : %s
' "$CP"
    printf 'C. 8 клиентов на Replica под записью : %s
' "$CR"
    printf 'Выигрыш чтения на Replica            : %s %%
' "$(awk -v p="$CP" -v r="$CR" 'BEGIN { printf "%.1f", (r - p) / p * 100 }')"
} >> "$OUT/06-read-scaling.txt"

tail -8 "$OUT/06-read-scaling.txt"
echo "Готово: $OUT/06-read-scaling.txt"
