@echo off
rem v1.1 / 20: Prefer the project Python environment with pyserial installed.
cd /d "%~dp0.."
if exist "ml\.venv\Scripts\python.exe" (
    "ml\.venv\Scripts\python.exe" -m host.gui %*
) else (
    python -m host.gui %*
)
if errorlevel 1 pause
