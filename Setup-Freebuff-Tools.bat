@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

:: 1. Check if user ran directly from inside ZIP without extracting
if not exist "%~dp0Setup-Freebuff-Tools.ps1" (
    cls
    echo ==========================================================================
    echo [שגיאה] קבצי ההתקנה לא חולצו במלואם!
    echo.
    echo נראה שניסית להפעיל את הקובץ ישירות מתוך ה-ZIP ללא חילוץ קודם.
    echo.
    echo כדי להתקין בהצלחה:
    echo 1. לחץ מקש ימני על קובץ ה-ZIP ובחר "חלץ הכל..." (Extract All).
    echo 2. היכנס לתיקייה שחולצה והפעל משם את Setup-Freebuff-Tools.bat.
    echo ==========================================================================
    echo.
    pause
    exit /b 1
)

:: 2. Unblock files in this folder if Windows marked them as blocked from internet
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

:: 3. Run the installer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Freebuff-Tools.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [שגיאה] ההתקנה נעצרה (קוד %ERRORLEVEL%).
    pause
)
