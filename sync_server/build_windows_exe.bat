@echo off
REM Gera sistema_vendas_sync_server.exe na mesma pasta deste script.
cd /d "%~dp0"
where dart >nul 2>&1
if errorlevel 1 (
  echo Coloque o Dart SDK no PATH ou abra o "Dart SDK" prompt.
  exit /b 1
)
call dart pub get
call dart compile exe bin\sync_server.dart -o sistema_vendas_sync_server.exe
if errorlevel 1 exit /b 1
echo.
echo OK: sistema_vendas_sync_server.exe criado em %cd%
exit /b 0
