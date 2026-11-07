@echo off
rem Shut Home Assistant down cleanly, then restart Windows. Use this instead of Start > Restart.
set VBM="C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
set VM="Home Assistant"
echo Shutting down Home Assistant...
%VBM% controlvm %VM% acpipowerbutton
for /L %%i in (1,1,60) do (
  %VBM% showvminfo %VM% --machinereadable | findstr /C:"VMState=\"poweroff\"" >nul && goto done
  timeout /t 2 /nobreak >nul
)
echo Still running after 2 minutes - saving its state instead.
%VBM% controlvm %VM% savestate
:done
echo Restarting Windows...
shutdown /r /t 5
