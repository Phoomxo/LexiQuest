@echo off
setlocal
set GATE=%1
if "%GATE%"=="" set GATE=All
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0agent_pipeline.ps1" -Gate %GATE%
exit /b %ERRORLEVEL%
