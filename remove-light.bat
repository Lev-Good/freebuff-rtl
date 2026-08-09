@echo off
rem ===========================================================================
rem  Freebuff Desktop - Light mode toggle uninstaller (one click)
rem  Removes the light theme: strips the freebuff-light.css palette block and
rem  the toggle button script. The RTL patch (if installed) is untouched.
rem
rem  Usage:
rem    double-click               - uses the default install location
rem    remove-light.bat "PATH"    - PATH = folder containing index-*.css
rem ===========================================================================
setlocal
set "EXTRA="
if not "%~1"=="" set "EXTRA=-CssDir ""%~1"""
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0freebuff-rtl-patch.ps1" -RevertLight %EXTRA%
echo.
echo [Freebuff RTL] Restart Freebuff - the theme is back to the app default (dark).
pause
