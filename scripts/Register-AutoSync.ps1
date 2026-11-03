[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Updater = Join-Path $PSScriptRoot "Update-GlobalConfig.ps1"
$CurrentUser = "$env:USERDOMAIN\$env:USERNAME"

if (!(Test-Path -LiteralPath $Updater)) {
    throw "Script de atualização não encontrado: $Updater"
}

$PowerShell = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
if (!$PowerShell) {
    $PowerShell = (Get-Command pwsh.exe -ErrorAction Stop).Source
}

$arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Updater`""
$action = New-ScheduledTaskAction -Execute $PowerShell -Argument $arguments -WorkingDirectory $RepoRoot

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

# Registrar duas tarefas separadas evita ambiguidades entre conjuntos de parâmetros.
$tasks = @(
    @{
        Name = "AntigravityGlobalConfigSync-Logon"
        Trigger = (New-ScheduledTaskTrigger -AtLogOn -User $CurrentUser)
        Description = "Sincroniza as regras e skills globais do Antigravity ao entrar no Windows."
    },
    @{
        Name = "AntigravityGlobalConfigSync-Daily"
        Trigger = (New-ScheduledTaskTrigger -Daily -At "08:00")
        Description = "Sincroniza diariamente as regras e skills globais do Antigravity."
    }
)

foreach ($task in $tasks) {
    Register-ScheduledTask `
        -TaskName $task.Name `
        -Action $action `
        -Trigger $task.Trigger `
        -Settings $settings `
        -Description $task.Description `
        -User $CurrentUser `
        -RunLevel Limited `
        -Force | Out-Null

    Write-Host "[REGISTRADA] $($task.Name)" -ForegroundColor Green
}

Write-Host "`nSincronização automática configurada:" -ForegroundColor Cyan
Write-Host "- Ao entrar no Windows"
Write-Host "- Diariamente às 08:00"
