@echo off
rem ===========================================================================
rem  Freebuff Desktop - RTL permanent auto-patch uninstaller (one click)
rem  Removes the autostart entry that re-applies the RTL patch after updates.
rem  The RTL patch itself stays applied - run remove-rtl.bat if you also want
rem  to go back to the normal left-to-right layout.
rem ===========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0freebuff-rtl-autopatch.ps1" -Remove
echo.
echo [Freebuff RTL] Auto-patch removed.
echo [Freebuff RTL] Future Freebuff updates will NOT re-apply RTL automatically.
pause
