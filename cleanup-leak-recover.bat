@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup-leak-recover.ps1"
pause
