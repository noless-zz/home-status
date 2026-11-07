@echo off
rem Run as the kiosk account to give it back the normal Windows desktop.
rem To reach this from the kiosk: as another account create C:\HA\status\kiosk-off, then sign the kiosk account in again.
reg delete "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v Shell /f
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableTaskMgr /f
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableLockWorkstation /f
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableChangePassword /f
copy /Y "C:\HA\status\start-status.bat" "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\start-status.bat" >nul
echo.
echo Normal desktop restored for "%USERNAME%". Delete C:\HA\status\kiosk-off, then sign out and in again.
pause
