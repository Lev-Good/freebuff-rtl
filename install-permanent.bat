@echo off
rem ===========================================================================
rem  Freebuff Desktop - RTL + light-mode permanent auto-patch installer (one click)
rem  Registers a per-user autostart entry (HKCU Run key) that starts the
rem  keeper at every Windows logon. The keeper watches the Freebuff install
rem  and re-applies the RTL patch AND the light-mode toggle automatically
rem  after every Freebuff update - you never have to run apply-rtl.bat or
rem  apply-light.bat again.
rem
rem  Needs no admin rights (Freebuff installs under %LOCALAPPDATA%).
rem  To undo: run remove-permanent.bat
rem ===========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0freebuff-rtl-autopatch.ps1" -Install
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0freebuff-rtl-patch.ps1" -Light
echo.
echo [Freebuff RTL] Auto-patch is now installed permanently.
echo [Freebuff RTL] It starts at every logon and survives Freebuff updates.
echo [Freebuff RTL] Restart Freebuff once - the layout is RTL and a sun/moon
echo [Freebuff RTL] button at the bottom-right switches light/dark mode.
pause
