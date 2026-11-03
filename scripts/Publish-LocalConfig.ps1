[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    [string]$ConfigRoot = (Join-Path $env:USERPROFILE ".gemini\config"),
    [string]$CommitMessage = ("Atualiza configuração global - " + (Get-Date -Format "yyyy-MM-dd HH:mm"))
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$StateRoot = Join-Path $env:LOCALAPPDATA "AntigravityGlobalSync"
$StatePath = Join-Path $StateRoot "state.json"
$BackupRoot = Join-Path $StateRoot "publish-backups"

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

function Invoke-Git {
    param([string[]]$GitArguments, [switch]$AllowFailure)

    $output = & git -C $RepoRoot @GitArguments 2>&1
    $code = $LASTEXITCODE
    if ($output) { $output | ForEach-Object { Write-Host $_ } }
    if ($code -ne 0 -and !$AllowFailure) {
        throw "Comando Git falhou (código $code): git $($GitArguments -join ' ')"
    }
    return $code
}

function Get-ItemHash {
    param([string]$Path)

    if (!(Test-Path -LiteralPath $Path)) { return $null }

    if ((Get-Item -LiteralPath $Path).PSIsContainer) {
        $root = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
        $entries = Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object {
            $_.FullName.Substring($root.Length).ToLowerInvariant()
        }
        $parts = foreach ($file in $entries) {
            $relative = $file.FullName.Substring($root.Length).TrimStart('\').ToLowerInvariant()
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            "$relative|$hash"
        }
        $joined = [string]::Join("`n", [string[]]$parts)
        $bytes = [Text.Encoding]::UTF8.GetBytes($joined)
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "")
        } finally {
            $sha.Dispose()
        }
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Backup-Item {
    param([string]$Path, [string]$RelativePath)

    if (!(Test-Path -LiteralPath $Path)) { return }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $destination = Join-Path (Join-Path $BackupRoot $stamp) $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $Path -Destination $destination -Recurse -Force
    Write-Host "[BACKUP] $Path -> $destination" -ForegroundColor Yellow
}

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git não encontrado. Instale o Git for Windows."
}
if (!(Test-Path -LiteralPath $StatePath)) {
    throw "Estado local não encontrado: $StatePath. Execute primeiro a sincronização inicial."
}
if (!(Test-Path -LiteralPath $RepoRoot)) {
    throw "Clone do repositório não encontrado: $RepoRoot"
}

$inside = & git -C $RepoRoot rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or $inside -ne "true") {
    throw "A pasta '$RepoRoot' não é um clone Git."
}

$state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $state.items) {
    throw "O state.json não contém o mapa de itens sincronizados."
}

# Não misturar alterações manuais no clone com a publicação das configurações.
$status = & git -C $RepoRoot status --porcelain
if ($LASTEXITCODE -ne 0) { throw "Não foi possível consultar o estado do Git." }
if ($status) {
    Write-Host $status
    throw "O clone possui alterações locais pendentes. Faça commit, descarte ou resolva essas alterações antes de publicar."
}

Write-Host "`n[1/4] Buscando atualizações do GitHub..." -ForegroundColor Cyan
Invoke-Git -GitArguments @("pull", "--ff-only")

$items = @(
    [pscustomobject]@{
        Name = "AGENTS.md"
        Source = Join-Path $ConfigRoot "AGENTS.md"
        Destination = Join-Path $RepoRoot "AGENTS.md"
        Relative = "AGENTS.md"
    }
)
foreach ($skill in $SkillNames) {
    $items += [pscustomobject]@{
        Name = "skills/$skill"
        Source = Join-Path (Join-Path $ConfigRoot "skills") $skill
        Destination = Join-Path (Join-Path $RepoRoot "skills") $skill
        Relative = "skills/$skill"
    }
}

$toPublish = @()
$conflicts = @()

Write-Host "`n[2/4] Comparando alterações locais com a última sincronização..." -ForegroundColor Cyan

foreach ($item in $items) {
    if (!(Test-Path -LiteralPath $item.Source)) {
        Write-Warning "Configuração local ausente: $($item.Name). Item ignorado."
        continue
    }
    if ($item.Name -like "skills/*" -and !(Test-Path -LiteralPath (Join-Path $item.Source "SKILL.md"))) {
        Write-Warning "Skill sem SKILL.md: $($item.Name). Item ignorado."
        continue
    }

    $localHash = Get-ItemHash $item.Source
    $repoHash = Get-ItemHash $item.Destination
    $entry = $state.items.PSObject.Properties[$item.Name]
    $baseline = if ($null -ne $entry) { $entry.Value.lastSyncedHash } else { $null }

    if ($null -eq $repoHash) {
        $conflicts += "$($item.Name) (ausente no repositório)"
        Write-Warning "Conflito: '$($item.Name)' não existe no repositório."
        continue
    }

    if ($localHash -eq $repoHash) {
        Write-Host "[IGUAL] $($item.Name)" -ForegroundColor DarkGreen
        continue
    }

    if ([string]::IsNullOrWhiteSpace($baseline)) {
        $conflicts += "$($item.Name) (sem histórico-base)"
        Write-Warning "Conflito inicial em '$($item.Name)': não existe hash-base para decidir qual versão prevalece."
        continue
    }

    $localChanged = $localHash -ne $baseline
    $repoChanged = $repoHash -ne $baseline

    if ($localChanged -and !$repoChanged) {
        $toPublish += $item
        Write-Host "[PUBLICAR] Alteração somente local: $($item.Name)" -ForegroundColor Yellow
    }
    elseif (!$localChanged -and $repoChanged) {
        Write-Host "[REMOTO] '$($item.Name)' mudou no GitHub; será recebido pela sincronização." -ForegroundColor Cyan
    }
    else {
        $conflicts += $item.Name
        Write-Warning "Conflito em '$($item.Name)': houve alterações locais e remotas desde a última sincronização."
    }
}

if ($conflicts.Count -gt 0) {
    throw ("Publicação bloqueada. Resolva os conflitos antes de continuar: " + ($conflicts -join ", "))
}

if ($toPublish.Count -eq 0) {
    Write-Host "`nNenhuma alteração local precisa ser publicada." -ForegroundColor Green
    Write-Host "Se houver atualizações remotas, execute Update-GlobalConfig.ps1 para recebê-las."
    return
}

Write-Host "`n[3/4] Preparando publicação..." -ForegroundColor Cyan
foreach ($item in $toPublish) {
    if (!$PSCmdlet.ShouldProcess($item.Name, "Fazer backup e copiar configuração local para o clone Git")) {
        continue
    }

    Backup-Item -Path $item.Destination -RelativePath $item.Relative
    if (Test-Path -LiteralPath $item.Destination) {
        Remove-Item -LiteralPath $item.Destination -Recurse -Force
    }
    $parent = Split-Path -Parent $item.Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $item.Source -Destination $item.Destination -Recurse
}

if ($WhatIfPreference) {
    Write-Host "`nSimulação concluída. Nenhum commit ou push foi realizado." -ForegroundColor Yellow
    return
}

Write-Host "`n[4/4] Criando commit e enviando ao GitHub..." -ForegroundColor Cyan
$paths = @($toPublish | ForEach-Object { $_.Relative })
Invoke-Git -GitArguments (@("add", "--") + $paths)
$staged = & git -C $RepoRoot diff --cached --quiet
$diffCode = $LASTEXITCODE
if ($diffCode -eq 0) {
    Write-Host "Nenhuma diferença staged. Nada para publicar." -ForegroundColor Green
    return
}
if ($diffCode -ne 1) { throw "Não foi possível verificar as alterações staged." }

Invoke-Git -GitArguments @("commit", "-m", $CommitMessage)
Invoke-Git -GitArguments @("push")

Write-Host "`nPublicação enviada ao GitHub. Atualizando o estado local..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "Sync-GlobalConfig.ps1") -ConfigRoot $ConfigRoot

Write-Host "`nPublicação concluída." -ForegroundColor Green
