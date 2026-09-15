@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "GODOT="
if defined GODOT_PATH set "GODOT=%GODOT_PATH%"
if not defined GODOT for %%F in (Godot_v4.7.2-stable_win64.exe) do if exist "%%~fF" set "GODOT=%%~fF"
if not defined GODOT (
  for /f "delims=" %%I in ('where godot 2^>nul') do if not defined GODOT set "GODOT=%%I"
)
if not defined GODOT (
  echo Godot не найден. Запустите setup.bat или задайте переменную GODOT_PATH
  echo ^(путь к Godot_v4.7.2-stable_win64.exe, можно с пробелами^).
  exit /b 1
)

echo Запуск карты-полигона: "%GODOT%" --path . res://scenes/maps/bench.tscn
echo WASD - движение, мышь - обзор, ЛКМ - огонь, R - перезарядка, Ctrl - присед, Esc - курсор.
echo.
"%GODOT%" --path . "res://scenes/maps/bench.tscn" %*
echo.
echo Игра закрылась. Если окно пропало мгновенно - запустите test_all.bat, он покажет ошибку.
endlocal
