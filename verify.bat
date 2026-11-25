@echo off
rem ---------------------------------------------------------------
rem songquery-flutter health check launcher (double-click friendly)
rem   verify.bat           analyze + test + apk content
rem   verify.bat --build   also rebuild the arm64 release apk
rem Real logic lives in tool\verify.py: cmd label/errorlevel chains
rem cannot be self-tested, python can.
rem Comments stay English on purpose -- cmd swallows UTF-8 in rem.
rem ---------------------------------------------------------------
setlocal
cd /d "%~dp0"

set "PY="
if exist "C:\Users\Tsumugi\.workbuddy\binaries\python\versions\3.13.12\python.exe" set "PY=C:\Users\Tsumugi\.workbuddy\binaries\python\versions\3.13.12\python.exe"
if defined PY goto :run
rem "where python" is not enough: the Store alias resolves but does nothing.
where python >nul 2>nul
if errorlevel 1 goto :try_launcher
python -c "import sys" >nul 2>nul
if errorlevel 1 goto :try_launcher
set "PY=python"
goto :run
:try_launcher
where py >nul 2>nul
if errorlevel 1 goto :no_python
py -3 -c "import sys" >nul 2>nul
if errorlevel 1 goto :no_python
set "PY=py -3"
goto :run

:no_python
echo [ERROR] python not found -- install python or set FLUTTER/PYTHON PATH
if not defined SQ_NO_PAUSE pause
exit /b 1

:run
%PY% tool\verify.py %*
set "CODE=%ERRORLEVEL%"
if not defined SQ_NO_PAUSE pause
exit /b %CODE%
