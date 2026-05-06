# Cria tarefa agendada para iniciar o servidor de sync ao logar no Windows.
# Execute no PowerShell COMO ADMINISTRADOR (botao direito -> Executar como administrador).
# Ajuste $Porta se precisar.

$Porta = 8787
$Raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$Exe = Join-Path $Raiz "sistema_vendas_sync_server.exe"

if (-not (Test-Path $Exe)) {
    Write-Host "ERRO: Nao encontrado: $Exe"
    Write-Host "Rode antes build_windows_exe.bat nesta pasta."
    exit 1
}

$NomeTarefa = "SistemaVendas_SyncServer"
Unregister-ScheduledTask -TaskName $NomeTarefa -Confirm:$false -ErrorAction SilentlyContinue

$Acao = New-ScheduledTaskAction -Execute $Exe -Argument "$Porta" -WorkingDirectory $Raiz
$Disparador = New-ScheduledTaskTrigger -AtLogOn
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$Config = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $NomeTarefa -Action $Acao -Trigger $Disparador -Principal $Principal -Settings $Config -Description "Servidor LAN sistema_vendas (sync)"

Write-Host "Tarefa criada: $NomeTarefa (inicia ao logar, porta $Porta)"
Write-Host "Gerenciar: taskschd.msc -> Biblioteca do Agendador de Tarefas"
