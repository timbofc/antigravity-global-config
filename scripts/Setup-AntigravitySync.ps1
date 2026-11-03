[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^https://github\.com/.+/.+(\.git)?$")]
    [string]$RepositoryUrl,

    [string]$ConfigRoot = (Join-Path $env:USERPROFILE ".gemini\config"),

    [int]$EveryHours = 4
)

$ErrorActionPreference = "Stop"
$StateRoot = Join-Path $env:LOCALAPPDATA "AntigravityGlobalSync"
$RepoRoot = Join-Path $StateRoot "repo"

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git não encontrado. Instale Git for Windows antes de continuar."
}

New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null

if (Test-Path -LiteralPath $RepoRoot) {
    $isRepo = git -C $RepoRoot rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $isRepo -ne "true") {
        throw "Já existe '$RepoRoot', mas não é um clone Git. Renomeie ou faça backup manual antes de continuar."
    }
    git -C $RepoRoot remote set-url origin $RepositoryUrl
    if ($LASTEXITCODE -ne 0) { throw "Não foi possível configurar o remote origin." }
    git -C $RepoRoot pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw "Não foi possível atualizar o repositório. Nenhum arquivo global foi alterado." }
} else {
    git clone $RepositoryUrl $RepoRoot
    if ($LASTEXITCODE -ne 0) { throw "Clone falhou. Verifique URL, acesso privado e autenticação GitHub." }
}

& (Join-Path $RepoRoot "scripts\Sync-GlobalConfig.ps1") -ConfigRoot $ConfigRoot

& (Join-Path $RepoRoot "scripts\Register-AutoSync.ps1")

Write-Host "`nConfiguração concluída." -ForegroundColor Cyan
Write-Host "Clone: $RepoRoot"
Write-Host "Configuração Antigravity: $ConfigRoot"
Write-Host "Tarefa: AntigravityGlobalConfigSync"
