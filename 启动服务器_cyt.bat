@echo off
setlocal EnableExtensions

REM Keep this file ASCII-only. Some Windows code pages will garble non-ASCII
REM characters (e.g., Chinese filenames) inside .bat, causing invalid paths.
chcp 65001 >nul

set "SCRIPT_DIR=%~dp0"
set "PS1_SCRIPT="

REM Find the PowerShell launcher in the same folder (avoid hard-coded filename).
for %%F in ("%SCRIPT_DIR%*.ps1") do (
	set "PS1_SCRIPT=%%~fF"
	goto :found
)

echo ERROR: No .ps1 launcher found in: "%SCRIPT_DIR%"
echo Expected a file like "启动服务器_*.ps1" next to this .bat.
exit /b 1

:found
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%"

endlocal
