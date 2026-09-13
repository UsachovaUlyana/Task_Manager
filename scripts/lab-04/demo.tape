# ЛР №4: запись терминала (https://github.com/charmbracelet/vhs).
# Primary и Replica: роли, streaming replication, запрет записи на Replica
# и момент, когда Replica отстала от Primary (replication lag).
#
# Запуск из корня репозитория при запущенном docker compose:
#   vhs scripts/lab-04/demo.tape
# Нужны vhs, ttyd и ffmpeg (winget install charmbracelet.vhs tsl0922.ttyd Gyan.FFmpeg).

Output docs/lab-04/demo.gif

Set Shell "powershell"
Set FontSize 15
Set Width 1500
Set Height 860
Set Padding 16
Set Theme "Dracula"
Set TypingSpeed 25ms
Set Framerate 20

Hide
Type "[Console]::OutputEncoding = [Text.Encoding]::UTF8; cls"
Enter
Sleep 3s
Show

Type "powershell -ExecutionPolicy Bypass -File scripts/lab-04/demo-replication.ps1 -Phase basics -Pause 2"
Enter
Sleep 22s
Screenshot docs/lab-04/demo-1-replication.png
Sleep 2s

Type "cls"
Enter
Sleep 500ms
Type "powershell -ExecutionPolicy Bypass -File scripts/lab-04/demo-replication.ps1 -Phase lag -Pause 2"
Enter
Sleep 24s
Screenshot docs/lab-04/demo-2-lag.png
Sleep 3s
