[CmdletBinding()]
param(
    [string]$ConfigRoot = (Join-Path $env:USERPROFILE ".gemini\config")
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$StateRoot = Join-Path $env:LOCALAPPDATA "AntigravityGlobalSync"
$StatePath = Join-Path $StateRoot "state.json"
$BackupRoot = Join-Path $StateRoot "backups"

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

New-Item -ItemType Directory -Path $StateRoot, $BackupRoot, $ConfigRoot -Force | Out-Null

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

function Backup-Existing {
    param([string]$Path, [string]$RelativePath)

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $destination = Join-Path (Join-Path $BackupRoot $stamp) $RelativePath
    $parent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $Path -Destination $destination -Recurse -Force
    Write-Host "[BACKUP] $Path -> $destination" -ForegroundColor Yellow
}

function Restore-FromBackup {
    param([string]$BackupPath, [string]$Destination)

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Copy-Item -LiteralPath $BackupPath -Destination $Destination -Recurse -Force
}

if (Test-Path -LiteralPath $StatePath) {
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
} else {
    $state = [pscustomobject]@{ version = 1; items = [pscustomobject]@{} }
}

if ($null -eq $state.items) { $state | Add-Member -NotePropertyName items -NotePropertyValue ([pscustomobject]@{}) -Force }

$items = @()
$items += [pscustomobject]@{
    Name = "AGENTS.md"
    Source = Join-Path $RepoRoot "AGENTS.md"
    Destination = Join-Path $ConfigRoot "AGENTS.md"
    Relative = "AGENTS.md"
}
foreach ($skill in $SkillNames) {
    $items += [pscustomobject]@{
        Name = "skills/$skill"
        Source = Join-Path (Join-Path $RepoRoot "skills") $skill
        Destination = Join-Path (Join-Path $ConfigRoot "skills") $skill
        Relative = "skills\$skill"
    }
}

$conflicts = @()
foreach ($item in $items) {
    if (!(Test-Path -LiteralPath $item.Source)) {
        Write-Warning "Origem ausente no repositório: $($item.Source). Item ignorado."
        continue
    }

    if ($item.Name -like "skills/*" -and !(Test-Path -LiteralPath (Join-Path $item.Source "SKILL.md"))) {
        Write-Warning "Skill sem SKILL.md: $($item.Source). Item ignorado."
        continue
    }

    $sourceHash = Get-ItemHash -Path $item.Source
    $destinationExists = Test-Path -LiteralPath $item.Destination
    $destinationHash = if ($destinationExists) { Get-ItemHash -Path $item.Destination } else { $null }
    $previous = $state.items.PSObject.Properties[$item.Name]
    $lastHash = if ($null -ne $previous) { $previous.Value.lastSyncedHash } else { $null }

    if (!$destinationExists) {
        $parent = Split-Path -Parent $item.Destination
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item -LiteralPath $item.Source -Destination $item.Destination -Recurse
        Write-Host "[INSTALADO] $($item.Name)" -ForegroundColor Green
        $state.items | Add-Member -NotePropertyName $item.Name -NotePropertyValue ([pscustomobject]@{ lastSyncedHash = $sourceHash }) -Force
        continue
    }

    if ($destinationHash -eq $sourceHash) {
        $state.items | Add-Member -NotePropertyName $item.Name -NotePropertyValue ([pscustomobject]@{ lastSyncedHash = $sourceHash }) -Force
        Write-Host "[ATUALIZADO] $($item.Name) já está na versão do repositório." -ForegroundColor DarkGreen
        continue
    }

    if ([string]::IsNullOrWhiteSpace($lastHash)) {
        Backup-Existing -Path $item.Destination -RelativePath $item.Relative
        $conflicts += $item.Name
        Write-Warning "Conflito inicial em '$($item.Name)': destino existente diferente da origem. Backup criado; destino preservado sem sobrescrita."
        continue
    }

    if ($destinationHash -ne $lastHash) {
        Backup-Existing -Path $item.Destination -RelativePath $item.Relative
        $conflicts += $item.Name
        Write-Warning "Alteração local detectada em '$($item.Name)'. Backup criado; alteração local preservada e atualização ignorada."
        continue
    }

    # Destination still matches the last synchronized version: safe to update after backup.
    Backup-Existing -Path $item.Destination -RelativePath $item.Relative
    $parent = Split-Path -Parent $item.Destination
    $staging = "$($item.Destination).sync-staging"
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    Copy-Item -LiteralPath $item.Source -Destination $staging -Recurse
    try {
        Remove-Item -LiteralPath $item.Destination -Recurse -Force
        Move-Item -LiteralPath $staging -Destination $item.Destination
        $state.items | Add-Member -NotePropertyName $item.Name -NotePropertyValue ([pscustomobject]@{ lastSyncedHash = $sourceHash }) -Force
        Write-Host "[ATUALIZADO] $($item.Name)" -ForegroundColor Green
    } catch {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
        throw "Falha ao atualizar '$($item.Name)'. O backup foi preservado. Erro: $_"
    }
}

$state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $StatePath -Encoding UTF8

if ($conflicts.Count -gt 0) {
    Write-Warning ("Sincronização terminou com conflitos: " + ($conflicts -join ", "))
    Write-Warning "Os destinos em conflito foram preservados. Consulte backups em '$BackupRoot'."
}

if ($conflicts.Count -eq 0) {
    Write-Host "Sincronização concluída sem conflitos." -ForegroundColor Cyan
}
