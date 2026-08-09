<#
 ============================================================================
  Freebuff Desktop — RTL patch engine (single source of truth)
 ============================================================================
  Applies (or reverts) the three changes that make Freebuff right-to-left:

    1. Appends freebuff-rtl.css to the stylesheet the app actually serves
       (found via index.html, not guessed) — updates an older RTL sheet in
       place, keeps a .pre-rtl.bak backup of the pristine file.
    2. Adds dir="rtl" to the <html> tag in index.html — every rule in the
       sheet is gated on html[dir="rtl"], so without this the CSS stays inert.
    3. Injects freebuff-rtl-dragfix.js into index.html — reverses the
       explorer resize drag direction, which the app hard-codes for LTR.

  Idempotent: running it again is a no-op. Safe to call from the .bat
  installers, the DevTools launcher, and the auto-patch keeper.

  Usage:
    powershell -File freebuff-rtl-patch.ps1            # auto-detect install
    powershell -File freebuff-rtl-patch.ps1 -InstallRoot "C:\path\to\@codebufffreebuff-desktop"
    powershell -File freebuff-rtl-patch.ps1 -CssDir "C:\...\ui\assets"   # legacy arg
    powershell -File freebuff-rtl-patch.ps1 -Revert   # uninstall the patch
 ============================================================================
#>
[CmdletBinding()]
param(
  [string]$InstallRoot = '',
  [string]$CssDir = '',
  [switch]$Revert,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sheetFile = Join-Path $scriptDir 'freebuff-rtl.css'
$shimFile  = Join-Path $scriptDir 'freebuff-rtl-dragfix.js'
$marker    = '/* ==== freebuff-rtl ==== */'

function Write-Out($msg) {
  if (-not $Quiet) { Write-Host "[Freebuff RTL] $msg" }
}

function Resolve-Paths {
  # Returns @{ Html = ...; Css = ... } or $null.
  $htmlFile = $null
  $assetsDir = $null

  if ($CssDir) {
    $assetsDir = $CssDir
  }
  elseif ($InstallRoot) {
    if (Test-Path -LiteralPath (Join-Path $InstallRoot 'index.html')) {
      $assetsDir = Join-Path $InstallRoot 'assets'
    } else {
      $assetsDir = Join-Path $InstallRoot 'resources\orchestrator\ui\assets'
    }
  }
  else {
    $candidates = @(
      (Join-Path $env:LOCALAPPDATA 'Programs\@codebufffreebuff-desktop\resources\orchestrator\ui\assets'),
      (Join-Path $env:ProgramFiles '@codebufffreebuff-desktop\resources\orchestrator\ui\assets'),
      (Join-Path ${env:ProgramFiles(x86)} '@codebufffreebuff-desktop\resources\orchestrator\ui\assets')
    )
    $assetsDir = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  }

  if (-not $assetsDir -or -not (Test-Path -LiteralPath $assetsDir)) {
    return $null
  }

  $htmlFile = Join-Path (Split-Path -Parent $assetsDir) 'index.html'

  # Find the CSS file the app actually loads — from index.html, else glob.
  $cssFile = $null
  if (Test-Path -LiteralPath $htmlFile) {
    $htmlText = [IO.File]::ReadAllText($htmlFile)
    $m = [regex]::Match($htmlText, 'href="([^"]*index-[^"]*\.css)"')
    if ($m.Success) {
      $ref = $m.Groups[1].Value.TrimStart('./').Replace('/', '\')
      $candidate = Join-Path $assetsDir $ref
      if (Test-Path -LiteralPath $candidate) { $cssFile = $candidate }
    }
  }
  if (-not $cssFile) {
    $cssFile = Get-ChildItem -LiteralPath $assetsDir -Filter 'index-*.css' -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notlike '*.pre-rtl.bak' -and $_.Name -notlike '*.bak' } |
      Select-Object -First 1 -ExpandProperty FullName
  }
  if (-not $cssFile) { return $null }

  return @{ Html = $htmlFile; Css = $cssFile; Assets = $assetsDir }
}

function Invoke-Apply {
  $paths = Resolve-Paths
  if (-not $paths) {
    Write-Out "Could not find the Freebuff UI files. Pass -InstallRoot or -CssDir."
    exit 1
  }
  $htmlFile = $paths.Html
  $cssFile  = $paths.Css

  # --- 1) CSS ---------------------------------------------------------------
  if (-not (Test-Path -LiteralPath $sheetFile)) { Write-Out "Missing $sheetFile"; exit 1 }
  $sheet = [IO.File]::ReadAllText($sheetFile)
  $css   = [IO.File]::ReadAllText($cssFile)
  $i = $css.IndexOf($marker)
  if ($i -lt 0) {
    Copy-Item -LiteralPath $cssFile -Destination ($cssFile + '.pre-rtl.bak') -Force
    [IO.File]::WriteAllText($cssFile, $css + $sheet)
    Write-Out "CSS patched: $([IO.Path]::GetFileName($cssFile))"
  } elseif ($css.Substring($i) -ne $sheet) {
    if (-not (Test-Path -LiteralPath ($cssFile + '.pre-rtl.bak'))) {
      Copy-Item -LiteralPath $cssFile -Destination ($cssFile + '.pre-rtl.bak') -Force
    }
    [IO.File]::WriteAllText($cssFile, $css.Substring(0, $i) + $sheet)
    Write-Out 'CSS updated to the latest RTL sheet.'
  } else {
    Write-Out 'CSS already up to date.'
  }

  # --- 2 + 3) index.html: dir="rtl" + drag shim ----------------------------
  if (-not (Test-Path -LiteralPath $htmlFile)) {
    Write-Out "WARNING: $htmlFile not found - dir=rtl and drag shim were NOT set. RTL will NOT work."
    exit 1
  }
  if (-not (Test-Path -LiteralPath $shimFile)) { Write-Out "Missing $shimFile"; exit 1 }
  $html = [IO.File]::ReadAllText($htmlFile)
  $changed = $false

  $m = [regex]::Match($html, '(?is)<html[^>]*>')
  if ($m.Success -and $m.Value -notmatch '\sdir\s*=') {
    $newTag = $m.Value -replace '<html', '<html dir="rtl"'
    $html = $html.Remove($m.Index, $m.Length).Insert($m.Index, $newTag)
    Write-Out 'dir="rtl" added to the html tag.'
    $changed = $true
  } else {
    Write-Out 'dir already set on the html tag.'
  }

  if ($html -notmatch 'freebuff-rtl-dragfix') {
    $shim = [IO.File]::ReadAllText($shimFile)
    $html = [regex]::Replace($html, '(?i)(<head[^>]*>)', { param($x) $x.Groups[1].Value + '<script>' + $shim + '</script>' })
    Write-Out 'Drag-direction shim injected into index.html.'
    $changed = $true
  } else {
    Write-Out 'Drag-direction shim already present.'
  }

  if ($changed) { [IO.File]::WriteAllText($htmlFile, $html) }
  Write-Out 'Done. Restart Freebuff - the chat is now right-to-left.'
  exit 0
}

function Invoke-Revert {
  $paths = Resolve-Paths
  if (-not $paths) {
    Write-Out "Could not find the Freebuff UI files. Pass -InstallRoot or -CssDir."
    exit 1
  }
  $htmlFile = $paths.Html
  $cssFile  = $paths.Css

  # --- 1) strip the RTL block from the CSS ---
  $css = [IO.File]::ReadAllText($cssFile)
  $i = $css.IndexOf($marker)
  if ($i -lt 0) {
    Write-Out 'CSS: RTL was not applied - nothing to remove.'
  } else {
    [IO.File]::WriteAllText($cssFile, $css.Substring(0, $i))
    Write-Out 'CSS: RTL block removed.'
  }

  # --- 2) remove the drag shim + dir from index.html ---
  if (Test-Path -LiteralPath $htmlFile) {
    $html = [IO.File]::ReadAllText($htmlFile)
    $changed = $false
    if ($html -match 'freebuff-rtl-dragfix') {
      $html = [regex]::Replace($html, '(?is)<script[^>]*>\s*/\* freebuff-rtl-dragfix \*/.*?</script>', '')
      Write-Out 'HTML: drag shim removed.'
      $changed = $true
    } else {
      Write-Out 'HTML: no drag shim - nothing to remove.'
    }
    $m = [regex]::Match($html, '(?is)<html[^>]*>')
    if ($m.Success) {
      $newTag = $m.Value -replace '\sdir="[^"]*"', ''
      if ($newTag -ne $m.Value) {
        $html = $html.Remove($m.Index, $m.Length).Insert($m.Index, $newTag)
        Write-Out 'HTML: dir removed from the html tag.'
        $changed = $true
      } else {
        Write-Out 'HTML: no dir attribute - nothing to do.'
      }
    } else {
      Write-Out 'HTML: no html tag found - nothing to do.'
    }
    if ($changed) { [IO.File]::WriteAllText($htmlFile, $html) }
  } else {
    Write-Out "HTML: $htmlFile not found - skipped."
  }

  Write-Out 'Done. Restart Freebuff - the layout is back to normal.'
  exit 0
}

if ($Revert) { Invoke-Revert } else { Invoke-Apply }
