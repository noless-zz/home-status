# Home status board - serves http://localhost:8090 (config in config.json next to this file)
# Updates itself from git: every 10 minutes it fetches origin/main and restarts when there is a new commit.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgFile = Join-Path $root 'config.json'
if (-not (Test-Path $cfgFile)) { $cfgFile = Join-Path $root 'config.example.json' }
$cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
$port = 8090; if ($cfg.port) { $port = [int]$cfg.port }
$logFile = Join-Path $root 'status.log'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Log($m) {
  try { if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 1MB) { Move-Item $logFile "$logFile.old" -Force } } catch {}
  try { Add-Content $logFile ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) } catch {} }

function Get-Http($url, $timeoutMs) {
  try {
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Timeout = $timeoutMs; $req.ReadWriteTimeout = $timeoutMs
    $resp = $req.GetResponse()
    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $body = $sr.ReadToEnd(); $code = [int]$resp.StatusCode; $resp.Close()
    return @{ ok = $true; code = $code; body = $body }
  } catch [System.Net.WebException] {
    if ($_.Exception.Response) { return @{ ok = $true; code = [int]$_.Exception.Response.StatusCode; body = '' } }
    return @{ ok = $false; code = 0; body = ''; err = $_.Exception.Message }
  } catch { return @{ ok = $false; code = 0; body = ''; err = $_.Exception.Message } }
}

function Get-HA {
  $r = @{ host = $cfg.haHost; core = 'down'; supervisor = 'unreachable'; health = '?'; support = '?' }
  $hosts = @($cfg.haHost, $cfg.haIp) | Where-Object { $_ }
  foreach ($h in $hosts) {
    $o = Get-Http ("http://{0}:4357/" -f $h) 2500
    if ($o.ok -and $o.body) {
      $b = $o.body; $r.host = $h
      $r.supervisor = if ($b -match 'Disconnected') { 'Disconnected' } elseif ($b -match 'Connected') { 'Connected' } else { '?' }
      $r.health = if ($b -match 'Unhealthy') { 'Unhealthy' } elseif ($b -match 'Healthy') { 'Healthy' } else { '?' }
      $r.support = if ($b -match 'Unsupported') { 'Unsupported' } elseif ($b -match 'Supported') { 'Supported' } else { '?' }
      break
    }
  }
  $p = 80; if ($cfg.haPort) { $p = [int]$cfg.haPort }
  $c = Get-Http ("http://{0}:{1}/manifest.json" -f $r.host, $p) 3000
  if ($c.ok -and $c.code -eq 200) { $r.core = 'running' }
  else {
    $l = Get-Http ("http://{0}:{1}/" -f $r.host, $p) 3000
    if ($l.ok -and $l.body -match 'Preparing|landing') { $r.core = 'starting' }
    elseif ($l.ok) { $r.core = 'starting' }
  }
  $r.url = "http://{0}:{1}/" -f $r.host, $p
  return $r
}

function Get-VM {
  $r = @{ running = $false; process = ''; memMB = 0; cpu = 0; started = $null }
  $procs = @(Get-Process -Name VBoxHeadless, VirtualBoxVM -ErrorAction SilentlyContinue)
  if ($procs.Count -gt 0) {
    $r.running = $true
    $r.process = ($procs | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
    $r.memMB = [math]::Round((($procs | Measure-Object WorkingSet64 -Sum).Sum) / 1MB)
    try { $r.started = ($procs | Sort-Object StartTime | Select-Object -First 1).StartTime.ToString('o') } catch {}
    try {
      $perf = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "Name like 'VBoxHeadless%' or Name like 'VirtualBoxVM%'" -ErrorAction Stop
      $r.cpu = [math]::Round((($perf | Measure-Object PercentProcessorTime -Sum).Sum) / [int]$env:NUMBER_OF_PROCESSORS, 1)
    } catch {}
  }
  if ($cfg.vmMemoryMB) { $r.allocMB = [int]$cfg.vmMemoryMB }
  return $r
}

function Get-Autostart {
  $s = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'VBoxAutostart*' -or $_.DisplayName -like '*VirtualBox*utostart*' } | Select-Object -First 1
  if (-not $s) { return @{ installed = $false } }
  return @{ installed = $true; name = $s.DisplayName; status = "$($s.Status)"; startType = "$($s.StartType)" }
}

function Get-HostInfo {
  $r = @{ name = $env:COMPUTERNAME }
  try {
    $os = Get-CimInstance Win32_OperatingSystem
    $r.memTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $r.memUsedGB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
    $r.boot = $os.LastBootUpTime.ToString('o')
  } catch {}
  try { $r.cpu = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average) } catch {}
  try {
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $r.diskFreeGB = [math]::Round($d.FreeSpace / 1GB); $r.diskTotalGB = [math]::Round($d.Size / 1GB)
  } catch {}
  return $r
}

function Get-Tailscale {
  $exe = 'C:\Program Files\Tailscale\tailscale.exe'
  if ($cfg.tailscalePath) { $exe = $cfg.tailscalePath }
  if (-not (Test-Path $exe)) { return @{ installed = $false } }
  try {
    $j = (& $exe status --json 2>$null | Out-String) | ConvertFrom-Json
    $peers = @(); if ($j.Peer) { $peers = @($j.Peer.PSObject.Properties | ForEach-Object { $_.Value }) }
    $ip = ''; if ($j.Self -and $j.Self.TailscaleIPs) { $ip = $j.Self.TailscaleIPs[0] }
    return @{ installed = $true; state = "$($j.BackendState)"; ip = $ip; peers = $peers.Count; peersOnline = @($peers | Where-Object { $_.Online }).Count }
  } catch { return @{ installed = $true; state = 'error'; err = $_.Exception.Message } }
}

function VarInt([int]$v) {
  $out = New-Object System.Collections.Generic.List[byte]
  do { $b = $v -band 0x7F; $v = $v -shr 7; if ($v -ne 0) { $b = $b -bor 0x80 }; $out.Add([byte]$b) } while ($v -ne 0)
  return , $out.ToArray()
}
function ReadVarInt($s) {
  $num = 0; $shift = 0
  while ($true) {
    $b = $s.ReadByte(); if ($b -lt 0) { throw 'eof' }
    $num = $num -bor (($b -band 0x7F) -shl $shift)
    if (($b -band 0x80) -eq 0) { break }
    $shift += 7; if ($shift -gt 28) { throw 'bad varint' }
  }
  return $num
}
function Get-Minecraft($srv) {
  $r = @{ name = $srv.name; host = $srv.host; port = [int]$srv.port; online = $false }
  if (-not $r.port) { $r.port = 25565 }
  $c = New-Object System.Net.Sockets.TcpClient
  try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $ar = $c.BeginConnect($r.host, $r.port, $null, $null)
    if (-not $ar.AsyncWaitHandle.WaitOne(2000)) { throw 'timeout' }
    $c.EndConnect($ar)
    $s = $c.GetStream(); $s.ReadTimeout = 2500
    $hb = [Text.Encoding]::UTF8.GetBytes($r.host)
    $body = New-Object System.Collections.Generic.List[byte]
    $body.AddRange((VarInt 0)); $body.AddRange((VarInt 767)); $body.AddRange((VarInt $hb.Length)); $body.AddRange($hb)
    $body.Add([byte](($r.port -shr 8) -band 0xFF)); $body.Add([byte]($r.port -band 0xFF)); $body.AddRange((VarInt 1))
    $pkt = New-Object System.Collections.Generic.List[byte]
    $pkt.AddRange((VarInt $body.Count)); $pkt.AddRange($body); $pkt.Add(1); $pkt.Add(0)
    $a = $pkt.ToArray(); $s.Write($a, 0, $a.Length)
    [void](ReadVarInt $s); [void](ReadVarInt $s); $len = ReadVarInt $s
    $buf = New-Object byte[] $len; $got = 0
    while ($got -lt $len) { $n = $s.Read($buf, $got, $len - $got); if ($n -le 0) { throw 'eof' }; $got += $n }
    $r.ms = $sw.ElapsedMilliseconds
    $j = [Text.Encoding]::UTF8.GetString($buf) | ConvertFrom-Json
    $r.online = $true; $r.players = [int]$j.players.online; $r.max = [int]$j.players.max; $r.version = "$($j.version.name)"
    if ($j.players.sample) { $r.who = @($j.players.sample | ForEach-Object { $_.name }) }
    $d = $j.description; if ($d -is [string]) { $r.motd = $d } elseif ($d.text) { $r.motd = $d.text }
  } catch { $r.err = "$($_.Exception.Message)" } finally { $c.Close() }
  return $r
}


function Get-Web($w) {
  $r = @{ name = $w.name; url = $w.url; kind = "$($w.kind)"; ok = $false }
  if (-not $w.url) { $r.err = 'not configured'; return $r }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $o = Get-Http $w.url 6000
  $r.ms = $sw.ElapsedMilliseconds; $r.code = $o.code
  if (-not $o.ok) { $r.err = $o.err; return $r }
  if ($w.kind -eq 'jar') {
    try { $j = $o.body | ConvertFrom-Json; $r.ok = [bool]$j.ok; $r.via = "$($j.via)" } catch { $r.err = 'unexpected reply' }
  } else { $r.ok = ($o.code -ge 200 -and $o.code -lt 400) ; if (-not $r.ok) { $r.err = "HTTP $($o.code)" } }
  return $r
}

function Get-Status {
  $web = @(); foreach ($w in @($cfg.web)) { if ($w) { $web += Get-Web $w } }
  $mc = @(); foreach ($srv in @($cfg.minecraft)) { if ($srv -and $srv.host) { $mc += Get-Minecraft $srv } }
  return @{
    time = (Get-Date).ToString('o'); version = $version; ha = Get-HA; vm = Get-VM; autostart = Get-Autostart
    host = Get-HostInfo; tailscale = Get-Tailscale; web = $web; minecraft = $mc
  }
}


# ---- self-update from git ----
function Find-Git {
  $g = Get-Command git -ErrorAction SilentlyContinue
  if ($g) { return $g.Source }
  foreach ($p in 'C:\Program Files\Git\cmd\git.exe', "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe") { if (Test-Path $p) { return $p } }
  return $null
}
$git = Find-Git
function Invoke-Git { & $git -c safe.directory=* -C $root @args 2>&1 }
$version = 'local'
if ($git -and (Test-Path (Join-Path $root '.git'))) { $version = "$(Invoke-Git rev-parse --short HEAD)".Trim() }
function Update-FromGit {
  if (-not $git -or -not (Test-Path (Join-Path $root '.git'))) { return $false }
  try {
    $f = Invoke-Git fetch -q origin main
    if ($LASTEXITCODE -ne 0) { Log "git fetch failed: $f"; return $false }
    $head = "$(Invoke-Git rev-parse HEAD)".Trim(); $remote = "$(Invoke-Git rev-parse origin/main)".Trim()
    if ($head -eq $remote) { return $false }
    $out = Invoke-Git reset -q --hard origin/main
    if ($LASTEXITCODE -ne 0) { Log "git reset failed: $out"; return $false }
    Log "updated $head -> $remote"
    return $true
  } catch { Log "update error: $_"; return $false }
}

$html = Get-Content (Join-Path $root 'index.html') -Raw -Encoding UTF8
$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$port/"; if ($cfg.lan) { $prefix = "http://+:$port/" }
$listener.Prefixes.Add($prefix)
try { $listener.Start() } catch {
  if ($cfg.lan) { $listener = New-Object System.Net.HttpListener; $listener.Prefixes.Add("http://localhost:$port/"); try { $listener.Start() } catch { Log "start failed: $_"; exit 1 } }
  else { Log "start failed (already running?): $_"; exit 1 }
}
Log "listening on $($listener.Prefixes -join ',') (version $version)"
$cache = $null; $cacheAt = [datetime]::MinValue
$nextUpdate = (Get-Date).AddMinutes(1)
while ($listener.IsListening) {
  try {
    $ar = $listener.BeginGetContext($null, $null)
    while (-not $ar.AsyncWaitHandle.WaitOne(1000)) {
      if ((Get-Date) -ge $nextUpdate) {
        $nextUpdate = (Get-Date).AddMinutes(10)
        if (Update-FromGit) {
          Log 'restarting with the new version'
          $listener.Stop()
          Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`""
          exit 0
        }
      }
    }
    $ctx = $listener.EndGetContext($ar)
    $path = $ctx.Request.Url.AbsolutePath
    if ($path -eq '/api') {
      if (((Get-Date) - $cacheAt).TotalSeconds -gt 8) { $cache = (Get-Status | ConvertTo-Json -Depth 6 -Compress); $cacheAt = Get-Date }
      $bytes = [Text.Encoding]::UTF8.GetBytes($cache); $ctx.Response.ContentType = 'application/json; charset=utf-8'
    } elseif ($path -eq '/update') {
      $nextUpdate = Get-Date
      $bytes = [Text.Encoding]::UTF8.GetBytes('{"ok":true,"msg":"checking for updates"}'); $ctx.Response.ContentType = 'application/json'
    } else {
      $bytes = [Text.Encoding]::UTF8.GetBytes($html); $ctx.Response.ContentType = 'text/html; charset=utf-8'
    }
    $ctx.Response.Headers.Add('Cache-Control', 'no-store')
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length); $ctx.Response.Close()
  } catch { Log "request error: $_"; Start-Sleep -Milliseconds 200 }
}
