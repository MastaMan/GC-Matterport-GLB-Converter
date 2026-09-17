:: Denoiser
:: 1.0.0
:: Vasyl Lukianenko 
:: 3DGROUND
:: https://3dground.net

echo off
cls

set input=%1
set version=
set file=

for /f "tokens=1,2,3 delims=;" %%i in (%input%) do (
	set version=%%i
	set file="%%j"
)

set vdenoise="c:\ProgramData\Autodesk\ApplicationPlugins\VRay3dsMax%version%\bin\vdenoise.exe"
set pth=%~dp0
set config="%pth%vdenoise.xml"

if exist "%vdenoise%" (
	if exist %file% (
		%vdenoise% -inputFile=%file% -configFile=%config% -autoClose=1
	)
)

