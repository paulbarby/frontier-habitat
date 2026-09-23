@echo off
rem Play Frontier Habitat: starts the local game server (if it is not running) and opens the game.
title Frontier Habitat
cd /d "%~dp0"
set PORT=5791
set URL=http://localhost:%PORT%/

if not exist "build\web\index.html" (
  echo The game build is missing: build\web\index.html
  pause
  exit /b 1
)

rem Is the server already running?
curl.exe -s -o nul -m 2 %URL%
if errorlevel 1 (
  echo Starting the game server on port %PORT% ...
  start "Frontier Habitat server - close this window to stop the game" /min node "%~dp0tools\serve.mjs" %PORT%
  rem Wait up to 10 seconds for it to answer.
  for /l %%i in (1,1,20) do (
    curl.exe -s -o nul -m 1 %URL% && goto :open
    timeout /t 1 /nobreak >nul
  )
  echo The server did not start. Is Node.js installed?
  pause
  exit /b 1
)

:open
rem Open in its own Chrome window if Chrome is installed, else in the default browser.
set CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe
if exist "%CHROME%" (
  start "" "%CHROME%" --app=%URL% --start-maximized
) else (
  start "" %URL%
)
exit /b 0
