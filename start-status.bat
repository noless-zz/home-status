@echo off
rem Home status board: start the status service (if not already running) and show it full screen
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\HA\status\status.ps1"
timeout /t 5 /nobreak >nul
start "" msedge --kiosk http://localhost:8090 --edge-kiosk-type=fullscreen --no-first-run
