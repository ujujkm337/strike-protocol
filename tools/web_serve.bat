@echo off
REM Запуск веб-сборки Strike Protocol. Python 3 нужен (обычно уже стоит).
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  py serve.py %*
) else (
  python serve.py %*
)
if %errorlevel% neq 0 (
  echo.
  echo Не нашёл Python. Поставь python.org/downloads ^(галочка "Add to PATH"^) и повтори.
  pause
)
