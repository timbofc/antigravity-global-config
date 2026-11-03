[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigRoot = (Join-Path $env:USERPROFILE ".gemini\config")
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$SkillNames = @(
    "brainstorming",
    "systematic-debugging",
    "backend-architect",
    "code-review-and-quality",
    "test-driven-development",
    "security-and-hardening",
    "api-and-interface-design",
    "prisma-expert",
    "postgres-best-practices"
)

function Copy-ToRepoSafely {
    param([string]$Source, [string]$Destination)

    if (!(Test-Path -LiteralPath $Source)) {
        throw "Origem não encontrada: $Source"
    }

    if (Test-Path -LiteralPath $Destination) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupRoot = Join-Path $RepoRoot ".publish-backups\$stamp"
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        $backupPath = Join-Path $backupRoot ([IO.Path]::GetFileName($Destination))
        Copy-Item -LiteralPath $Destination -Destination $backupPath -Recurse -Force
        throw "Destino já existe. Backup criado em '$backupPath'. Nada foi sobrescrito. Revise/mescle manualmente e rode novamente após remover ou renomear o destino do repositório."
    }

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse
    Write-Host "[PUBLICADO] $Destination" -ForegroundColor Green
}

$sourceAgents = Join-Path $ConfigRoot "AGENTS.md"
$destAgents = Join-Path $RepoRoot "AGENTS.md"
if (Test-Path -LiteralPath $destAgents) {
    Write-Host "[PRESERVADO] O repositório já contém AGENTS.md. Compare com '$sourceAgents' e faça a mesclagem manual se necessário." -ForegroundColor Yellow
} else {
    Copy-ToRepoSafely -Source $sourceAgents -Destination $destAgents
}

$skillsRoot = Join-Path $ConfigRoot "skills"
$repoSkillsRoot = Join-Path $RepoRoot "skills"
New-Item -ItemType Directory -Path $repoSkillsRoot -Force | Out-Null

foreach ($name in $SkillNames) {
    $source = Join-Path $skillsRoot $name
    $destination = Join-Path $repoSkillsRoot $name

    if (!(Test-Path -LiteralPath (Join-Path $source "SKILL.md"))) {
        Write-Warning "Skill '$name' não encontrada em '$source'; ignorada."
        continue
    }

    if (Test-Path -LiteralPath $destination) {
        Write-Warning "Skill '$name' já existe no repositório. Não foi sobrescrita."
        continue
    }

    Copy-Item -LiteralPath $source -Destination $destination -Recurse
    Write-Host "[PUBLICADA] skill $name" -ForegroundColor Green
}

Write-Host "`nPublicação concluída. Revise o diff antes de enviar ao GitHub." -ForegroundColor Cyan
