<#
 ============================================================================
  Freebuff Desktop — RTL & Tools Patch Engine (single source of truth)
 ============================================================================
  Applies (or reverts) the comprehensive enhancements for Freebuff:
    1. RTL Stylesheet (freebuff-rtl.css) & Drag Direction Fix (freebuff-rtl-dragfix.js)
    2. Unified Tools Hub (freebuff-tools-hub.js) - in-app single settings menu
    3. Hebrew Auto-Translation Engine (freebuff-auto-translate.js)
    4. Ad Blocker in orchestrator.js (removes disruptive chat ads)
    5. In-app updater notifier & update management (app-update.yml)

  Idempotent: safe to run repeatedly.
 ============================================================================
#>
[CmdletBinding()]
param(
  [string]$InstallRoot = '',
  [string]$CssDir = '',
  [switch]$NoRtl,
  [switch]$NoTranslate,
  [switch]$NoAdsBlock,
  [switch]$BlockUpdates,
  [switch]$AllowUpdates,
  [switch]$Revert,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$sheetFile        = Join-Path $scriptDir 'freebuff-rtl.css'
$shimFile         = Join-Path $scriptDir 'freebuff-rtl-dragfix.js'
$dirJsFile        = Join-Path $scriptDir 'freebuff-rtl-dir.js'
$toolsHubJsFile   = Join-Path $scriptDir 'freebuff-tools-hub.js'
$translateJsFile  = Join-Path $scriptDir 'freebuff-auto-translate.js'
$updaterJsFile    = Join-Path $scriptDir 'freebuff-rtl-updater.js'
$versionFile      = Join-Path $scriptDir 'VERSION'
$marker           = '/* ==== freebuff-rtl ==== */'
$lightMarker      = '/* ==== freebuff-light ==== */'

function Write-Out($msg) {
  if (-not $Quiet) { Write-Host "[Freebuff Tools] $msg" }
}

function Resolve-Paths {
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

  $uiDir = Split-Path -Parent $assetsDir
  $htmlFile = Join-Path $uiDir 'index.html'
  $orchFile = Join-Path (Split-Path -Parent $uiDir) 'orchestrator.js'
  $updateYml = Join-Path (Split-Path -Parent (Split-Path -Parent $uiDir)) 'app-update.yml'

  # Find the CSS file the app actually loads
  $cssFile = $null
  if (Test-Path -LiteralPath $htmlFile) {
    $htmlText = [IO.File]::ReadAllText($htmlFile)
    $m = [regex]::Match($htmlText, '(?i)href\s*=\s*["'']([^"'']*index-[^"'']*\.css)["'']')
    if ($m.Success) {
      $ref = $m.Groups[1].Value.TrimStart('./').Replace('/', '\')
      $candidate = Join-Path $assetsDir $ref
      if (Test-Path -LiteralPath $candidate) { $cssFile = $candidate }
    }
    if (-not $cssFile) {
      $m = [regex]::Match($htmlText, '(?i)href\s*=\s*["'']([^"'']*\.css)["'']')
      if ($m.Success) {
        $ref = $m.Groups[1].Value.TrimStart('./').Replace('/', '\')
        $candidate = Join-Path $assetsDir $ref
        if (Test-Path -LiteralPath $candidate) { $cssFile = $candidate }
      }
    }
  }
  if (-not $cssFile) {
    $cssFile = Get-ChildItem -LiteralPath $assetsDir -Filter 'index-*.css' -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notlike '*.pre-rtl.bak' -and $_.Name -notlike '*.bak' } |
      Select-Object -First 1 -ExpandProperty FullName
  }
  if (-not $cssFile) { return $null }

  return @{
    Html = $htmlFile
    Css = $cssFile
    Assets = $assetsDir
    Orchestrator = $orchFile
    UpdateYml = $updateYml
  }
}

function Set-InjectedScript {
  param([string]$Html, [string]$Marker, [string]$File, [string]$Content = '')
  if (-not $Content) { $Content = [IO.File]::ReadAllText($File) }
  $pattern = '(?is)<script[^>]*>\s*/\* ' + [regex]::Escape($Marker) + '.*?</script>'
  if ($Html -match $pattern) {
    return [regex]::Replace($Html, $pattern, '<script>' + $Content + '</script>')
  }
  return [regex]::Replace($Html, '(?i)(<head[^>]*>)', { param($x) $x.Groups[1].Value + '<script>' + $Content + '</script>' })
}

function Remove-InjectedScript {
  param([string]$Html, [string]$Marker)
  $pattern = '(?is)<script[^>]*>\s*/\* ' + [regex]::Escape($Marker) + '.*?</script>'
  if ($Html -match $pattern) {
    return [regex]::Replace($Html, $pattern, '')
  }
  return $Html
}

function Get-UpdaterScript {
  if (-not (Test-Path -LiteralPath $updaterJsFile)) { return '' }
  $version = '0.0.0'
  if (Test-Path -LiteralPath $versionFile) {
    $version = ([IO.File]::ReadAllText($versionFile)).Trim()
  }
  return ([IO.File]::ReadAllText($updaterJsFile)) -replace '__VERSION__', $version
}

function Patch-AdBlocking($orchFile) {
  if (-not (Test-Path -LiteralPath $orchFile)) { return }
  $content = [IO.File]::ReadAllText($orchFile)
  $original = $content
  $bak = $orchFile + '.bak'
  if (-not (Test-Path -LiteralPath $bak)) {
    Copy-Item -LiteralPath $orchFile -Destination $bak -Force
  }

  $methods = @('breakAd', 'partnerAd', 'intermissionAd', 'inlineAd', 'agenticOffer')
  foreach ($m in $methods) {
    $pattern = "(?s)(async\s+$m\s*\([^)]*\)\s*\{)(?!\s*return\s+null;)"
    if ($content -match $pattern) {
      $content = [regex]::Replace($content, $pattern, '$1 return null;')
    }
  }

  if ($content -ne $original) {
    [IO.File]::WriteAllText($orchFile, $content)
    Write-Out "Ad-blocking patched in orchestrator.js."
  } else {
    Write-Out "Ad-blocking already active in orchestrator.js."
  }
}

function Restore-AdBlocking($orchFile) {
  $bak = $orchFile + '.bak'
  if (Test-Path -LiteralPath $bak) {
    Copy-Item -LiteralPath $bak -Destination $orchFile -Force
    Write-Out "orchestrator.js restored from backup (ad-blocking removed)."
  }
}

function Set-UpdateBlocking($ymlFile, [bool]$block) {
  if (-not (Test-Path -LiteralPath $ymlFile)) { return }
  $text = [IO.File]::ReadAllText($ymlFile)
  if ($block) {
    $newText = $text -replace 'url:\s*https?://[^\r\n]+', 'url: http://127.0.0.1:0/'
    if ($newText -ne $text) {
      [IO.File]::WriteAllText($ymlFile, $newText)
      Write-Out "Auto-updates disabled in app-update.yml."
    }
  } else {
    $newText = $text -replace 'url:\s*http://127\.0\.0\.1:0/', 'url: https://update.codebuff.com/'
    if ($newText -ne $text) {
      [IO.File]::WriteAllText($ymlFile, $newText)
      Write-Out "Auto-updates enabled/restored in app-update.yml."
    }
  }
}

function Invoke-Apply {
  $paths = Resolve-Paths
  if (-not $paths) {
    Write-Out "Could not find Freebuff UI files. Pass -InstallRoot or -CssDir."
    exit 1
  }
  $htmlFile = $paths.Html
  $cssFile  = $paths.Css
  $html = [IO.File]::ReadAllText($htmlFile)
  $changedHtml = $false

  # --- 1) RTL Stylesheet & Drag fix ---
  if (-not $NoRtl) {
    if (Test-Path -LiteralPath $sheetFile) {
      $sheet = [IO.File]::ReadAllText($sheetFile)
      $css   = [IO.File]::ReadAllText($cssFile)

      $lightAt = $css.IndexOf($lightMarker)
      if ($lightAt -ge 0) {
        $css = $css.Substring(0, $lightAt)
        [IO.File]::WriteAllText($cssFile, $css)
        Write-Out 'CSS: removed old light-mode block.'
      }

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
        Write-Out 'CSS updated to latest RTL sheet.'
      } else {
        Write-Out 'CSS already up to date.'
      }
    }

    # Set dir="rtl" on html tag
    $m = [regex]::Match($html, '(?is)<html[^>]*>')
    if ($m.Success) {
      if ($m.Value -match '(?i)\sdir\s*=') {
        $newTag = [regex]::Replace($m.Value, '(?i)\sdir\s*=\s*(?:"[^"]*"|''[^'']*'')', ' dir="rtl"')
        if ($newTag -ne $m.Value) {
          $html = $html.Remove($m.Index, $m.Length).Insert($m.Index, $newTag)
          Write-Out 'dir attribute set to "rtl".'
          $changedHtml = $true
        }
      } else {
        $newTag = $m.Value -replace '<html', '<html dir="rtl"'
        $html = $html.Remove($m.Index, $m.Length).Insert($m.Index, $newTag)
        Write-Out 'dir="rtl" added to html tag.'
        $changedHtml = $true
      }
    }

    if (Test-Path -LiteralPath $shimFile) {
      $before = $html
      $html = Set-InjectedScript $html 'freebuff-rtl-dragfix' $shimFile
      if ($html -ne $before) { Write-Out 'Drag-direction shim injected.'; $changedHtml = $true }
    }
  }

  # --- 2) Unified Tools Hub or Direction button ---
  if (Test-Path -LiteralPath $toolsHubJsFile) {
    $before = $html
    # Strip standalone direction toggle if tools hub is installed
    $html = Remove-InjectedScript $html 'freebuff-rtl-dir'
    $html = Set-InjectedScript $html 'freebuff-tools-hub' $toolsHubJsFile
    if ($html -ne $before) { Write-Out 'Freebuff Tools Hub injected.'; $changedHtml = $true }
  } elseif (Test-Path -LiteralPath $dirJsFile) {
    $before = $html
    $html = Set-InjectedScript $html 'freebuff-rtl-dir' $dirJsFile
    if ($html -ne $before) { Write-Out 'RTL direction toggle injected.'; $changedHtml = $true }
  }

  # --- 3) Auto-translation engine ---
  if (-not $NoTranslate -and (Test-Path -LiteralPath $translateJsFile)) {
    $before = $html
    # Remove any old <script src="./freebuff-auto-translate.js"></script> tag if present
    $html = $html -replace '(?i)<script\s+src=["'']\.\/freebuff-auto-translate\.js["'']><\/script>', ''
    $html = Set-InjectedScript $html 'freebuff-auto-translate' $translateJsFile
    if ($html -ne $before) { Write-Out 'Hebrew auto-translation engine injected.'; $changedHtml = $true }
  }

  # --- 4) Updater notifier ---
  $updaterJs = Get-UpdaterScript
  if ($updaterJs) {
    $before = $html
    $html = Set-InjectedScript $html 'freebuff-rtl-updater' $updaterJsFile $updaterJs
    if ($html -ne $before) { Write-Out 'Update notifier injected.'; $changedHtml = $true }
  }

  # Clean old light-mode leftovers
  if ($html -match 'freebuff-light') {
    $html = [regex]::Replace($html, '(?is)<script[^>]*>\s*/\* freebuff-light.*?</script>', '')
    $changedHtml = $true
  }

  if ($changedHtml) {
    [IO.File]::WriteAllText($htmlFile, $html)
    Write-Out 'HTML file updated successfully.'
  }

  # --- 5) Ad blocking in orchestrator.js ---
  if (-not $NoAdsBlock -and (Test-Path -LiteralPath $paths.Orchestrator)) {
    Patch-AdBlocking $paths.Orchestrator
  }

  # --- 6) Auto-updates blocking ---
  if ($BlockUpdates -and (Test-Path -LiteralPath $paths.UpdateYml)) {
    Set-UpdateBlocking $paths.UpdateYml $true
  } elseif ($AllowUpdates -and (Test-Path -LiteralPath $paths.UpdateYml)) {
    Set-UpdateBlocking $paths.UpdateYml $false
  }

  Write-Out 'Patch complete! Restart Freebuff to apply all changes.'
  exit 0
}

function Invoke-Revert {
  $paths = Resolve-Paths
  if (-not $paths) {
    Write-Out "Could not find Freebuff UI files."
    exit 1
  }
  $htmlFile = $paths.Html
  $cssFile  = $paths.Css

  # --- 1) Strip CSS blocks ---
  if (Test-Path -LiteralPath $cssFile) {
    $css = [IO.File]::ReadAllText($cssFile)
    $changedCss = $false
    $i = $css.IndexOf($marker)
    if ($i -ge 0) {
      $css = $css.Substring(0, $i)
      $changedCss = $true
      Write-Out 'CSS: RTL block removed.'
    }
    $lightAt = $css.IndexOf($lightMarker)
    if ($lightAt -ge 0) {
      $css = $css.Substring(0, $lightAt)
      $changedCss = $true
      Write-Out 'CSS: light-mode block removed.'
    }
    if ($changedCss) { [IO.File]::WriteAllText($cssFile, $css) }
  }

  # --- 2) Remove injected scripts from index.html ---
  if (Test-Path -LiteralPath $htmlFile) {
    $html = [IO.File]::ReadAllText($htmlFile)
    $before = $html

    $html = Remove-InjectedScript $html 'freebuff-tools-hub'
    $html = Remove-InjectedScript $html 'freebuff-auto-translate'
    $html = Remove-InjectedScript $html 'freebuff-rtl-dragfix'
    $html = Remove-InjectedScript $html 'freebuff-rtl-dir'
    $html = Remove-InjectedScript $html 'freebuff-rtl-updater'
    $html = Remove-InjectedScript $html 'freebuff-light'
    $html = $html -replace '(?i)<script\s+src=["'']\.\/freebuff-auto-translate\.js["'']><\/script>', ''

    $m = [regex]::Match($html, '(?is)<html[^>]*>')
    if ($m.Success) {
      $newTag = $m.Value -replace '\sdir="[^"]*"', ''
      if ($newTag -ne $m.Value) {
        $html = $html.Remove($m.Index, $m.Length).Insert($m.Index, $newTag)
      }
    }

    if ($html -ne $before) {
      [IO.File]::WriteAllText($htmlFile, $html)
      Write-Out 'HTML: restored to original state.'
    }
  }

  # --- 3) Restore ad-blocking in orchestrator.js ---
  if (Test-Path -LiteralPath $paths.Orchestrator) {
    Restore-AdBlocking $paths.Orchestrator
  }

  # --- 4) Restore app-update.yml ---
  if (Test-Path -LiteralPath $paths.UpdateYml) {
    Set-UpdateBlocking $paths.UpdateYml $false
  }

  Write-Out 'Revert complete. Freebuff is back to factory state.'
  exit 0
}

if ($Revert) { Invoke-Revert }
else { Invoke-Apply }
