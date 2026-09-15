#!/usr/bin/env bash
# ЛР №5: все опыты подряд. Нужны запущенный docker compose, curl и jq.
# Результаты: docs/lab-05/results/
#
#   bash scripts/lab-05/run-all.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

for script in 01-shards-status 02-modulo 03-consistent-hashing 04-real-rebalance 05-api-routing; do
    echo ">>> $script"
    bash "scripts/lab-05/$script.sh"
done

echo ">>> запись терминала (нужен vhs): vhs scripts/lab-05/demo.tape"
