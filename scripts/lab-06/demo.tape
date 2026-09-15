# ЛР №6: запись терминала (https://github.com/charmbracelet/vhs).
# Запросы после шардирования: агрегация и ORDER BY + LIMIT по всем шардам, отказ одного шарда.
#
# Запуск из корня репозитория при запущенном docker compose и загруженных шардах:
#   vhs scripts/lab-06/demo.tape

Output docs/lab-06/demo.gif

Set Shell "powershell"
Set FontSize 16
Set Width 1300
Set Height 800
Set Padding 16
Set Theme "Dracula"
Set TypingSpeed 25ms
Set Framerate 20

Hide
Type "[Console]::OutputEncoding = [Text.Encoding]::UTF8; cls"
Enter
Sleep 3s
Show

Type "powershell -ExecutionPolicy Bypass -File scripts/lab-06/demo-distributed.ps1 -Pause 3"
Enter
Sleep 50s
Screenshot docs/lab-06/demo-distributed.png
Sleep 3s
