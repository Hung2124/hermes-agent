@echo off
setlocal enabledelayedexpansion
set RES=%LOCALAPPDATA%\Programs\hermes\resources
set NEW=%LOCALAPPDATA%\hermes\hermes-agent\apps\desktop\app.asar.fixed
set EXE=%LOCALAPPDATA%\Programs\hermes\Hermes.exe
set VALIDATOR=%~dp0scripts\validate-asar.mjs
rem app.asar is ~44 MB; anything under 10 MB is almost certainly a bad/partial build.
set MIN_BYTES=10000000
set KEEP_BACKUPS=3
set BOOT_WAIT=8

if not exist "%NEW%" (
  echo ERROR: app.asar.fixed not found at "%NEW%"
  pause
  exit /b 1
)
if not exist "%RES%\app.asar" (
  echo ERROR: installed app.asar not found at "%RES%\app.asar"
  pause
  exit /b 1
)

rem --- Validate BEFORE touching the install: size floor + parseable asar header. ---
echo Validating new archive...
node "%VALIDATOR%" "%NEW%" %MIN_BYTES%
if errorlevel 1 (
  echo ERROR: app.asar.fixed failed validation. Aborting - nothing was changed.
  pause
  exit /b 1
)

rem wmic was removed in Windows 11, so use PowerShell for the timestamp.
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set TS=%%I
set BACKUP=%RES%\app.asar.bak-!TS!

echo Closing Hermes...
taskkill /IM Hermes.exe /F >nul 2>&1
rem Start-Sleep instead of timeout.exe: timeout aborts when stdin is redirected (e.g. invoked from git-bash/CI).
powershell -NoProfile -Command "Start-Sleep -Seconds 3"

echo Backing up current app.asar to app.asar.bak-!TS! ...
copy /y "%RES%\app.asar" "!BACKUP!" >nul
if errorlevel 1 (
  echo ERROR: backup failed. Aborting - nothing was changed.
  pause
  exit /b 1
)

echo Swapping in updated app.asar...
copy /y "%NEW%" "%RES%\app.asar" >nul
if errorlevel 1 (
  echo ERROR: copy failed. Restoring backup...
  copy /y "!BACKUP!" "%RES%\app.asar" >nul
  pause
  exit /b 1
)

echo Relaunching Hermes...
start "" "%EXE%"

rem --- Confirm a clean boot; auto-rollback if the app died on startup. ---
echo Waiting %BOOT_WAIT%s to confirm Hermes stays up...
powershell -NoProfile -Command "Start-Sleep -Seconds %BOOT_WAIT%"
rem Absolute find.exe path: git-bash puts GNU find first on PATH, which breaks the boot check.
tasklist /FI "IMAGENAME eq Hermes.exe" 2>nul | "%SystemRoot%\System32\find.exe" /I "Hermes.exe" >nul
if errorlevel 1 (
  echo ERROR: Hermes did not stay running - rolling back to app.asar.bak-!TS! ...
  taskkill /IM Hermes.exe /F >nul 2>&1
  powershell -NoProfile -Command "Start-Sleep -Seconds 2"
  copy /y "!BACKUP!" "%RES%\app.asar" >nul
  start "" "%EXE%"
  echo Rolled back. The updated archive failed to boot and was reverted; old version is launching.
  pause
  exit /b 1
)

rem --- Boot confirmed: keep only the newest %KEEP_BACKUPS% timestamped backups. ---
rem (The unmanaged plain app.asar.bak, if any, is intentionally left untouched.)
echo Boot confirmed. Pruning old backups (keeping newest %KEEP_BACKUPS%)...
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%RES%' -Filter 'app.asar.bak-*' | Sort-Object LastWriteTime -Descending | Select-Object -Skip %KEEP_BACKUPS% | Remove-Item -Force -ErrorAction SilentlyContinue"

echo Done. Updated desktop is running. Backup saved as app.asar.bak-!TS!
endlocal
