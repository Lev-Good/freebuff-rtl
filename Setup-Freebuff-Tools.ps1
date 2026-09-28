# ============================================================================
#  Freebuff Tools & Hebrew All-in-One - Master Setup Script
# ============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Freebuff All-in-One Setup"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$autopatchScript = Join-Path $scriptDir 'freebuff-rtl-autopatch.ps1'
$patchScript     = Join-Path $scriptDir 'freebuff-rtl-patch.ps1'

function Show-Header {
    Clear-Host
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "       חבילת הכלים, העברית ושיפורי הממשק ל-Freebuff Desktop" -ForegroundColor Yellow
    Write-Host "       כולל: תרגום לעברית | RTL | חסימת פרסומות | מרכז בקרה פנימי" -ForegroundColor White
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Restart-FreebuffApp {
    $procs = Get-Process -Name 'Freebuff' -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "מזהה ש-Freebuff פועלת כעת." -ForegroundColor Yellow
        $ans = Read-Host "האם לסגור ולהפעיל אותה מחדש כעת כדי להחיל את השינויים? (Y/N)"
        if ($ans -match '^[Yyכן]') {
            Write-Host "סוגר את Freebuff..." -ForegroundColor Cyan
            $procs | Stop-Process -Force
            Start-Sleep -Seconds 1
            $freebuffExe = Join-Path $env:LOCALAPPDATA 'Programs\@codebufffreebuff-desktop\Freebuff.exe'
            if (Test-Path -LiteralPath $freebuffExe) {
                Write-Host "מפעיל את Freebuff מחדש..." -ForegroundColor Green
                Start-Process -FilePath $freebuffExe
            }
        }
    }
}

function Install-Full {
    Show-Header
    Write-Host "מתחיל בהתקנה מלאה (1-Click Install)..." -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------------"
    
    # 1. Register background keeper (protects against updates & self-updates)
    if (Test-Path -LiteralPath $autopatchScript) {
        Write-Host "[1/3] מגדיר שירות שמירה אוטומטי (שומר על השינויים בעדכוני תוכנה)..." -ForegroundColor White
        & powershell -NoProfile -ExecutionPolicy Bypass -File $autopatchScript -Install
    }

    # 2. Apply full patch (RTL + Translation + Hub + AdBlock)
    if (Test-Path -LiteralPath $patchScript) {
        Write-Host "[2/3] מחיל עברית, RTL, חסימת פרסומות ומרכז שליטה פנימי..." -ForegroundColor White
        & powershell -NoProfile -ExecutionPolicy Bypass -File $patchScript
    }

    Write-Host "[3/3] בדיקת עדכונים ראשונית..." -ForegroundColor White
    if (Test-Path -LiteralPath $autopatchScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $autopatchScript -CheckUpdates
    }

    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host "               ההתקנה המלאה הושלמה בהצלחה!" -ForegroundColor Green
    Write-Host " כעת תמצא בתוך התוכנה (בפינה הימנית התחתונה) כפתור חדש:" -ForegroundColor Yellow
    Write-Host " [⚙️ כלים] - בלחיצה עליו תוכל לכבות/להדליק כל תכונה כרצונך בכל עת!" -ForegroundColor Yellow
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host ""
    Restart-FreebuffApp
}

function Install-Modular {
    Show-Header
    Write-Host "התקנה מותאמת אישית (בחירת רכיבים בנפרד)" -ForegroundColor Yellow
    Write-Host "בחר אילו תכונות ברצונך להתקין:" -ForegroundColor White
    Write-Host "--------------------------------------------------------------------------"

    $ansTrans = Read-Host "1. האם להתקין תרגום ממשק לעברית? (Y/n)"
    $ansRtl   = Read-Host "2. האם להתקין היפוך תצוגה מימין לשמאל (RTL)? (Y/n)"
    $ansAds   = Read-Host "3. האם לחסום פרסומות והצעות בצ'אט? (Y/n)"
    $ansUpd   = Read-Host "4. האם לחסום עדכונים אוטומטיים של Freebuff? (y/N)"
    $ansKeep  = Read-Host "5. האם להפעיל שמירה קבועה נגד דריסת קבצים (Keeper)? (Y/n)"

    $args = @()
    if ($ansRtl -match '^[Nnלא]') { $args += '-NoRtl' }
    if ($ansTrans -match '^[Nnלא]') { $args += '-NoTranslate' }
    if ($ansAds -match '^[Nnלא]') { $args += '-NoAdsBlock' }
    if ($ansUpd -match '^[Yyכן]') { $args += '-BlockUpdates' } else { $args += '-AllowUpdates' }

    Write-Host ""
    Write-Host "מחיל את ההגדרות שבחרת..." -ForegroundColor Green

    if ($ansKeep -notmatch '^[Nnלא]' -and (Test-Path -LiteralPath $autopatchScript)) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $autopatchScript -Install
    }

    if (Test-Path -LiteralPath $patchScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $patchScript @args
    }

    Write-Host ""
    Write-Host "ההתקנה המותאמת הושלמה בהצלחה!" -ForegroundColor Green
    Restart-FreebuffApp
}

function Uninstall-All {
    Show-Header
    Write-Host "הסרת כל השינויים ושחזור Freebuff למצב המקורי" -ForegroundColor Red
    Write-Host "--------------------------------------------------------------------------"
    $confirm = Read-Host "האם אתה בטוח שברצונך להסיר את כל השינויים? (Y/N)"
    if ($confirm -match '^[Yyכן]') {
        if (Test-Path -LiteralPath $autopatchScript) {
            Write-Host "מסיר שירות שמירה ורקע..." -ForegroundColor White
            & powershell -NoProfile -ExecutionPolicy Bypass -File $autopatchScript -Uninstall
        }
        if (Test-Path -LiteralPath $patchScript) {
            Write-Host "משחזר קבצי מערכת, ממשק ותרגום..." -ForegroundColor White
            & powershell -NoProfile -ExecutionPolicy Bypass -File $patchScript -Revert
        }
        Write-Host ""
        Write-Host "ההסרה הושלמה. Freebuff שוחזרה למצבה המקורי." -ForegroundColor Green
        Restart-FreebuffApp
    }
}

# Main Interactive Loop
while ($true) {
    Show-Header
    Write-Host "[1] התקנה מלאה מומלצת בלחיצה אחת (עברית + RTL + חסימת פרסומות + כפתור כלים)" -ForegroundColor Green
    Write-Host "[2] התקנה מותאמת אישית (בחירת רכיבים בנפרד לפי העדפתך)" -ForegroundColor Cyan
    Write-Host "[3] הפעלה מחדש של Freebuff" -ForegroundColor White
    Write-Host "[4] הסרה מלאה ושחזור Freebuff למצב ברירת מחדל" -ForegroundColor Red
    Write-Host "[5] יציאה" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "בחר אפשרות [1-5]"
    switch ($choice) {
        '1' { Install-Full; Read-Host "לחץ Enter להמשך..."; break }
        '2' { Install-Modular; Read-Host "לחץ Enter להמשך..."; break }
        '3' { Restart-FreebuffApp; Read-Host "לחץ Enter להמשך..."; break }
        '4' { Uninstall-All; Read-Host "לחץ Enter להמשך..."; break }
        '5' { exit 0 }
        default {
            Write-Host "בחירה לא תקינה, נסה שוב." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
