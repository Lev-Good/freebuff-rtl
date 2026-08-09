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
    powershell -File freebuff-rtl-patch.ps1 -Light          # add light-mode toggle (works with or without RTL)
    powershell -File freebuff-rtl-patch.ps1 -RevertLight    # remove light-mode toggle
 ============================================================================
#>
[CmdletBinding()]
param(
  [string]$InstallRoot = '',
  [string]$CssDir = '',
  [switch]$Revert,
  [switch]$Light,
  [switch]$RevertLight,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sheetFile = Join-Path $scriptDir 'freebuff-rtl.css'
$shimFile  = Join-Path $scriptDir 'freebuff-rtl-dragfix.js'
$dirJsFile = Join-Path $scriptDir 'freebuff-rtl-dir.js'
$marker    = '/* ==== freebuff-rtl ==== */'
$lightSheet   = Join-Path $scriptDir 'freebuff-light.css'
$lightJs      = Join-Path $scriptDir 'freebuff-light.js'
$lightMarker  = '/* ==== freebuff-light ==== */'

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

function Set-InjectedScript {
  # Replaces (or inserts) the injected <script> block for $marker with the
  # current contents of $file. Older injected copies (e.g. the pre-icon
  # light-mode script) are swapped in place instead of being left stale.
  # Returns the updated html.
  param([string]$Html, [string]$Marker, [string]$File)
  $js = [IO.File]::ReadAllText($File)
  $pattern = '(?is)<script[^>]*>\s*/\* ' + [regex]::Escape($Marker) + '.*?</script>'
  if ($Html -match $pattern) {
    return [regex]::Replace($Html, $pattern, '<script>' + $js + '</script>')
  }
  return [regex]::Replace($Html, '(?i)(<head[^>]*>)', { param($x) $x.Groups[1].Value + '<script>' + $js + '</script>' })
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
    # Replace only the old RTL block - keep any blocks appended after it
    # (e.g. the light-theme block) by splicing them back on.
    $nextMarker = $css.IndexOf($lightMarker, $i + $marker.Length)
    $suffix = if ($nextMarker -ge 0) { $css.Substring($nextMarker) } else { '' }
    [IO.File]::WriteAllText($cssFile, $css.Substring(0, $i) + $sheet + $suffix)
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
  if (-not (Test-Path -LiteralPath $dirJsFile)) { Write-Out "Missing $dirJsFile"; exit 1 }
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

  $before = $html
  $html = Set-InjectedScript $html 'freebuff-rtl-dragfix' $shimFile
  if ($html -ne $before) {
    Write-Out 'Drag-direction shim injected/updated in index.html.'
    $changed = $true
  } else {
    Write-Out 'Drag-direction shim already up to date.'
  }

  $before = $html
  $html = Set-InjectedScript $html 'freebuff-rtl-dir' $dirJsFile
  if ($html -ne $before) {
    Write-Out 'RTL/LTR direction toggle injected/updated in index.html.'
    $changed = $true
  } else {
    Write-Out 'RTL/LTR direction toggle already up to date.'
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

  # --- 1) strip the RTL block from the CSS (keep any blocks after it) ---
  $css = [IO.File]::ReadAllText($cssFile)
  $i = $css.IndexOf($marker)
  if ($i -lt 0) {
    Write-Out 'CSS: RTL was not applied - nothing to remove.'
  } else {
    $nextMarker = $css.IndexOf($lightMarker, $i + $marker.Length)
    $suffix = if ($nextMarker -ge 0) { $css.Substring($nextMarker) } else { '' }
    [IO.File]::WriteAllText($cssFile, $css.Substring(0, $i) + $suffix)
    Write-Out 'CSS: RTL block removed.'
  }

  # --- 2) remove the drag shim + dir from index.html ---
  if (Test-Path -LiteralPath $htmlFile) {
    $html = [IO.File]::ReadAllText($htmlFile)
    $changed = $false
    if ($html -match 'freebuff-rtl-dragfix') {
      $html = [regex]::Replace($html, '(?is)<script[^>]*>\s*/\* freebuff-rtl-dragfix.*?</script>', '')
      Write-Out 'HTML: drag shim removed.'
      $changed = $true
    } else {
      Write-Out 'HTML: no drag shim - nothing to remove.'
    }
    if ($html -match 'freebuff-rtl-dir') {
      $html = [regex]::Replace($html, '(?is)<script[^>]*>\s*/\* freebuff-rtl-dir.*?</script>', '')
      Write-Out 'HTML: direction toggle removed.'
      $changed = $true
    } else {
      Write-Out 'HTML: no direction toggle - nothing to remove.'
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

function Invoke-ApplyLight {
  $paths = Resolve-Paths
  if (-not $paths) {
    Write-Out "Could not find the Freebuff UI files. Pass -InstallRoot or -CssDir."
    exit 1
  }
  $htmlFile = $paths.Html
  $cssFile  = $paths.Css

  # --- 1) CSS: append / refresh the light block -----------------------------
  if (-not (Test-Path -LiteralPath $lightSheet)) { Write-Out "Missing $lightSheet"; exit 1 }
  $sheet = [IO.File]::ReadAllText($lightSheet)
  $css   = [IO.File]::ReadAllText($cssFile)
  $i = $css.IndexOf($lightMarker)
  if ($i -lt 0) {
    if (-not (Test-Path -LiteralPath ($cssFile + '.pre-rtl.bak'))) {
      Copy-Item -LiteralPath $cssFile -Destination ($cssFile + '.pre-rtl.bak') -Force
    }
    [IO.File]::WriteAllText($cssFile, $css + $sheet)
    Write-Out "Light CSS patched: $([IO.Path]::GetFileName($cssFile))"
  } elseif ($css.Substring($i) -ne $sheet) {
    [IO.File]::WriteAllText($cssFile, $css.Substring(0, $i) + $sheet)
    Write-Out 'Light CSS updated to the latest sheet.'
  } else {
    Write-Out 'Light CSS already up to date.'
  }

  # --- 2) index.html: inject the toggle button script -----------------------
  if (-not (Test-Path -LiteralPath $htmlFile)) {
    Write-Out "WARNING: $htmlFile not found - light-mode toggle was NOT set."
    exit 1
  }
  if (-not (Test-Path -LiteralPath $lightJs)) { Write-Out "Missing $lightJs"; exit 1 }
  $html = [IO.File]::ReadAllText($htmlFile)
  $before = $html
  $html = Set-InjectedScript $html 'freebuff-light' $lightJs
  if ($html -ne $before) {
    [IO.File]::WriteAllText($htmlFile, $html)
    Write-Out 'Light-mode toggle injected/updated in index.html.'
  } else {
    Write-Out 'Light-mode toggle already up to date.'
  }

  Write-Out 'Done. A sun/moon button appears at the bottom-right - click it to switch.'
  exit 0
}

function Invoke-RevertLight {
  $paths = Resolve-Paths
  if (-not $paths) {
    Write-Out "Could not find the Freebuff UI files. Pass -InstallRoot or -CssDir."
    exit 1
  }
  $htmlFile = $paths.Html
  $cssFile  = $paths.Css

  # --- 1) strip the light block from the CSS ---
  $css = [IO.File]::ReadAllText($cssFile)
  $i = $css.IndexOf($lightMarker)
  if ($i -lt 0) {
    Write-Out 'CSS: light theme was not applied - nothing to remove.'
  } else {
    [IO.File]::WriteAllText($cssFile, $css.Substring(0, $i))
    Write-Out 'CSS: light block removed.'
  }

  # --- 2) remove the toggle script from index.html ---
  if (Test-Path -LiteralPath $htmlFile) {
    $html = [IO.File]::ReadAllText($htmlFile)
    if ($html -match 'freebuff-light') {
      $html = [regex]::Replace($html, '(?is)<script[^>]*>\s*/\* freebuff-light.*?</script>', '')
      [IO.File]::WriteAllText($htmlFile, $html)
      Write-Out 'HTML: light-mode toggle removed.'
    } else {
      Write-Out 'HTML: no light-mode toggle - nothing to remove.'
    }
  } else {
    Write-Out "HTML: $htmlFile not found - skipped."
  }

  Write-Out 'Done. The theme is back to the app default (dark).'
  exit 0
}

if ($RevertLight) { Invoke-RevertLight }
elseif ($Light) { Invoke-ApplyLight }
elseif ($Revert) { Invoke-Revert }
else { Invoke-Apply }
