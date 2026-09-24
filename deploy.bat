@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

if not exist "0\" goto :nosrc
if not exist "1\" goto :nosrc
if not exist "2\" goto :nosrc

echo [deploy] Purging mirrors (exact copy, no stale files)...
if exist "BeeOS"   rmdir /s /q "BeeOS"
if exist "LabOS"   rmdir /s /q "LabOS"
if exist "HeartOS" rmdir /s /q "HeartOS"

echo [deploy] Mirroring 0/ -^> BeeOS/
xcopy "0" "BeeOS" /E /I /Y >nul
echo [deploy] Mirroring 1/ -^> LabOS/
xcopy "1" "LabOS" /E /I /Y >nul
echo [deploy] Mirroring 2/ -^> HeartOS/
xcopy "2" "HeartOS" /E /I /Y >nul

git add -A BeeOS/ LabOS/ HeartOS/
if errorlevel 1 goto :fail

git diff --cached --quiet
if not errorlevel 1 (
  echo [deploy] Nothing staged. Nothing to commit.
  goto :done
)

set "TMPF=%TEMP%\hiveos_deploy_files.txt"
git diff --cached --name-only > "%TMPF%"
set "ROLES="
findstr /b /c:"BeeOS/"   "%TMPF%" >nul && set "ROLES=!ROLES! BeeOS"
findstr /b /c:"LabOS/"   "%TMPF%" >nul && set "ROLES=!ROLES! LabOS"
findstr /b /c:"HeartOS/" "%TMPF%" >nul && set "ROLES=!ROLES! HeartOS"
del "%TMPF%" >nul 2>&1

set "STAT="
for /f "delims=" %%S in ('git diff --cached --stat') do set "STAT=%%S"

git commit -m "deploy: sync!ROLES! - !STAT!"
if errorlevel 1 goto :fail
git push
if errorlevel 1 goto :fail
echo [deploy] Done.
goto :done

:nosrc
echo [deploy] FAILED: run deploy.bat from the repo root (0/ 1/ 2/ not found).
exit /b 1

:fail
echo [deploy] FAILED. See output above.
exit /b 1

:done
endlocal
