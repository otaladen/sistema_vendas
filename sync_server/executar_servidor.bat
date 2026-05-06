@echo off
REM Inicia o servidor de sync na porta 8787 (ou passe outra: executar_servidor.bat 9000)
cd /d "%~dp0"
set PORT_ARG=%1
if "%PORT_ARG%"=="" set PORT_ARG=8787

if exist sistema_vendas_sync_server.exe (
  sistema_vendas_sync_server.exe %PORT_ARG%
) else (
  echo Executavel nao encontrado. Rode antes: build_windows_exe.bat
  pause
  exit /b 1
)
