# Shell for the kiosk account, used instead of Explorer (no Start menu, taskbar or desktop).
# Keeps the status server and the full-screen board running. Ctrl+Alt+Del still works for Switch user / Sign out.
# Escape hatch: create C:\HA\status\kiosk-off (from another account) and sign the kiosk account in again,
# and it opens a File Explorer window instead, from where uninstall-kiosk.cmd can be run.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$off = Join-Path $root 'kiosk-off'
function Start-Server {
  Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', (Join-Path $root 'status.ps1')
}
function Test-Server {
  $c = New-Object Net.Sockets.TcpClient
  try { $ar = $c.BeginConnect('127.0.0.1', 8090, $null, $null); return ($ar.AsyncWaitHandle.WaitOne(2000) -and $c.Connected) } catch { return $false } finally { $c.Close() }
}
if (Test-Path $off) { Start-Process explorer.exe; exit }
if (-not (Test-Server)) { Start-Server }
Start-Sleep 5
$session = (Get-Process -Id $PID).SessionId
$fails = 0; $tick = 0
while ($true) {
  if (Test-Path $off) { Start-Process explorer.exe; exit }
  $edge = Get-Process msedge -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }
  if (-not $edge) { Start-Process msedge -ArgumentList '--kiosk', 'http://localhost:8090', '--edge-kiosk-type=fullscreen', '--no-first-run' }
  $tick++
  if ($tick % 6 -eq 0) {
    # status.ps1 restarts itself after an update; only step in if it has been gone for ~90 s.
    if (Test-Server) { $fails = 0 } else { $fails++; if ($fails -ge 3) { Start-Server; $fails = 0 } }
  }
  Start-Sleep 5
}
