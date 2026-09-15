@echo off
setlocal
cd /d "%~dp0"
set VER=4.7.2
set NAME=Godot_v%VER%-stable_win64.exe
set URL=https://github.com/godotengine/godot/releases/download/%VER%-stable/%NAME%

where godot >nul 2>nul
if %errorlevel%==0 (
  echo Godot найден в PATH:
  godot --version
  goto :py
)
if exist "%~dp0%NAME%" (
  echo Godot уже лежит в папке проекта: %NAME%
  goto :py
)
echo.
echo Godot не найден. Скачайте вручную (это один .exe, ~50 МБ, без установки):
echo   %URL%
echo Положите файл в папку проекта ^(рядом с setup.bat^) и запустите setup.bat снова.
echo Либо установите через winget:
echo   winget install GodotEngine.Godot
exit /b 1

:py
where py >nul 2>nul
if %errorlevel%==0 (
  py -m pip install -q -r tools\requirements.txt
  echo Python OK
) else (
  echo Python не найден ^(нужен для tools\*.py^). Godot для запуска игры это не блокирует.
)
echo.
echo Готово. Дальше: run_bench.bat -быстрый старт карты-полигона- или просто
echo откройте project.godot двойным кликом и нажмите F5.
endlocal
