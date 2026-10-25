@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

if not exist "0\" goto :nosrc
if not exist "1\" goto :nosrc
if not exist "2\" goto :nosrc
if not exist "3\startup.lua" goto :nosrc
if not exist "3\pocket_main.lua" goto :nosrc

set "COMMIT_MSG=%~1"
set "LOCAL_ONLY=0"
if /I "%~1"=="--local" (
  set "LOCAL_ONLY=1"
  set "COMMIT_MSG=%~2"
)
if /I "%~2"=="--local" set "LOCAL_ONLY=1"

echo [deploy] Purging mirrors (exact copy, no stale files)...
if exist "BeeOS" (
  rmdir /s /q "BeeOS"
  if errorlevel 1 goto :fail
)
if exist "LabOS" (
  rmdir /s /q "LabOS"
  if errorlevel 1 goto :fail
)
if exist "HeartOS" (
  rmdir /s /q "HeartOS"
  if errorlevel 1 goto :fail
)
if exist "PocketOS" (
  rmdir /s /q "PocketOS"
  if errorlevel 1 goto :fail
)

echo [deploy] Mirroring 0/ -^> BeeOS/
xcopy "0" "BeeOS" /E /I /Y >nul
if errorlevel 1 goto :fail
echo [deploy] Mirroring 1/ -^> LabOS/
xcopy "1" "LabOS" /E /I /Y >nul
if errorlevel 1 goto :fail
echo [deploy] Mirroring 2/ -^> HeartOS/
xcopy "2" "HeartOS" /E /I /Y >nul
if errorlevel 1 goto :fail

echo [deploy] Mirroring PocketOS program files from 3/
mkdir "PocketOS"
if errorlevel 1 goto :fail
xcopy "3\startup.lua" "PocketOS\" /I /Y >nul
if errorlevel 1 goto :fail
xcopy "3\pocket_main.lua" "PocketOS\" /I /Y >nul
if errorlevel 1 goto :fail

git add -A BeeOS/ LabOS/ HeartOS/ PocketOS/
if errorlevel 1 goto :fail

git diff --cached --quiet -- BeeOS/ LabOS/ HeartOS/ PocketOS/
if not errorlevel 1 (
  echo [deploy] Nothing staged. Skipping commit.
  goto :push
)

if "!COMMIT_MSG!"=="" (
  set "TMPF=%TEMP%\hiveos_deploy_files.txt"
  git diff --cached --name-only -- BeeOS/ LabOS/ HeartOS/ PocketOS/ > "!TMPF!"
  set "ROLES="
  findstr /b /c:"BeeOS/"   "!TMPF!" >nul && set "ROLES=!ROLES! BeeOS"
  findstr /b /c:"LabOS/"   "!TMPF!" >nul && set "ROLES=!ROLES! LabOS"
  findstr /b /c:"HeartOS/" "!TMPF!" >nul && set "ROLES=!ROLES! HeartOS"
  findstr /b /c:"PocketOS/" "!TMPF!" >nul && set "ROLES=!ROLES! PocketOS"
  del "!TMPF!" >nul 2>&1

  set "STAT="
  for /f "delims=" %%S in ('git diff --cached --stat -- BeeOS/ LabOS/ HeartOS/ PocketOS/') do set "STAT=%%S"

  set "COMMIT_MSG=deploy: sync!ROLES! - !STAT!"
)

git commit -m "!COMMIT_MSG!" -- BeeOS/ LabOS/ HeartOS/ PocketOS/
if errorlevel 1 goto :fail

:push
if "!LOCAL_ONLY!"=="1" (
  echo [deploy] Local commit complete. Push skipped.
  goto :done
)
echo [deploy] Pushing to origin...
git push -u origin HEAD
if errorlevel 1 goto :fail
echo [deploy] Done.
goto :done

:nosrc
echo [deploy] FAILED: required source files are missing from 0/ 1/ 2/ or 3/.
exit /b 1

:fail
echo [deploy] FAILED. See output above.
exit /b 1

:done
endlocal
