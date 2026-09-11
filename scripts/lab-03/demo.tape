# ЛР №3: запись терминала (https://github.com/charmbracelet/vhs).
# Сбой ночной задачи партиций: проверка находит пропавшую партицию и отправляет alert в Telegram,
# повторный alert не отправляется, job восстанавливает партицию, приходит recovery.
#
# Запуск из корня репозитория при запущенном docker compose (API на http://localhost:5000):
#   vhs scripts/lab-03/demo.tape
# Нужны vhs, ttyd и ffmpeg (winget install charmbracelet.vhs tsl0922.ttyd Gyan.FFmpeg).

Output docs/lab-03/demo.gif

Set Shell "powershell"
Set FontSize 15
Set Width 1500
Set Height 820
Set Padding 16
Set Theme "Dracula"
Set TypingSpeed 25ms
Set Framerate 20

Hide
Type "[Console]::OutputEncoding = [Text.Encoding]::UTF8; cls"
Enter
Sleep 3s
Show

Type "powershell -ExecutionPolicy Bypass -File scripts/lab-03/demo-alert.ps1 -Phase break -Pause 2"
Enter
Sleep 16s
Screenshot docs/lab-03/demo-1-alert.png
Sleep 2s

Type "cls"
Enter
Sleep 500ms
Type "powershell -ExecutionPolicy Bypass -File scripts/lab-03/demo-alert.ps1 -Phase restore -Pause 2"
Enter
Sleep 14s
Screenshot docs/lab-03/demo-2-recovery.png
Sleep 3s
