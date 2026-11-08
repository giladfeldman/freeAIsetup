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
echo Press any key to close this window.
pause >nul
exit /b 3
