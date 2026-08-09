@echo off
rem ===========================================================================
rem  Freebuff Desktop - Light mode toggle installer (one click)
rem  Adds the light theme: appends the freebuff-light.css palette and injects
rem  a small sun/moon toggle button (bottom-right of the app window). Works
rem  with or without the RTL patch. Idempotent - safe to re-run, and it
rem  refreshes an older light sheet in place.
rem
rem  Usage:
rem    double-click                - uses the default install location
rem    apply-light.bat "PATH"      - PATH = folder containing index-*.css
rem
rem  Note: Freebuff updates replace these files - run this again afterwards,
rem  or install the permanent auto-patch (install-permanent.bat) that keeps
rem  the light toggle AND the RTL patch alive across updates.
rem ===========================================================================
setlocal
set "EXTRA="
if not "%~1"=="" set "EXTRA=-CssDir ""%~1"""
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0freebuff-rtl-patch.ps1" -Light %EXTRA%
echo.
echo [Freebuff RTL] Restart Freebuff - a sun/moon button appears at the bottom-right.
pause
