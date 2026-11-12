@echo off
rem MetaScience course setup for Windows: double-click this file.
cd /d "%~dp0"
if not exist "%~dp0setup-windows.ps1" (
  echo.
  echo  The setup files are still inside the zip file.
  echo  Close this window. Right-click metascience-setup.zip, choose "Extract All...", click Extract,
  echo  then open the new folder student-setup and double-click install-windows.cmd there.
  echo.
  echo Press any key to close this window.
  pause >nul
  exit /b 2
)
rem Files from a downloaded zip are marked "from the internet"; unmark this folder's own files so Windows runs them.
set "MS_DIR=%~dp0"
powershell -NoProfile -Command "Get-ChildItem -LiteralPath $env:MS_DIR -Recurse -File | Unblock-File" >nul 2>&1
rem An organisation can forbid scripts on its computers (group policy). Then this setup cannot run here.
set "MS_POL="
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "$p = Get-ExecutionPolicy -Scope MachinePolicy; if ($p -eq 'Undefined') { $p = Get-ExecutionPolicy -Scope UserPolicy }; $p"`) do set "MS_POL=%%p"
if /i "%MS_POL%"=="AllSigned" goto managed
if /i "%MS_POL%"=="Restricted" goto managed
rem -Uninstall removes this folder, and with it this file: work outside it (Windows cannot delete a folder a window
rem works in); the uninstaller deletes the folder only after this cmd has ended (MS_FROM_CMD).
rem -Uninstall may come anywhere among the words after the file name, not only first.
set "MS_UNINSTALL="
for %%a in (%*) do if /i "%%~a"=="-Uninstall" set "MS_UNINSTALL=1"
if defined MS_UNINSTALL (
  cd /d "%TEMP%"
  set "MS_FROM_CMD=1"
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-windows.ps1" %*
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-windows.ps1" %*
set "MS_RC=%ERRORLEVEL%"
echo.
echo Press any key to close this window.
pause >nul
exit /b %MS_RC%

:managed
echo.
echo  This computer is managed by an organisation (for example a university or employer), and its
echo  rules forbid running setup scripts (PowerShell policy: %MS_POL%).
echo  Please use your own laptop for the course, or ask the computer's IT support to install:
echo  Git, Node.js, uv, R, RStudio, Quarto and OpenCode. Show this message to the teacher.
echo.
rem The teacher's log box hears about this stop too (with a yes). The policy forbids script files, not this command.
set "MS_SEND="
set /p MS_SEND=  Send a short report to your teacher, so they can see what went wrong? It contains no passwords and no names. [Y/n]
if /i "%MS_SEND%"=="n" goto managed_end
if /i "%MS_SEND%"=="no" goto managed_end
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $b = '== installer (install-windows.cmd) ==' + [char]10 + 'FAIL  Managed computer  PowerShell policy %MS_POL% forbids setup scripts'; $u = if ($env:MS_LOG_URL) { $env:MS_LOG_URL.TrimEnd('/') } else { 'https://freeaisetup-logs.giladfel.workers.dev' }; $h = @{ 'x-freeaisetup' = '1' }; if ($env:MS_LOG_ENV) { $h['x-freeaisetup-env'] = $env:MS_LOG_ENV }; try { $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri ($u + '/upload?platform=windows&version=zip&result=failed') -Headers $h -Body $b -TimeoutSec 60; Write-Host ('  Sent. Your code is ' + ([string]$r.Content).Trim() + '. Tell your teacher this code.') } catch { Write-Host '  Could not send it (no internet?). Show this window to your teacher instead.' }"
:managed_end
echo.
echo Press any key to close this window.
pause >nul
exit /b 3
