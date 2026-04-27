@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup-leak.ps1"
pause
