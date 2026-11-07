@echo off
rem Run ONCE while signed in as the kiosk account (e.g. "status"), never as an administrator.
rem Replaces Explorer with kiosk-shell.ps1 for this account only and turns off Task Manager and Lock for it.
whoami /groups | find "S-1-5-32-544" >nul
if not errorlevel 1 (
  echo This account is an administrator. Run this as the limited kiosk account instead.
  pause
  exit /b 1
)
echo This makes "%USERNAME%" a kiosk-only account: no Start menu, taskbar, desktop or Task Manager.
echo Ctrl+Alt+Del keeps working for Switch user and Sign out.
choice /m "Continue"
if errorlevel 2 exit /b 1
reg add "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v Shell /t REG_SZ /d "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\HA\status\kiosk-shell.ps1" /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableTaskMgr /t REG_DWORD /d 1 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableLockWorkstation /t REG_DWORD /d 1 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableChangePassword /t REG_DWORD /d 1 /f
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\start-status.bat" 2>nul
echo.
echo Done. Sign out of "%USERNAME%" and sign in again to start the kiosk.
pause
