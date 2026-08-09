@echo off
rem ===========================================================================
rem  Freebuff Desktop - RTL patch uninstaller (one click)
rem  Reverts the changes made by apply-rtl.bat: removes the RTL stylesheet
rem  block, strips dir="..." from the <html> tag and removes the drag shim.
rem
rem  Usage:
rem    double-click              - uses the default install location
rem    remove-rtl.bat "PATH"     - PATH = folder containing index-*.css
rem ===========================================================================
setlocal
set "EXTRA="
if not "%~1"=="" set "EXTRA=-CssDir ""%~1"""
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0freebuff-rtl-patch.ps1" -Revert %EXTRA%
echo.
echo [Freebuff RTL] Restart Freebuff - the layout is back to normal.
pause
