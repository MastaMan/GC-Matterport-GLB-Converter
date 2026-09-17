:: GLTF Packer - WebGL
:: Based on GC Tools 1.0.0 by Vasyl Lukianenko / 3DGROUND
:: https://3dground.net
:: Converter adaptation: input;output;LOD texture cap, checked exit, caller-owned cleanup.
@echo off
setlocal DisableDelayedExpansion
set "input=%~1"
set "gltf="
set "glb="
set "textureLimit="
for /f "tokens=1,2,3 delims=;" %%i in ("%input%") do (
	set "gltf=%%i"
	set "glb=%%j"
	set "textureLimit=%%k"
)
if not defined gltf exit /b 2
if not defined glb exit /b 2
set "validLimit="
for %%n in (512 1024 2048 4096) do if "%textureLimit%"=="%%n" set "validLimit=1"
if not defined validLimit exit /b 2
if not exist "%gltf%" exit /b 2
if not exist "%~dp0gltfpack.exe" exit /b 2
:: Export for Light WebGL: original GC Tools flags, with the per-LOD cap.
"%~dp0gltfpack.exe" -noq -vtf -vnf -vpf -vc 16 -vn 16 -vp 16 -vt 16 -tc -tl %textureLimit% -i "%gltf%" -o "%glb%" > "%glb%.log" 2>&1
set "packExit=%errorlevel%"
if not "%packExit%"=="0" exit /b %packExit%
if not exist "%glb%" exit /b 3
exit /b 0
