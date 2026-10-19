@echo off
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js was not found. Install Node.js 20.19+ or 22.12+ LTS, then reopen this file.
  pause
  exit /b 1
)
node scripts\serve.mjs %*
pause
