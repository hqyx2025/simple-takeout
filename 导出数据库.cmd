@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\export-database.ps1"
set "EXPORT_RESULT=%ERRORLEVEL%"
pause
exit /b %EXPORT_RESULT%
