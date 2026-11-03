[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Updater = Join-Path $PSScriptRoot "Update-GlobalConfig.ps1"
$TaskName = "AntigravityGlobalConfigSync"
$CurrentUser = "$env:USERDOMAIN\$env:USERNAME"

if (!(Test-Path -LiteralPath $Updater)) { throw "Script de atualização não encontrado: $Updater" }

$PowerShell = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
if (!$PowerShell) { $PowerShell = (Get-Command pwsh.exe -ErrorAction Stop).Source }

$arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Updater`""
$action = New-ScheduledTaskAction -Execute $PowerShell -Argument $arguments -WorkingDirectory $RepoRoot
$logon = New-ScheduledTaskTrigger -AtLogOn -User $CurrentUser
$daily = New-ScheduledTaskTrigger -Daily -At "08:00"

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

$principal = New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType Interactive -RunLevel Limited
$task = New-ScheduledTask -Action $action -Trigger @($logon, $daily) -Settings $settings -Principal $principal

Register-ScheduledTask -TaskName $TaskName -InputObject $task `
    -Description "Atualiza regras e skills globais do Antigravity a partir do repositório Git privado." `
    -Force | Out-Null

Write-Host "Tarefa '$TaskName' registrada para $CurrentUser." -ForegroundColor Green
Write-Host "Execução ao entrar no Windows e diariamente às 08:00." -ForegroundColor Cyan
