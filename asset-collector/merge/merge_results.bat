@echo off
chcp 65001 > nul
set "SCRIPT_DIR=%~dp0"

if "%~1"=="" (
    set "INPUT_DIR=%SCRIPT_DIR%..\results"
) else (
    set "INPUT_DIR=%~1"
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%merge_results.ps1" "%INPUT_DIR%"
