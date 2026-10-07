@echo off
chcp 65001 >nul
rem Home cloud server. Change the password and folder below if needed.
set CLOUD_DIR=D:\CloudStorage
set CLOUD_PORT=8080
set CLOUD_TOKEN=change-me

"%~dp0..\..\flutter\bin\cache\dart-sdk\bin\dart.exe" run "%~dp0bin\server.dart" --dir "%CLOUD_DIR%" --port %CLOUD_PORT% --token %CLOUD_TOKEN% --log "%~dp0logs\server.log"
pause
