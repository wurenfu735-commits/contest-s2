@echo off
rem Backup DSH chat/session data before uninstall (double-click to run).
rem Backs up D:\dsh-home\profiles and D:\dsh-home\storages only.
set SRC=D:\dsh-home
set DST=D:\dsh_backup_before_reinstall
if not exist "%SRC%" (
  echo [FAIL] %SRC% not found, nothing backed up.
  goto END
)
if not exist "%DST%" mkdir "%DST%"
echo [1/3] backing up profiles ...
xcopy /E /I /Y "%SRC%\profiles" "%DST%\profiles" >nul
echo [2/3] backing up storages ...
xcopy /E /I /Y "%SRC%\storages" "%DST%\storages" >nul
echo [3/3] backing up AGENTS.md ...
copy /Y "%SRC%\AGENTS.md" "%DST%\AGENTS.md" >nul 2>nul
echo [OK] backup finished: %DST%
:END
pause