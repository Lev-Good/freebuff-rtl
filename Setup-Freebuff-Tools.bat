@echo off
rem ===========================================================================
rem  Freebuff Tools & Hebrew All-in-One - One-Click Installer
rem ===========================================================================
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; & (Join-Path (Get-Location) 'Setup-Freebuff-Tools.ps1')"
pause
