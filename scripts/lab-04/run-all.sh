#!/usr/bin/env bash
# ЛР №4: все замеры подряд. Нужен запущенный docker compose (Primary, Replica, API).
# Результаты: docs/lab-04/results/
#
#   bash scripts/lab-04/run-all.sh

set -euo pipefail
cd "$(dirname "$0")/../.."
export MSYS_NO_PATHCONV=1

echo ">>> схема замеров lab04 на Primary"
docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X -v ON_ERROR_STOP=1 \
    -f /scripts/lab-04/00-setup.sql > /dev/null

for script in 01-replication-status 02-prove-replication 03-read-only 04-lag 05-api-read-path 06-read-scaling 07-cpu-limited-scaling; do
    echo ">>> $script"
    bash "scripts/lab-04/$script.sh"
done

echo ">>> запись терминала (нужен vhs)"
echo "    vhs scripts/lab-04/demo.tape"
