@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "GC_RELEASE_ARGUMENT="
if "%~1"=="" goto run_release
if /I "%~1"=="--check-only" goto check_only

echo Unknown argument: %~1
echo Usage: %~nx0 [--check-only]
exit /b 2

:check_only
set "GC_RELEASE_ARGUMENT=-CheckOnly"

:run_release
if not exist "%~dp0release-github.ps1" (
	echo release-github.ps1 was not found next to this BAT.
	exit /b 2
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0release-github.ps1" %GC_RELEASE_ARGUMENT%
set "GC_RELEASE_RESULT=%ERRORLEVEL%"

echo.
if not "%GC_RELEASE_NO_PAUSE%"=="1" pause
endlocal & exit /b %GC_RELEASE_RESULT%
