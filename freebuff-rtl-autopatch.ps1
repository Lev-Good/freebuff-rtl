<#
 ============================================================================
  Freebuff Desktop — RTL auto-patch keeper
 ============================================================================
  Runs in the background and makes sure the RTL patch survives Freebuff
  updates. Freebuff updates replace the UI files and wipe the patch; this
  keeper detects the replacement within seconds and re-applies it.

  How it works:
    * Polls the installed index.html / stylesheet for the RTL markers every
      3 seconds (cheap mtime comparison, no heavy I/O).
    * If the markers are missing (fresh update), runs freebuff-rtl-patch.ps1
      to re-apply CSS + dir="rtl" + drag shim.
    * Also re-applies once on start, in case it was launched manually.

  Modes:
    powershell -File freebuff-rtl-autopatch.ps1             # run keeper (foreground)
    powershell -File freebuff-rtl-autopatch.ps1 -Install    # register scheduled task + start
    powershell -File freebuff-rtl-autopatch.ps1 -Remove     # unregister scheduled task
    powershell -File freebuff-rtl-autopatch.ps1 -Once       # apply once, exit (for install-permanent.bat)

  The scheduled task is registered per-user and runs at every logon, hidden,
  with no admin rights required (the app lives under %LOCALAPPDATA%).
 ============================================================================
#>
[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$Remove,
  [switch]$Once,
  [int]$PollSeconds = 3,
  [string]$UiDir = ''   # optional: watch a specific ui folder (default: auto-detect)
)

$ErrorActionPreference = 'Stop'
$scriptSelf = $MyInvocation.MyCommand.Path
$scriptDir  = Split-Path -Parent $scriptSelf
$patchScript = Join-Path $scriptDir 'freebuff-rtl-patch.ps1'
$taskName   = 'Freebuff RTL Auto-Patch'
$logDir     = Join-Path $env:LOCALAPPDATA 'freebuff-rtl'
$logFile    = Join-Path $logDir 'autopatch.log'

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
  param([switch]$Light)
  try {
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $patchScript)
    if ($Light) { $args += '-Light' }
    if ($UiDir) { $args += @('-CssDir', (Join-Path $UiDir 'assets')) }
    $out = & powershell @args 2>&1 | Out-String
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

# ---- Install: register the per-user scheduled task --------------------------
# Autostart strategy:
#   * Primary: HKCU Run key - per-user, needs no admin rights, runs at every
#     logon. Verified to work even in restricted shells (scheduled-task
#     creation with an ONLOGON trigger requires elevation on many setups).
#   * The launcher value points at powershell.exe running this script
#     hidden, so no console window flashes at logon.
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runName = 'Freebuff RTL Auto-Patch'

function Get-LaunchValue {
  $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  return ('"' + $ps + '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $scriptSelf + '"')
}

function Register-Task {
  $value = Get-LaunchValue
  try {
    Set-ItemProperty -Path $runKey -Name $runName -Value $value -Force
    return $true
  } catch {
    return $false
  }
}

function Unregister-Task {
  try {
    Remove-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue
    return $true
  } catch {
    return $false
  }
}

if ($Install) {
  if (Register-Task) {
    Write-Host "[Freebuff RTL] Autostart entry '$taskName' registered - it will run at every logon." -ForegroundColor Green
  } else {
    Write-Host '[Freebuff RTL] Failed to register the autostart entry.' -ForegroundColor Red
    exit 1
  }
  Write-Host '[Freebuff RTL] Applying the patch now...'
  [void](Invoke-PatchOnce)
  Write-Host '[Freebuff RTL] Done. The patch will now survive Freebuff updates automatically.' -ForegroundColor Green
  exit 0
}

# ---- Remove: unregister the autostart entry --------------------------------
if ($Remove) {
  if (Unregister-Task) {
    Write-Host "[Freebuff RTL] Autostart entry '$taskName' removed." -ForegroundColor Green
  } else {
    Write-Host '[Freebuff RTL] Failed to remove the autostart entry.' -ForegroundColor Red
    exit 1
  }
  Write-Host '[Freebuff RTL] The RTL patch itself is untouched - run remove-rtl.bat to uninstall it too.' 
  exit 0
}

# ---- Once: apply and exit ----------------------------------------------------
if ($Once) {
  [void](Invoke-PatchOnce)
  exit 0
}

# ---- Keeper loop -------------------------------------------------------------
Write-Host "[Freebuff RTL] Keeper started - watching for Freebuff updates (poll every ${PollSeconds}s)." -ForegroundColor Green
Write-Log 'keeper started'

$lastHtmlMtime = $null
$lastCssMtime  = $null

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
  $m = [regex]::Match($htmlText, 'href="([^"]*index-[^"]*\.css)"')
  if ($m.Success) {
    $ref = $m.Groups[1].Value.TrimStart('./').Replace('/', '\')
    $candidate = Join-Path $assetsDir $ref
    if (Test-Path -LiteralPath $candidate) { $cssFile = $candidate }
  }
  if (-not $cssFile) {
    $cssFile = Get-ChildItem -LiteralPath $assetsDir -Filter 'index-*.css' -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notlike '*.bak' } | Select-Object -First 1 -ExpandProperty FullName
  }
  return @{ Html = $htmlFile; Css = $cssFile }
}

while ($true) {
  try {
    $paths = Get-InstallPaths
    if ($paths) {
      $htmlMtime = (Get-Item -LiteralPath $paths.Html -ErrorAction SilentlyContinue).LastWriteTimeUtc.Ticks
      $cssMtime  = if ($paths.Css) { (Get-Item -LiteralPath $paths.Css -ErrorAction SilentlyContinue).LastWriteTimeUtc.Ticks } else { $null }

      $changed = ($lastHtmlMtime -ne $null -and $htmlMtime -ne $lastHtmlMtime) -or
                 ($lastCssMtime -ne $null -and $cssMtime -ne $lastCssMtime)

      if ($changed -or $lastHtmlMtime -eq $null) {
        $lastHtmlMtime = $htmlMtime
        $lastCssMtime  = $cssMtime
        # File touched — could be an update OR our own patch. Re-check markers.
        $htmlText = [IO.File]::ReadAllText($paths.Html)
        $cssText  = if ($paths.Css) { [IO.File]::ReadAllText($paths.Css) } else { '' }
        # Versioned markers: if an older injected copy survived (the engine
        # only replaces when content differs), the version check fails and the
        # patch re-runs, upgrading the stale script in place.
        $rtlOk   = $htmlText -match 'freebuff-rtl-dragfix v1' -and
                   $htmlText -match 'freebuff-rtl-dir v1' -and
                   $htmlText -match 'dir="rtl"' -and
                   $cssText -match '/\* ==== freebuff-rtl ==== \*/'
        $lightOk = $htmlText -match 'freebuff-light v2' -and
                   $cssText -match '/\* ==== freebuff-light ==== \*/'
        if (-not $rtlOk) {
          Write-Log 'update detected - re-applying RTL patch'
          [void](Invoke-PatchOnce)
        }
        if (-not $lightOk) {
          Write-Log 'update detected - re-applying light-mode toggle'
          [void](Invoke-PatchOnce -Light)
        }
      }
    }
  } catch {
    Write-Log "keeper error: $($_.Exception.Message)"
  }
  Start-Sleep -Seconds $PollSeconds
}
