# ЛР №5: запись терминала (https://github.com/charmbracelet/vhs).
# Шардирование задач по user_id: три PostgreSQL, router и сравнение hash % N с consistent hashing.
#
# Запуск из корня репозитория при запущенном docker compose и загруженных шардах:
#   vhs scripts/lab-05/demo.tape

Output docs/lab-05/demo.gif

Set Shell "powershell"
Set FontSize 16
Set Width 1400
Set Height 760
Set Padding 16
Set Theme "Dracula"
Set TypingSpeed 25ms
Set Framerate 20

Hide
Type "[Console]::OutputEncoding = [Text.Encoding]::UTF8; cls"
Enter
Sleep 3s
Show

Type "powershell -ExecutionPolicy Bypass -File scripts/lab-05/demo-sharding.ps1 -Pause 3"
Enter
Sleep 26s
Screenshot docs/lab-05/demo-sharding.png
Sleep 3s
