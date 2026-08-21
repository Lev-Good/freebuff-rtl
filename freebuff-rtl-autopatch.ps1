<#
 ============================================================================
  Freebuff Desktop — RTL auto-patch keeper
 ============================================================================
  Runs in the background and makes sure the RTL patch survives Freebuff
  updates. Freebuff updates replace the UI files and wipe the patch; this
  keeper detects the replacement within seconds and re-applies it.

  Since v1.4.0 the keeper also keeps the RTL script itself up to date:

    * Every few hours (and once at start) it asks GitHub for the latest
      release of Lev-Good/freebuff-rtl. If a newer version exists it
      downloads the zip, replaces the old script files (deleting leftovers
      of previous versions), re-registers autostart and re-applies the patch
      to the installed Freebuff files - all in the background, no clicks.

    * It watches %TEMP%\freebuff-desktop-pastes\ for the small *.rtlupdate
      marker the in-app "Update & relaunch" button writes. When one arrives
      it forces an update check now, waits for Freebuff to exit and starts
      it again - so the button can close the app, get the new script
      installed and bring the app back, all automatically.

  Modes:
    powershell -File freebuff-rtl-autopatch.ps1             # run keeper (foreground)
    powershell -File freebuff-rtl-autopatch.ps1 -Install    # register autostart + start
    powershell -File freebuff-rtl-autopatch.ps1 -Remove     # unregister autostart
    powershell -File freebuff-rtl-autopatch.ps1 -Once       # apply once, exit
    powershell -File freebuff-rtl-autopatch.ps1 -CheckUpdates  # self-update once, exit

  The autostart entry is registered per-user (HKCU Run key) and runs at every
  logon, hidden, with no admin rights required (the app lives under
  %LOCALAPPDATA%).
 ============================================================================
#>
[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$Remove,
  [switch]$Once,
  [switch]$CheckUpdates,
  [switch]$Watchdog,    # lightweight periodic check that restarts the keeper if it died
  [int]$PollSeconds = 3,
  [string]$UiDir = ''   # optional: watch a specific ui folder (default: auto-detect)
)

$ErrorActionPreference = 'Stop'
# GitHub's API requires TLS 1.2 - force it for older Windows PowerShell.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$scriptSelf = $MyInvocation.MyCommand.Path
$sourceDir  = Split-Path -Parent $scriptSelf
# Keep the background installation in a stable, ASCII-only per-user path.
# Older releases registered the original download folder; when that folder
# contained Hebrew characters, the nested PowerShell call lost the path and
# the keeper could no longer re-apply the patch after a Freebuff update.
$stableDir  = Join-Path $env:LOCALAPPDATA 'freebuff-rtl'
$scriptDir  = $sourceDir

if (-not [string]::Equals(
    ([IO.Path]::GetFullPath($sourceDir)).TrimEnd([char[]]@('\', '/')),
    ([IO.Path]::GetFullPath($stableDir)).TrimEnd([char[]]@('\', '/')),
    [StringComparison]::OrdinalIgnoreCase
  )) {
  try {
    New-Item -ItemType Directory -Path $stableDir -Force | Out-Null
    # Copy the complete flat release payload before registering autostart.
    # This also repairs installations created by v1.5.x in a moved/renamed
    # download folder. File APIs handle Unicode here; only child process
    # command lines need the encoded-command workaround below.
    $releaseFiles = Get-ChildItem -LiteralPath $sourceDir -File -ErrorAction Stop | Where-Object {
      $_.Name -match '^(freebuff-rtl|apply-rtl|remove-rtl|remove-permanent|install-permanent|VERSION|README|פוסט-)'
    }
    foreach ($file in $releaseFiles) {
      Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $stableDir $file.Name) -Force
    }
    $scriptDir = $stableDir
    $scriptSelf = Join-Path $scriptDir 'freebuff-rtl-autopatch.ps1'
  } catch {
    Write-Host "[Freebuff RTL] Could not create the stable installation: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
  }
}

$patchScript = Join-Path $scriptDir 'freebuff-rtl-patch.ps1'
$versionFile = Join-Path $scriptDir 'VERSION'
$taskName   = 'Freebuff RTL Auto-Patch'
# Secondary layer of reliability on top of the HKCU Run key: two scheduled
# tasks. The logon task starts the keeper at every logon; the watchdog task
# runs every few minutes and restarts the keeper if it ever died - so a
# Freebuff update is never missed because the keeper was not alive.
$watchdogTask = 'Freebuff RTL Auto-Patch Watchdog'
$keeperMutex  = 'FreebuffRtlKeeperMutex'
# Heartbeat written by the running keeper (pid + script path + timestamps).
# It lets a newer keeper identify and stop a stale one WITHOUT WMI/CIM,
# which can be broken on some machines ("Invalid class") - the heartbeat
# carries the exact PID, so takeover is a plain Get-Process / Stop-Process.
$keeperHeartbeat = Join-Path $stableDir 'keeper.json'
$psExe        = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$wscriptExe   = "$env:SystemRoot\System32\wscript.exe"
$logDir     = $stableDir
$logFile    = Join-Path $logDir 'autopatch.log'
$updatesDir = Join-Path $logDir 'updates'
$markerDir  = Join-Path $env:TEMP 'freebuff-desktop-pastes'
$ghRepo     = 'Lev-Good/freebuff-rtl'
$ghApiUrl   = "https://api.github.com/repos/$ghRepo/releases/latest"
$ghUserAgent = 'freebuff-rtl-autopatch'

# Update cadence for the background check.
$UpdateCheckIntervalSec = 6 * 60 * 60   # every 6 hours
# A marker older than this is stale (e.g. left by a session that never
# finished closing) and is ignored.
$MarkerMaxAgeSec = 30 * 60
# How long the keeper waits for Freebuff to exit after an update request
# before giving up on the relaunch.
$RestartWaitSec = 90

if (-not (Test-Path -LiteralPath $patchScript)) {
  Write-Host "[Freebuff RTL] Missing $patchScript (must sit next to this script)." -ForegroundColor Red
  exit 1
}

function Write-Log($msg) {
  try {
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    Add-Content -LiteralPath $logFile -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
  } catch {}
}

function Invoke-PatchOnce {
  try {
    # Do not pass a Hebrew download path directly to Windows PowerShell 5.1:
    # its child-process argument conversion can turn it into question marks.
    # -EncodedCommand transports the complete command as UTF-16LE instead.
    $escapedPatch = $patchScript.Replace("'", "''")
    $command = "& '$escapedPatch'"
    if ($UiDir) {
      $escapedCssDir = (Join-Path $UiDir 'assets').Replace("'", "''")
      $command += " -CssDir '$escapedCssDir'"
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)
    $out = & $psExe @args 2>&1 | Out-String
    $ok = $LASTEXITCODE -eq 0
    if ($ok) {
      Write-Log "patch applied: $($out.Trim() -replace '\s+', ' ')"
    } else {
      Write-Log "patch FAILED: $($out.Trim() -replace '\s+', ' ')"
    }
    return $ok
  } catch {
    Write-Log "patch threw: $($_.Exception.Message)"
    return $false
  }
}

# ---- version helpers --------------------------------------------------------

function Compare-Version {
  # Returns 1 when $a is newer than $b, -1 when older, 0 when equal.
  param([string]$a, [string]$b)
  $pa = ($a -replace '^v', '') -split '\.' | ForEach-Object { try { [int]$_ } catch { 0 } }
  $pb = ($b -replace '^v', '') -split '\.' | ForEach-Object { try { [int]$_ } catch { 0 } }
  for ($i = 0; $i -lt [Math]::Max($pa.Count, $pb.Count); $i++) {
    $va = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
    $vb = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
    if ($va -gt $vb) { return 1 }
    if ($va -lt $vb) { return -1 }
  }
  return 0
}

function Get-LocalVersion {
  if (-not (Test-Path -LiteralPath $versionFile)) { return '0.0.0' }
  try { return ([IO.File]::ReadAllText($versionFile)).Trim() } catch { return '0.0.0' }
}

function Get-LatestRelease {
  try {
    $r = Invoke-RestMethod -Uri $ghApiUrl -Headers @{ 'User-Agent' = $ghUserAgent } -TimeoutSec 15
    if ($r -and $r.tag_name) { return @{ Tag = [string]$r.tag_name; Body = [string]$r.body } }
  } catch {
    Write-Log "update check failed: $($_.Exception.Message)"
  }
  return $null
}

# ---- self-update ------------------------------------------------------------

function Invoke-SelfUpdate {
  # Downloads and installs the newest release of this script into $scriptDir,
  # deleting leftover files of older versions, then re-applies the RTL patch.
  # Returns $true when an update was applied, $false otherwise.
  try {
    $latest = Get-LatestRelease
    if (-not $latest) { return $false }
    $local = Get-LocalVersion
    if ((Compare-Version $latest.Tag $local) -le 0) { return $false }

    Write-Log "self-update: newer version $($latest.Tag) found (installed: $local) - downloading"
    $tagNoV = $latest.Tag -replace '^v', ''
    $zipUrl = "https://github.com/$ghRepo/archive/refs/tags/$($latest.Tag).zip"
    $zipPath = Join-Path $updatesDir ($latest.Tag + '.zip')
    $extractDir = Join-Path $updatesDir $tagNoV

    New-Item -ItemType Directory -Path $updatesDir -Force | Out-Null
    if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -Headers @{ 'User-Agent' = $ghUserAgent } -TimeoutSec 120
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    # GitHub source archives unpack to <repo>-<version>/.
    $src = Join-Path $extractDir ("$($ghRepo.Split('/')[1])-$tagNoV")
    if (-not (Test-Path -LiteralPath $src)) {
      $src = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
      Write-Log "self-update FAILED: could not find extracted files in $extractDir"
      return $false
    }

    # Copy the new files over the current script folder.
    $newFiles = Get-ChildItem -LiteralPath $src -File
    foreach ($f in $newFiles) {
      Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $scriptDir $f.Name) -Force
    }
    Write-Log "self-update: copied $($newFiles.Count) file(s) to $scriptDir"

    # Delete leftover files of previous versions that are not part of the
    # release (e.g. the old light-mode files) plus stray zips/temp files.
    $newNames = @($newFiles | ForEach-Object { $_.Name })
    # Anything a previous version of this project shipped (including the old
    # light-mode files) that the new release does not contain is stale.
    Get-ChildItem -LiteralPath $scriptDir -File -ErrorAction SilentlyContinue | Where-Object {
      $_.Name -match '^(freebuff-rtl|freebuff-light|apply-rtl|apply-light|remove-rtl|remove-light|remove-permanent|install-permanent|VERSION|README)' -and
      $_.Name -ne 'freebuff-rtl-hidden.vbs' -and
      $newNames -notcontains $_.Name
    } | ForEach-Object {
      Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
      Write-Log "self-update: removed old file $($_.Name)"
    }
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "self-update: cleaned up download artifacts"

    # The autostart entry points at the same path - keep it registered, then
    # re-apply the patch so the new injected scripts reach the app.
    [void](Register-Task)
    [void](Invoke-PatchOnce)

    try {
      @{ version = $latest.Tag; applied = $true; at = (Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logDir 'update-ready.json') -Encoding UTF8
    } catch {}
    Write-Log "self-update: installed $($latest.Tag)"
    return $true
  } catch {
    Write-Log "self-update threw: $($_.Exception.Message)"
    return $false
  }
}

# ---- app restart (triggered by the in-app update button) --------------------

function Get-FreebuffExe {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\@codebufffreebuff-desktop\Freebuff.exe'),
    (Join-Path $env:ProgramFiles '@codebufffreebuff-desktop\Freebuff.exe'),
    (Join-Path ${env:ProgramFiles(x86)} '@codebufffreebuff-desktop\Freebuff.exe')
  )
  return ($candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

function Test-FreebuffRunning {
  return [bool](Get-Process -Name 'Freebuff' -ErrorAction SilentlyContinue)
}

function Consume-RestartMarkers {
  # The in-app button writes a tiny JSON marker (freebuffRtlRestart=true)
  # through the app's clipboard-image IPC into %TEMP%\freebuff-desktop-pastes\
  # as paste-*.rtlupdate. When one is found the user asked for
  # "update & relaunch": consume it, make sure the update is applied and let
  # the keeper loop relaunch the app once it has exited.
  if (-not (Test-Path -LiteralPath $markerDir)) { return $false }
  $markers = Get-ChildItem -LiteralPath $markerDir -Filter 'paste-*.rtlupdate' -ErrorAction SilentlyContinue
  $found = $false
  foreach ($m in $markers) {
    try {
      $json = $m | Get-Content -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
      if ($json.freebuffRtlRestart -eq $true) {
        $age = ((Get-Date) - $m.LastWriteTime).TotalSeconds
        if ($age -gt $MarkerMaxAgeSec) {
          Write-Log "restart marker is stale ($([int]$age)s) - ignoring"
        } else {
          Write-Log "restart marker received (version $($json.version))"
          $found = $true
        }
      }
    } catch {
      Write-Log "bad restart marker $($m.Name): $($_.Exception.Message)"
    }
    Remove-Item -LiteralPath $m.FullName -Force -ErrorAction SilentlyContinue
  }
  return $found
}

function Start-PendingRelaunch {
  # Once the app has exited after an update request, bring it back.
  $exe = Get-FreebuffExe
  if (-not $exe) {
    Write-Log 'relaunch: Freebuff.exe not found - cannot restart the app'
    return
  }
  Write-Log "relaunch: starting $exe"
  try { Start-Process -FilePath $exe | Out-Null } catch { Write-Log "relaunch failed: $($_.Exception.Message)" }
}

# ---- install / remove -------------------------------------------------------

$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runName = 'Freebuff RTL Auto-Patch'

function Get-ProcessTable {
  # Returns a hashtable { pid -> command line } for all processes, using the
  # first provider that works. WMI/CIM can be broken on some machines
  # ("Invalid class" from both Get-CimInstance and Get-WmiObject), so we
  # fall back through the legacy provider and the deprecated wmic.exe before
  # giving up. Returns $null when nothing works.
  $table = @{}
  try {
    Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object {
      $table[[int]$_.ProcessId] = [string]$_.CommandLine
    }
    if ($table.Count) { return $table }
  } catch {}
  try {
    Get-WmiObject Win32_Process -ErrorAction Stop | ForEach-Object {
      $table[[int]$_.ProcessId] = [string]$_.CommandLine
    }
    if ($table.Count) { return $table }
  } catch {}
  try {
    $wmic = "$env:SystemRoot\System32\wbem\wmic.exe"
    if (Test-Path -LiteralPath $wmic) {
      $csv = & $wmic process get ProcessId,CommandLine /format:csv 2>$null
      foreach ($line in $csv) {
        # CSV format: <Node>,<CommandLine>,<ProcessId> - a command line can
        # itself contain commas, so split into at most 3 parts.
        $parts = $line -split ',', 3
        if ($parts.Count -eq 3 -and $parts[2].Trim() -match '^\d+$') {
          $table[[int]$parts[2].Trim()] = $parts[1].Trim()
        }
      }
      if ($table.Count) { return $table }
    }
  } catch {}
  return $null
}

function Get-KeeperProcesses {
  # Lists running processes that run THIS keeper script (freebuff-rtl-
  # autopatch.ps1) from a path that is not the canonical stable copy.
  # Returns @( [pscustomobject]@{ Id = ...; CommandLine = ... } ).
  $table = Get-ProcessTable
  if (-not $table) { return @() }
  $result = @()
  $stablePattern = [regex]::Escape($scriptSelf)
  foreach ($entry in $table.GetEnumerator()) {
    $cmd = [string]$entry.Value
    if ($cmd -match 'freebuff-rtl-autopatch\.ps1' -and $cmd -notmatch $stablePattern) {
      $result += [pscustomobject]@{ Id = [int]$entry.Key; CommandLine = $cmd }
    }
  }
  return $result
}

function Test-AcquireMutex {
  # Waits on a named mutex and reports ownership. Special case: when the
  # previous owner DIED without releasing (which is exactly what happens
  # after we stop a stale keeper), .NET throws AbandonedMutexException on
  # the WaitOne that grants us ownership - that is a SUCCESS, not a failure.
  param($Mutex)
  try {
    return $Mutex.WaitOne(0)
  } catch [System.Threading.AbandonedMutexException] {
    return $true
  } catch {
    return $false
  }
}

function Write-Heartbeat {
  # Records who we are so a newer keeper (or the watchdog) can take over if
  # we ever go stale - e.g. when the folder we were started from was moved
  # or deleted, which makes our patch path invalid while we still hold the
  # mutex and silently block the canonical keeper.
  try {
    @{
      pid        = $PID
      scriptPath = $scriptSelf
      startUtc   = (Get-Date).ToUniversalTime().ToString('o')
      beatUtc    = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $keeperHeartbeat -Encoding UTF8
  } catch {}
}

function Stop-LegacyKeepers {
  # A keeper from an older version (or from a folder that was later moved or
  # renamed) can keep running forever and hold the shared mutex, blocking the
  # canonical keeper and leaving the RTL patch un-applied after a Freebuff
  # update. This stops exactly those processes and nothing else:
  #
  #   1. Heartbeat first - the canonical keeper records its PID, so takeover
  #      needs no process enumeration at all (works even with broken WMI).
  #   2. Command-line scan as fallback - catches keepers too old to write a
  #      heartbeat, using the first working provider (CIM -> WMI -> wmic).
  #
  # Returns $true when at least one stale keeper was stopped.
  $stopped = @()

  if (Test-Path -LiteralPath $keeperHeartbeat) {
    try {
      $hb = Get-Content -LiteralPath $keeperHeartbeat -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
      if ($hb.pid -and [int]$hb.pid -ne $PID) {
        $hbProc = Get-Process -Id ([int]$hb.pid) -ErrorAction SilentlyContinue
        $canonical = $scriptSelf -and $hb.scriptPath -and ([string]$hb.scriptPath -match [regex]::Escape($scriptSelf))
        if ($hbProc -and -not $canonical) {
          Stop-Process -Id ([int]$hb.pid) -Force -ErrorAction SilentlyContinue
          $stopped += [int]$hb.pid
          Write-Log "takeover: stopped stale keeper pid $($hb.pid) (path $($hb.scriptPath))"
        }
      }
    } catch {
      Write-Log "takeover: could not read heartbeat: $($_.Exception.Message)"
    }
  }

  foreach ($p in (Get-KeeperProcesses)) {
    try {
      Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
      $stopped += $p.Id
      Write-Log "takeover: stopped legacy keeper pid $($p.Id)"
    } catch {}
  }

  return ($stopped.Count -gt 0)
}

function Get-HiddenLauncherPath {
  # wscript.exe is a GUI-subsystem application, so a scheduled task / Run key
  # entry that launches it can never create a console window. The generated
  # .vbs re-launches PowerShell with a hidden window (style 0). This kills the
  # brief console flash that Task Scheduler otherwise produces on every
  # trigger - even with -WindowStyle Hidden on the powershell.exe command line
  # the console window can appear for a moment before being hidden, which is
  # exactly the periodic flash users saw from the watchdog task.
  $vbs = Join-Path $scriptDir 'freebuff-rtl-hidden.vbs'
  # Rewrite only when missing or pointing at a different script path (e.g.
  # after the folder was moved): keeps this cheap on every watchdog run.
  $needsWrite = $true
  if (Test-Path -LiteralPath $vbs) {
    try {
      $existing = [IO.File]::ReadAllText($vbs)
      $needsWrite = $existing -notmatch [regex]::Escape($scriptSelf)
    } catch { $needsWrite = $true }
  }
  if ($needsWrite) {
    # Chr(34) = double quote, added at runtime - avoids VBS string-escaping
    # pitfalls when the paths contain non-ASCII characters. The inner
    # powershell is launched with window style 0 (hidden) and -WindowStyle
    # Hidden.
    $psQuoted = '"' + $psExe + '"'
    $sfQuoted = '"' + $scriptSelf + '"'
    $content = @"
' Freebuff RTL hidden launcher - generated by freebuff-rtl-autopatch.ps1.
' wscript.exe is a GUI app, so nothing pointing here can flash a console.
Set sh = CreateObject("WScript.Shell")
q = Chr(34)
extra = ""
If WScript.Arguments.Count > 0 Then extra = " " & WScript.Arguments(0)
cmd = q & $psQuoted & q & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & q & $sfQuoted & q & extra
sh.Run cmd, 0, False
"@
    # UTF-16 LE + BOM so wscript.exe parses non-ASCII (Hebrew) paths correctly.
    [IO.File]::WriteAllText($vbs, $content, (New-Object System.Text.UnicodeEncoding($false, $true)))
  }
  return $vbs
}

function Get-LaunchValue {
  # The Run key launches powershell directly (-WindowStyle Hidden): explorer
  # honors the hidden window style reliably, and this keeps the bootstrap
  # independent of the generated .vbs file, so the keeper always comes back
  # even if the launcher file was ever lost.
  return ('"' + $psExe + '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $scriptSelf + '"')
}

# ---- scheduled-task helpers (used by Register-Task / the watchdog) -----------
# Uses the Task Scheduler COM API directly (Schedule.Service). The schtasks.exe
# CLI chokes on non-ASCII install paths and the CIM cmdlets are unavailable in
# some environments, but COM passes plain Unicode strings and works everywhere.
# No admin rights needed: tasks are registered for the current user with an
# interactive logon token.

function New-TaskScheduler {
  $ts = New-Object -ComObject Schedule.Service
  $ts.Connect()
  return $ts
}

function Test-TaskExists {
  param([string]$Name)
  try {
    $ts = New-TaskScheduler
    $root = $ts.GetFolder('\')
    $task = $root.GetTask($Name)
    return ($null -ne $task)
  } catch {
    return $false
  }
}

function Set-TaskCommon {
  # Shared settings for both tasks: hidden, survive reboots, no duplicate
  # instances, and (for the keeper) auto-restart shortly after a crash.
  param($Task, [string]$Description, [bool]$RestartOnFailure, [string]$ExecTimeLimit)
  $Task.RegistrationInfo.Description = $Description
  $Task.Settings.StartWhenAvailable = $true
  $Task.Settings.Enabled = $true
  $Task.Settings.MultipleInstances = 1   # TASK_INSTANCES_IGNORE_NEW
  $Task.Settings.ExecutionTimeLimit = $ExecTimeLimit
  $Task.Settings.DisallowStartIfOnBatteries = $false
  $Task.Settings.StopIfGoingOnBatteries = $false
  $Task.Settings.Hidden = $false
  if ($RestartOnFailure) {
    $Task.Settings.RestartCount = 9999
    $Task.Settings.RestartInterval = 'PT1M'  # retry 1 minute after a crash
  }
}

function Register-KeeperTask {
  # Logon task: starts the keeper at every Windows logon. Restart-on-failure
  # brings it back within a minute if it ever crashes.
  try {
    $ts = New-TaskScheduler
    $root = $ts.GetFolder('\')
    $task = $ts.NewTask(0)
    Set-TaskCommon $task 'Freebuff RTL keeper - re-applies the RTL patch after every Freebuff update.' $true 'PT0S'
    $trigger = $task.Triggers.Create(9)   # TASK_TRIGGER_LOGON
    # A per-user logon trigger (UserId set) needs no admin rights; an
    # all-users trigger would require elevation.
    $trigger.UserId = $env:USERNAME
    $action = $task.Actions.Create(0)     # TASK_ACTION_EXEC
    $action.Path = $wscriptExe
    $action.Arguments = '"' + (Get-HiddenLauncherPath) + '"'
    $root.RegisterTaskDefinition($taskName, $task, 6, $null, $null, 3, $null) | Out-Null
    return $true
  } catch {
    Write-Log "keeper task registration failed: $($_.Exception.Message)"
    return $false
  }
}

function Register-WatchdogTask {
  # Runs every few minutes. The -Watchdog mode checks whether the keeper is
  # still alive and restarts it if not - so even a keeper that dies in a way
  # restart-on-failure does not catch comes back on its own.
  try {
    $ts = New-TaskScheduler
    $root = $ts.GetFolder('\')
    $task = $ts.NewTask(0)
    Set-TaskCommon $task 'Freebuff RTL keeper watchdog - restarts the keeper if it died.' $false 'PT2M'
    $trigger = $task.Triggers.Create(1)   # TASK_TRIGGER_TIME (once, with repetition)
    # Start 30s in the future (not 'now'): a boundary that is already in the
    # past can be skipped by Task Scheduler even with StartWhenAvailable, and
    # a logon trigger does not fire for an already-logged-on session - so this
    # time trigger is the pattern that actually fires (verified empirically).
    $trigger.StartBoundary = (Get-Date).AddSeconds(30).ToString('yyyy-MM-ddTHH:mm:ss')
    $trigger.Repetition.Interval = 'PT5M' # every 5 minutes; no Duration = repeat indefinitely
    $action = $task.Actions.Create(0)
    $action.Path = $wscriptExe
    $action.Arguments = '"' + (Get-HiddenLauncherPath) + '" -Watchdog'
    $root.RegisterTaskDefinition($watchdogTask, $task, 6, $null, $null, 3, $null) | Out-Null
    return $true
  } catch {
    Write-Log "watchdog task registration failed: $($_.Exception.Message)"
    return $false
  }
}

function Remove-TaskByName {
  param([string]$Name)
  try {
    $ts = New-TaskScheduler
    $root = $ts.GetFolder('\')
    $root.DeleteTask($Name, 0)
  } catch {}
}

function Ensure-KeeperTask {
  # The watchdog calls this first: if the logon task was deleted/disabled by
  # anything, re-create it so the keeper can come back.
  if (-not (Test-TaskExists $taskName)) {
    [void](Register-KeeperTask)
  }
}

function Start-KeeperTask {
  # Launches the keeper through its scheduled task (not as a child of this
  # process, which Task Scheduler would kill when the action exits).
  try {
    $ts = New-TaskScheduler
    $root = $ts.GetFolder('\')
    $root.GetTask($taskName).Run($null) | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Register-Task {
  # Registers all three layers: the HKCU Run key, the logon scheduled task and
  # the watchdog scheduled task. The watchdog is what makes this survive - if
  # the keeper ever dies, Windows restarts it within a few minutes on its own.
  $okRunKey = $false
  try {
    Set-ItemProperty -Path $runKey -Name $runName -Value (Get-LaunchValue) -Force
    $okRunKey = $true
  } catch {
    $okRunKey = $false
  }
  $okTasks = (Register-KeeperTask) -and (Register-WatchdogTask)
  return ($okRunKey -and $okTasks)
}

function Unregister-Task {
  try {
    Remove-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue
  } catch {}
  Remove-TaskByName $taskName
  Remove-TaskByName $watchdogTask
  Remove-Item -LiteralPath $keeperHeartbeat -Force -ErrorAction SilentlyContinue
  return $true
}

if ($Install) {
  Stop-LegacyKeepers
  if (Register-Task) {
    Write-Host "[Freebuff RTL] Autostart entry '$taskName' registered - it will run at every logon." -ForegroundColor Green
  } else {
    Write-Host '[Freebuff RTL] Failed to register the autostart entry.' -ForegroundColor Red
    exit 1
  }
  Write-Host '[Freebuff RTL] Applying the patch now...'
  [void](Invoke-PatchOnce)
  Write-Host '[Freebuff RTL] Checking for a newer version of the script...'
  if (Invoke-SelfUpdate) {
    Write-Host "[Freebuff RTL] Updated to the latest version - the patch was re-applied." -ForegroundColor Green
  } else {
    Write-Host '[Freebuff RTL] Already running the latest version.' -ForegroundColor Green
  }
  Write-Host '[Freebuff RTL] Done. The patch will now survive Freebuff updates automatically.' -ForegroundColor Green
  exit 0
}

if ($Remove) {
  if (Unregister-Task) {
    Write-Host "[Freebuff RTL] Autostart entry '$taskName' removed." -ForegroundColor Green
  } else {
    Write-Host '[Freebuff RTL] Failed to remove the autostart entry.' -ForegroundColor Red
    exit 1
  }
  # Cancel any pending "update & relaunch" request so the app is not
  # unexpectedly restarted later.
  if (Test-Path -LiteralPath $markerDir) {
    Get-ChildItem -LiteralPath $markerDir -Filter 'paste-*.rtlupdate' -ErrorAction SilentlyContinue |
      Remove-Item -Force -ErrorAction SilentlyContinue
  }
  Write-Host '[Freebuff RTL] The RTL patch itself is untouched - run remove-rtl.bat to uninstall it too.'
  exit 0
}

if ($Once) {
  [void](Invoke-PatchOnce)
  exit 0
}

if ($CheckUpdates) {
  if (Invoke-SelfUpdate) {
    Write-Host "[Freebuff RTL] Updated to the latest version." -ForegroundColor Green
  } else {
    Write-Host '[Freebuff RTL] Already running the latest version.' -ForegroundColor Green
  }
  exit 0
}

# ---- watchdog mode ----------------------------------------------------------
# Run by the 'Freebuff RTL Auto-Patch Watchdog' scheduled task every few
# minutes. Cheap: checks whether a keeper is already alive (via a named
# mutex, which the OS releases automatically when the keeper process dies)
# and, if not, starts the keeper task. Exits immediately.
if ($Watchdog) {
  # Make sure the hidden launcher exists before any launch attempt.
  [void](Get-HiddenLauncherPath)
  # If the mutex is held by a STALE keeper (old version / moved folder), stop
  # it here so the canonical keeper can start on this cycle. Harmless when the
  # running keeper is healthy - the heartbeat scan only touches non-canonical
  # processes.
  [void](Stop-LegacyKeepers)
  $lock = $null
  $held = $false
  try {
    $lock = New-Object System.Threading.Mutex($false, $keeperMutex)
    $held = Test-AcquireMutex $lock
  } catch {
    $held = $false
  }
  if ($held) {
    try { $lock.ReleaseMutex() | Out-Null } catch {}
    # No keeper running - make sure the logon task exists, then launch it.
    Ensure-KeeperTask
    if (-not (Start-KeeperTask)) {
      # Task layer unavailable (task deleted/locked) - start the keeper
      # directly so the patch protection is never lost.
      Write-Log 'watchdog: task start failed - starting keeper directly'
      try {
        Start-Process -FilePath $wscriptExe -ArgumentList ('"' + (Get-HiddenLauncherPath) + '"') | Out-Null
      } catch {
        Write-Log "watchdog: direct start failed: $($_.Exception.Message)"
      }
    }
  }
  exit 0
}

# ---- keeper loop ------------------------------------------------------------

# Only one keeper may run (the Run key, the logon task and the watchdog can
# all try to start it). A named mutex makes the extra launches exit silently.
$keeperLock = $null
$keeperLocked = $false
try {
  $keeperLock = New-Object System.Threading.Mutex($false, $keeperMutex)
  $keeperLocked = Test-AcquireMutex $keeperLock
} catch {
  $keeperLocked = $false
}
if (-not $keeperLocked) {
  # Another keeper holds the mutex. If it is a stale copy from an older
  # version or from a folder that was moved/deleted, stop it and try once
  # more; if it is the canonical copy, a healthy keeper is already running
  # and we exit. This is what prevents the "button disappeared after an
  # update" failure mode: a stale keeper with a dead patch path can no
  # longer block the canonical one forever.
  if (Stop-LegacyKeepers) {
    Start-Sleep -Seconds 2
    $keeperLocked = Test-AcquireMutex $keeperLock
  }
  if (-not $keeperLocked) {
    Write-Log 'keeper: another keeper instance is already running - exiting'
    exit 0
  }
}

# Keep the hidden launcher in place so the watchdog task keeps working even
# if something removed the .vbs while we were not running.
[void](Get-HiddenLauncherPath)

Write-Host "[Freebuff RTL] Keeper started - watching for Freebuff updates (poll every ${PollSeconds}s)." -ForegroundColor Green
Write-Log "keeper started (pid $PID, script $scriptSelf)"
Write-Heartbeat

$lastHtmlMtime = $null
$lastCssMtime  = $null
$lastUpdateCheck = 0
$pendingRestart = $false
$pendingRestartAt = $null
$loopCount = 0

function Get-InstallPaths {
  # Returns the ui dir + current css file, or $null.
  $uiDir = $UiDir
  if (-not $uiDir) {
    $candidates = @(
      (Join-Path $env:LOCALAPPDATA 'Programs\@codebufffreebuff-desktop\resources\orchestrator\ui'),
      (Join-Path $env:ProgramFiles '@codebufffreebuff-desktop\resources\orchestrator\ui'),
      (Join-Path ${env:ProgramFiles(x86)} '@codebufffreebuff-desktop\resources\orchestrator\ui')
    )
    $uiDir = $candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'index.html') } | Select-Object -First 1
  }
  if (-not $uiDir -or -not (Test-Path -LiteralPath (Join-Path $uiDir 'index.html'))) { return $null }
  $htmlFile = Join-Path $uiDir 'index.html'
  $assetsDir = Join-Path $uiDir 'assets'
  $cssFile = $null
  $htmlText = [IO.File]::ReadAllText($htmlFile)
  # Keep watching the stylesheet actually linked by the hashed Vite build;
  # the filename changes after every Freebuff update.
  $m = [regex]::Match($htmlText, '(?i)href\s*=\s*["'']([^"'']*index-[^"'']*\.css)["'']')
  if (-not $m.Success) {
    $m = [regex]::Match($htmlText, '(?i)href\s*=\s*["'']([^"'']*\.css)["'']')
  }
  if ($m.Success) {
    $ref = $m.Groups[1].Value.TrimStart('./').Replace('/', '\')
    $candidate = Join-Path $assetsDir $ref
    if (Test-Path -LiteralPath $candidate) { $cssFile = $candidate }
  }
  if (-not $cssFile) {
    $cssFile = Get-ChildItem -LiteralPath $assetsDir -Filter '*.css' -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notlike '*.bak' } |
      Sort-Object LastWriteTimeUtc -Descending |
      Select-Object -First 1 -ExpandProperty FullName
  }
  return @{ Html = $htmlFile; Css = $cssFile }
}

while ($true) {
  Write-Heartbeat
  try {
    $paths = Get-InstallPaths
    if ($paths) {
      $htmlMtime = (Get-Item -LiteralPath $paths.Html -ErrorAction SilentlyContinue).LastWriteTimeUtc.Ticks
      $cssMtime  = if ($paths.Css) { (Get-Item -LiteralPath $paths.Css -ErrorAction SilentlyContinue).LastWriteTimeUtc.Ticks } else { $null }

      $changed = ($lastHtmlMtime -ne $null -and $htmlMtime -ne $lastHtmlMtime) -or
                 ($lastCssMtime -ne $null -and $cssMtime -ne $lastCssMtime)
      # Also re-verify the markers on a slow cadence even when no mtime changed:
      # a patch that failed mid-update (transient lock, app mid-install) would
      # otherwise stay broken until the next Freebuff update touched the files.
      $loopCount++
      $recheck = ($loopCount % 10) -eq 0

      if ($changed -or $lastHtmlMtime -eq $null -or $recheck) {
        $lastHtmlMtime = $htmlMtime
        $lastCssMtime  = $cssMtime
        # File touched — could be an update OR our own patch. Re-check markers.
        $htmlText = [IO.File]::ReadAllText($paths.Html)
        $cssText  = if ($paths.Css) { [IO.File]::ReadAllText($paths.Css) } else { '' }
        # Versioned markers: if an older injected copy survived (the engine
        # only replaces when content differs), the version check fails and the
        # patch re-runs, upgrading the stale script in place.
        $rtlOk   = $htmlText -match 'freebuff-rtl-dragfix v1' -and
                   $htmlText -match 'freebuff-rtl-dir v2' -and
                   $htmlText -match 'freebuff-rtl-updater v1' -and
                   $htmlText -match 'dir="rtl"' -and
                   $cssText -match '/\* ==== freebuff-rtl ==== \*/'
        # Light/dark mode is built into Freebuff now - if a previous version
        # of the script left its toggle behind, strip it (applying the patch
        # removes light artifacts as part of the job).
        $lightLeft = $htmlText -match 'freebuff-light' -or
                     $cssText -match '/\* ==== freebuff-light ==== \*/'
        if (-not $rtlOk) {
          Write-Log 'RTL patch missing or stale - re-applying'
          [void](Invoke-PatchOnce)
        }
        if ($lightLeft) {
          Write-Log 'legacy light-mode toggle detected - removing it (built into Freebuff now)'
          [void](Invoke-PatchOnce)
        }
      }
    }

    # --- background self-update check (once at start, then every 6h) ---------
    $nowSec = [int][double]::Parse((Get-Date -UFormat %s))
    if ($nowSec - $lastUpdateCheck -ge $UpdateCheckIntervalSec) {
      $lastUpdateCheck = $nowSec
      [void](Invoke-SelfUpdate)
    }

    # --- update & relaunch handshake from the in-app button -------------------
    if (Consume-RestartMarkers) {
      $pendingRestart = $true
      $pendingRestartAt = Get-Date
      # Make sure the newest version is installed before the app comes back.
      [void](Invoke-SelfUpdate)
    }

    if ($pendingRestart) {
      if (-not (Test-FreebuffRunning)) {
        Start-PendingRelaunch
        $pendingRestart = $false
        $pendingRestartAt = $null
      } elseif ($pendingRestartAt -and ((Get-Date) - $pendingRestartAt).TotalSeconds -gt $RestartWaitSec) {
        Write-Log 'relaunch: app did not exit in time - skipping'
        $pendingRestart = $false
        $pendingRestartAt = $null
      }
    }
  } catch {
    Write-Log "keeper error: $($_.Exception.Message)"
  }
  Start-Sleep -Seconds $PollSeconds
}
