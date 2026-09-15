@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
set "GODOT="
if defined GODOT_PATH set "GODOT=%GODOT_PATH%"
if not defined GODOT for %%F in (Godot_v4.7.2-stable_win64.exe) do if exist "%%~fF" set "GODOT=%%~fF"
if not defined GODOT (
  for /f "delims=" %%I in ('where godot 2^>nul') do if not defined GODOT set "GODOT=%%I"
)
if not defined GODOT ( echo Godot не найден - сначала setup.bat & exit /b 1 )

set "FAIL=0"
for %%t in (ballistics movement bench assets play_session menu_runtime) do (
  echo.
  echo --- test_%%t ---
  "%GODOT%" --headless --path . -s "tests\test_%%t.gd" >"%TEMP%\gt_%%t.log" 2>&1
  findstr /r /c:"ИТОГ" /c:"^битых" /c:"^сцен" "%TEMP%\gt_%%t.log"
  findstr /r /c:"FAIL" "%TEMP%\gt_%%t.log" >nul && set "FAIL=1"
)
echo.
if "%FAIL%"=="0" (echo === ВСЕ ТЕСТЫ ЗЕЛЁНЫЕ ===) else (echo === ЕСТЬ ПАДЕНИЯ, см. вывод выше ===)
endlocal
