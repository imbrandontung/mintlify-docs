@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup-leak-finalpush.ps1"
pause
