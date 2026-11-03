[CmdletBinding()]
param(
    [string]$ConfigRoot = (Join-Path $env:USERPROFILE ".gemini\config")
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git não encontrado. Instale o Git for Windows e autentique-se no GitHub."
}

$inside = git -C $RepoRoot rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or $inside -ne "true") {
    throw "A pasta '$RepoRoot' não é um clone Git."
}

git -C $RepoRoot pull --ff-only
if ($LASTEXITCODE -ne 0) {
    throw "git pull falhou. A configuração local não foi alterada."
}

& (Join-Path $PSScriptRoot "Sync-GlobalConfig.ps1") -ConfigRoot $ConfigRoot
