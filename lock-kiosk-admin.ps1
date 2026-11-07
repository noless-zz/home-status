# Run in an ADMINISTRATOR PowerShell:  powershell -ExecutionPolicy Bypass -File C:\HA\status\lock-kiosk-admin.ps1
# Turns off Task Manager, Lock and Change password for the kiosk account (a limited account can't set these itself).
# -Undo removes them again. Works whether the kiosk account is signed in or not.
param([string]$User = 'status', [switch]$Undo)
$ErrorActionPreference = 'Stop'
$sid = (New-Object Security.Principal.NTAccount($User)).Translate([Security.Principal.SecurityIdentifier]).Value
$admins = (Get-LocalGroupMember -SID 'S-1-5-32-544' | ForEach-Object { $_.SID.Value })
if ($admins -contains $sid) { throw "'$User' is an administrator - refusing to lock it down." }
$loaded = Test-Path "Registry::HKEY_USERS\$sid"
if (-not $loaded) {
  $profileDir = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid").ProfileImagePath
  reg load "HKU\$sid" (Join-Path $profileDir 'NTUSER.DAT') | Out-Null
}
try {
  $k = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Policies\System"
  $names = 'DisableTaskMgr', 'DisableLockWorkstation', 'DisableChangePassword'
  if ($Undo) {
    foreach ($n in $names) { Remove-ItemProperty $k -Name $n -ErrorAction SilentlyContinue }
    "Removed the kiosk restrictions for $User."
  } else {
    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
    foreach ($n in $names) { New-ItemProperty $k -Name $n -Value 1 -PropertyType DWord -Force | Out-Null }
    "Task Manager, Lock and Change password are now off for $User (from its next sign-in)."
  }
} finally {
  if (-not $loaded) { [gc]::Collect(); Start-Sleep 1; reg unload "HKU\$sid" | Out-Null }
}
