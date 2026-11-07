# home-status

A full-screen status board for the Windows PC that runs Home Assistant in a VirtualBox VM.
It shows Home Assistant (core / Supervisor / health), the VM's memory and CPU, the VirtualBox
autostart service, the PC itself, web endpoints reached through Tailscale Funnel, and Minecraft servers.

Plain PowerShell 5.1 + one HTML page. No installs besides Git.

## Files

| File | What it does |
|---|---|
| `status.ps1` | Small web server on `http://localhost:8090` (page + `/api` JSON). Updates itself from Git. |
| `index.html` | The board. Polls `/api` every 10 s and reloads itself when a new version is deployed. |
| `config.example.json` | Template. Copy to `config.json` (kept out of Git) and fill in your addresses. |
| `start-status.bat` | Starts the server and opens the board in Edge kiosk mode. |
| `install-for-this-user.bat` | Run once as the board's account: adds `start-status.bat` to its Startup folder. |
| `kiosk-shell.ps1` | Optional locked-down shell for the kiosk account (replaces Explorer). |
| `install-kiosk.cmd` / `uninstall-kiosk.cmd` | Turn that shell on/off for the account that runs them. |
| `safe-restart.bat` | Shuts the HA VM down cleanly, then restarts Windows. |

## Install (once)

```powershell
winget install --id Git.Git -e
git clone https://github.com/noless-zz/home-status.git C:\HA\status
copy C:\HA\status\config.example.json C:\HA\status\config.json   # then edit it
```

Then, signed in as the board's account, run `C:\HA\status\install-for-this-user.bat`.

## Deploying changes

Push to `main`. The PC fetches `origin/main` every 10 minutes; on a new commit it resets to it,
restarts `status.ps1`, and the open page reloads itself. Open `http://localhost:8090/update`
on the PC to check right away. The running version is shown at the bottom left of the board
and logged in `status.log`.

Local edits to tracked files are overwritten by an update — put local settings in `config.json`.

## config.json

Edits are picked up within about 10 seconds, no restart needed (except `port` and `lan`).
A JSON mistake keeps the previous settings and is logged in `status.log`.


- `haHost`, `haIp`, `haPort`: where Home Assistant answers (the Observer is checked on port 4357).
- `web`: list of `{name, kind, url}`. `kind: "jar"` expects a Jar `/v1/health` reply; anything else
  is OK on HTTP 2xx/3xx.
- `minecraft`: list of `{name, host, port}` (Java edition status ping).
- `lan`: `true` to serve the board on the home network too. Needs, once, in an admin PowerShell:
  `netsh http add urlacl url=http://+:8090/ user=Everyone` and a firewall rule for TCP 8090.
- `background`: `"spotlight"` (default) shows a Windows Spotlight photo, a new one every hour
  (saved in `bg\`, the newest 48 kept, reused when offline); `"none"` turns it off.
  `http://localhost:8090/next-bg` skips to the next photo.
- `vmMemoryMB`: optional, the RAM given to the VM, shown next to its usage.

Keep hostnames and other private details in `config.json` only; this repository is public.

## Locked-down kiosk (optional)

Signed in as the kiosk account, run `C:\HA\status\install-kiosk.cmd`. Then, in an administrator PowerShell,
run `powershell -ExecutionPolicy Bypass -File C:\HA\status\lock-kiosk-admin.ps1` (turns off Task Manager and
Lock for that account; a limited account can't set those itself). Sign the kiosk account out and in.
Explorer is replaced by `kiosk-shell.ps1`: no Start menu, taskbar, desktop or Task Manager, and the
board (and its server) are restarted if closed. Ctrl+Alt+Del still offers Switch user and Sign out.

To undo: from another account create `C:\HA\status\kiosk-off`, sign the kiosk account in (a File
Explorer window opens instead of the board), run `uninstall-kiosk.cmd` (and `lock-kiosk-admin.ps1 -Undo` as admin), delete `kiosk-off`, sign out and in.
