@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cloudflare-token-verify.ps1"
pause
