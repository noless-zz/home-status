@echo off
rem Run once while signed in as the account that should show the status board at sign-in
copy /Y "C:\HA\status\start-status.bat" "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\start-status.bat"
echo.
echo Status board will now open automatically when %USERNAME% signs in.
pause
