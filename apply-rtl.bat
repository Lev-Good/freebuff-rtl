@echo off
rem ===========================================================================
rem  Freebuff Desktop - RTL patch installer (one click)
rem  Applies the RTL layout: appends the RTL stylesheet, sets dir="rtl" and
rem  injects the drag-direction shim. Idempotent - safe to re-run, and it
rem  refreshes an older RTL sheet in place.
rem
rem  Usage:
rem    double-click            - uses the default install location
rem    apply-rtl.bat "PATH"    - PATH = folder containing index-*.css
rem
rem  Note: Freebuff updates replace these files - run this again afterwards.
rem  For a permanent fix that survives updates automatically, run
rem  install-permanent.bat once instead.
rem ===========================================================================
setlocal
set "EXTRA="
if not "%~1"=="" set "EXTRA=-CssDir ""%~1"""
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0freebuff-rtl-patch.ps1" %EXTRA%
echo.
echo [Freebuff RTL] Restart Freebuff - the chat is now right-to-left.
pause
