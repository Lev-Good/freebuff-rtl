<#
 ============================================================================
  Freebuff Desktop — RTL launcher (Windows, PowerShell 5+)
 ============================================================================
  Starts Freebuff Desktop with the Chromium remote-debugging port (loopback
  only), then connects over the Chrome DevTools Protocol and injects
  freebuff-rtl.js into every app window:

    * Page.addScriptToEvaluateOnNewDocument  -> applies to reloads & new windows
    * Runtime.evaluate                       -> applies to the already-open page

  The script keeps running so the injection survives page reloads. Close the
  window (or Ctrl+C) to stop; Freebuff itself keeps running.

  IMPORTANT:
    Freebuff enforces a single instance. If it is already running when this
    script starts, the debug port can never open — close Freebuff first, then
    run this script. From then on, always launch Freebuff through this script
    to keep RTL applied.
 ============================================================================
#>

[CmdletBinding()]
param(
  [int]    $Port    = 9222,
  [string] $AppPath = (Join-Path $env:LOCALAPPDATA 'Programs\@codebufffreebuff-desktop\Freebuff.exe')
)

$ErrorActionPreference = 'Stop'
$scriptFile = Join-Path $PSScriptRoot 'freebuff-rtl.js'

if (-not (Test-Path -LiteralPath $AppPath)) {
  Write-Host "Freebuff not found at: $AppPath" -ForegroundColor Red
  Write-Host 'Pass -AppPath <path-to-Freebuff.exe> if it is installed elsewhere.'
  exit 1
}
if (-not (Test-Path -LiteralPath $scriptFile)) {
  Write-Host "Missing $scriptFile (must sit next to this script)." -ForegroundColor Red
  exit 1
}

# --- CDP helpers (Windows PowerShell 5 compatible) ---------------------------
function Send-Cdp {
  param($ws, [int]$id, [string]$method, $params)
  $obj = @{ id = $id; method = $method }
  if ($null -ne $params) { $obj.params = $params }
  $json = $obj | ConvertTo-Json -Depth 12 -Compress
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $seg = [ArraySegment[byte]]::new($bytes)
  $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true,
    [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
}

function Get-AppTargets {
  try {
    $json = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json" -TimeoutSec 2
  } catch { return @() }
  return @($json | Where-Object { $_.type -eq 'page' -and $_.url -like 'http://127.0.0.1:*' })
}

$scriptSource = Get-Content -Raw -LiteralPath $scriptFile
$sessions = @{}   # targetId -> ClientWebSocket

function Connect-Target {
  param($target)
  try {
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl,
      [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    # New documents (reloads, later windows) get RTL from the start...
    Send-Cdp $ws 1 'Page.addScriptToEvaluateOnNewDocument' @{ source = $scriptSource }
    # ...and the page that is already open gets it right now.
    Send-Cdp $ws 2 'Runtime.evaluate' @{ expression = $scriptSource; returnByValue = $false }
    $script:sessions[$target.id] = $ws
    Write-Host "  RTL injected into: $($target.url)" -ForegroundColor Green
    return $true
  } catch {
    Write-Host "  Failed to attach to $($target.url): $($_.Exception.Message)" -ForegroundColor Yellow
    return $false
  }
}

# --- boot --------------------------------------------------------------------
$existing = Get-Process -Name Freebuff -ErrorAction SilentlyContinue
if ($existing) {
  Write-Host 'Freebuff is already running.' -ForegroundColor Yellow
  Write-Host 'The single-instance lock prevents a second process from opening the debug port.'
  Write-Host 'Close Freebuff, then re-run this script (use it as the way to start Freebuff).'
  exit 1
}

Write-Host "Starting Freebuff with debug port $Port ..."
$proc = Start-Process -FilePath $AppPath -ArgumentList "--remote-debugging-port=$Port" -PassThru
Start-Sleep -Seconds 2

# --- wait for the debug endpoint ----------------------------------------------
$deadline = (Get-Date).AddSeconds(60)
$targets = @()
while ((Get-Date) -lt $deadline) {
  $targets = Get-AppTargets
  if ($targets.Count -gt 0) { break }
  Start-Sleep -Milliseconds 500
}
if ($targets.Count -eq 0) {
  Write-Host 'Timed out waiting for the debug port. Is another Freebuff instance running?' -ForegroundColor Red
  exit 1
}

Write-Host 'Freebuff is up — injecting RTL. Keep this window open; Ctrl+C to stop.'
foreach ($t in $targets) { [void](Connect-Target $t) }

# --- keep-alive loop: attach to new windows, drop dead ones --------------------
while ($true) {
  Start-Sleep -Milliseconds 1000

  if ($proc.HasExited -or -not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) {
    Write-Host 'Freebuff closed — exiting.' -ForegroundColor Yellow
    break
  }

  $current = Get-AppTargets
  $currentIds = @{}
  foreach ($t in $current) { $currentIds[$t.id] = $t }

  # drop sessions whose window is gone
  foreach ($id in @($sessions.Keys)) {
    if (-not $currentIds.ContainsKey($id)) {
      try { $sessions[$id].Dispose() } catch {}
      $sessions.Remove($id)
    }
  }

  # attach to new windows (e.g. thread pop-outs)
  foreach ($t in $current) {
    if (-not $sessions.ContainsKey($t.id)) {
      [void](Connect-Target $t)
    }
  }
}

foreach ($id in @($sessions.Keys)) {
  try { $sessions[$id].Dispose() } catch {}
}
