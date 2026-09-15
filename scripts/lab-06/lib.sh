#!/usr/bin/env bash
# ЛР №6: общие функции — те же, что в ЛР №5 (вход в API, запросы, psql на шард), но результаты в docs/lab-06.
source "$(dirname "${BASH_SOURCE[0]}")/../lab-05/lib.sh"
OUT=docs/lab-06/results
mkdir -p "$OUT"

main_sql() { docker compose exec -T postgres psql -U taskmanager -d taskmanager_db -X "${@:2}" -c "$1"; }
user_id()  { main_sql "SELECT id FROM users WHERE username = '$1'" -tA | tr -d '\r'; }
# Время ответа API и HTTP-код: http_time GET /path [json-тело]
http_time() { curl -s -o /dev/null -m 60 -w '%{http_code} %{time_total}' -X "$1" -H "Authorization: Bearer $TOKEN"                    -H 'Content-Type: application/json' ${3:+-d "$3"} "$API$2"; }
