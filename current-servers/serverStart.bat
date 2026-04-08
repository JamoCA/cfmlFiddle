@echo off
rem CommandBox server startup menu
rem Place this file in the same directory as your server.*.json config files.
pushd %~dp0

:MENU
cls
echo.
echo  ============================================
echo   CommandBox Server Startup
echo  ============================================
echo.
echo   ColdFusion
echo   ----------
echo   [1]  CF 2016
echo   [2]  CF 2021
echo   [3]  CF 2023
echo   [4]  CF 2025
echo.
echo   Lucee
echo   -----
echo   [5]  Lucee 5
echo   [6]  Lucee 6
echo   [7]  Lucee 7
echo   [8]  Lucee Light
echo.
echo   [0]  Exit
echo.
set /p CHOICE=  Select server to start:

if "%CHOICE%"=="1" set CONFIG=cf2016
if "%CHOICE%"=="2" set CONFIG=cf2021
if "%CHOICE%"=="3" set CONFIG=cf2023
if "%CHOICE%"=="4" set CONFIG=cf2025
if "%CHOICE%"=="5" set CONFIG=lucee5
if "%CHOICE%"=="6" set CONFIG=lucee6
if "%CHOICE%"=="7" set CONFIG=lucee7
if "%CHOICE%"=="8" set CONFIG=luceelight
if "%CHOICE%"=="0" goto END

if not defined CONFIG (
    echo.
    echo   Invalid selection. Press any key to try again.
    pause >nul
    set CONFIG=
    goto MENU
)

:START
echo.
echo   Starting server with config: server.%CONFIG%.json
echo.
cd /D c:\commandbox\ && server start serverConfigFile=%~dp0server.%CONFIG%.json
goto END

:END
set CONFIG=
popd
