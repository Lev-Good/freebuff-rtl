@echo off
rem ===========================================================================
rem  Freebuff Desktop - RTL permanent auto-patch installer (one click)
rem  Registers a per-user autostart entry (HKCU Run key) that starts the RTL
rem  keeper at every Windows logon. The keeper watches the Freebuff install
rem  and re-applies the RTL patch automatically after every Freebuff update -
rem  you never have to run apply-rtl.bat again.
rem
rem  Needs no admin rights (Freebuff installs under %LOCALAPPDATA%).
rem  To undo: run remove-permanent.bat
rem ===========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0freebuff-rtl-autopatch.ps1" -Install
echo.
echo [Freebuff RTL] Auto-patch is now installed permanently.
echo [Freebuff RTL] It starts at every logon and survives Freebuff updates.
echo [Freebuff RTL] Restart Freebuff once to load the patch.
pause
