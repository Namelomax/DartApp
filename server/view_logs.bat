@echo off
chcp 65001 >nul
rem Shows the last 50 log lines and keeps following new ones. Close with Ctrl+C.
powershell -NoProfile -Command "Get-Content -Encoding UTF8 -Path '%~dp0logs\server.log' -Tail 50 -Wait"
