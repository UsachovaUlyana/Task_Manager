#!/usr/bin/env bash
# ЛР №6: все опыты подряд. Нужны запущенный docker compose, загруженные шарды (ЛР №5), curl и jq.
# Результаты: docs/lab-06/results/
#
#   bash scripts/lab-06/run-all.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

for script in 01-single-shard 02-aggregation 03-join 04-order-limit 05-shard-failure 06-hot-shard; do
    echo ">>> $script"
    bash "scripts/lab-06/$script.sh"
done

echo ">>> запись терминала (нужен vhs): vhs scripts/lab-06/demo.tape"
