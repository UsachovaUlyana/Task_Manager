# ЛР №2: запись терминала (https://github.com/charmbracelet/vhs).
# Живой psql на таблице lab02.events из 10 млн строк: поиск без индекса, построение индекса,
# тот же поиск с индексом и агрегация за год, которую индекс не ускоряет.
#
# Запуск из корня репозитория после bash scripts/lab-02/run-part-a.sh:
#   vhs scripts/lab-02/demo.tape
# Нужны vhs, ttyd и ffmpeg (winget install charmbracelet.vhs tsl0922.ttyd Gyan.FFmpeg).

Output docs/lab-02/demo.gif

Set Shell "powershell"
Set FontSize 15
Set Width 1500
Set Height 860
Set Padding 16
Set Theme "Dracula"
Set TypingSpeed 30ms
Set Framerate 20

Hide
Type "docker compose exec postgres psql -U taskmanager -d taskmanager_db -P pager=off"
Enter
Sleep 5s
Ctrl+L
Show

Type `\timing on`
Enter
Sleep 500ms
Type "SELECT count(*) FROM lab02.events;"
Enter
Sleep 2s

Type "EXPLAIN ANALYZE SELECT * FROM lab02.events WHERE user_id = 123;"
Enter
Sleep 4s
Screenshot docs/lab-02/demo-1-seq-scan.png
Sleep 1s

Ctrl+L
Type "CREATE INDEX idx_events_user_id ON lab02.events (user_id);"
Enter
Sleep 8s
Type "EXPLAIN ANALYZE SELECT * FROM lab02.events WHERE user_id = 123;"
Enter
Sleep 3s
Screenshot docs/lab-02/demo-2-index-scan.png
Sleep 1s

Ctrl+L
Type "EXPLAIN ANALYZE SELECT DATE(created_at), COUNT(*) FROM lab02.events WHERE created_at >= NOW() - INTERVAL '365 days' GROUP BY 1;"
Enter
Sleep 6s
Screenshot docs/lab-02/demo-3-aggregate.png
Sleep 3s

Hide
Type "DROP INDEX lab02.idx_events_user_id;"
Enter
Sleep 1s
Type `\q`
Enter
Sleep 1s
