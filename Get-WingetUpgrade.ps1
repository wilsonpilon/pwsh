#Requires -Version 5.1
<#
.SYNOPSIS
    Lists and upgrades all outdated packages via winget, logging the process.
.DESCRIPTION
    Runs 'winget upgrade' to detect outdatable packages, shows a summary,
    then upgrades each one individually while writing a timestamped log file.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Log file in user's temp folder
$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$logFile   = Join-Path $env:TEMP "WingetUpgrade_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Color = 'White')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Message"

    try {
        Write-Host $line -ForegroundColor $Color
    } catch {
        Write-Host $line
    }

    $logDir = Split-Path -Path $logFile -Parent
    if ($logDir -and -not (Test-Path -Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

function Get-UpgradeList {
    Write-Log "Consultando pacotes disponiveis para upgrade..." 'Cyan'

    $raw = @(winget update --include-unknown 2>&1)
    $lines = @()

    foreach ($item in $raw) {
        if ($null -eq $item) { continue }
        $lines += [string]$item
    }

    if ($lines.Count -eq 0) {
        Write-Log "Nao foi possivel obter a saida do winget." 'Red'
        return @()
    }

    $headerIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(?i)\b(Nome|Name)\b' -and $lines[$i] -match '(?i)\b(ID|Id)\b') {
            $headerIndex = $i
            break
        }
    }

    if ($headerIndex -lt 0) {
        Write-Log "Cabecalho da tabela do winget nao encontrado." 'Red'
        return @()
    }

    $headerLine = $lines[$headerIndex]
    $headerColumns = @($headerLine -split '\s{2,}') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    $idColumnIndex = -1

    for ($j = 0; $j -lt $headerColumns.Count; $j++) {
        if ($headerColumns[$j] -match '(?i)^ID$') {
            $idColumnIndex = $j
            break
        }
    }

    if ($idColumnIndex -lt 0 -or ($idColumnIndex + 1) -ge $headerColumns.Count) {
        Write-Log "Nao foi possivel localizar a coluna de ID." 'Red'
        return @()
    }

    $nextHeader = $headerColumns[$idColumnIndex + 1]
    $idStart = $headerLine.IndexOf('ID', [System.StringComparison]::OrdinalIgnoreCase)
    $nextStart = $headerLine.IndexOf($nextHeader, [System.StringComparison]::OrdinalIgnoreCase)
    if ($nextStart -lt 0) { $nextStart = $headerLine.Length }

    $ids = @()

    for ($i = $headerIndex + 2; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()

        if ($trimmed -eq '') { continue }
        if ($trimmed -match '^[-\s]{10,}$') { continue }
        if ($trimmed -match '^\d+\s+' -and ($trimmed -match 'atualiz|upgrade|available|dispon|pacotes?')) { break }

        if ($trimmed.Length -le $idStart) { continue }

        $idEnd = [Math]::Min($nextStart, $trimmed.Length)
        $idValue = $trimmed.Substring($idStart, $idEnd - $idStart).Trim()

        if ($idValue -and $idValue -notmatch '^(Nome|Name|Vers[ãa]o|Version|Dispon[ií]vel|Available|Origem|Source)$' -and $idValue -match '^[A-Za-z0-9][A-Za-z0-9\.\-\+_]*$') {
            $ids += $idValue
        }
    }

    return @($ids | Select-Object -Unique)
}

# ─── MAIN ────────────────────────────────────────────────────────────────────

Write-Log "=== Get-WingetUpgrade iniciado ===" 'Yellow'
Write-Log "Log: $logFile" 'DarkGray'
Write-Host ""

$upgradeIds = @(Get-UpgradeList)

if ($upgradeIds.Count -eq 0) {
    Write-Log "Nenhum pacote precisa de upgrade. Tudo atualizado!" 'Green'
    Write-Log "=== Concluido ===" 'Yellow'
    Write-Host "`nLog salvo em: $logFile" -ForegroundColor DarkGray
    exit 0
}

# Summary
Write-Host ""
Write-Log "─── RESUMO ───────────────────────────────────────────" 'Cyan'
Write-Log "$($upgradeIds.Count) pacote(s) serao atualizados:" 'Cyan'
foreach ($id in $upgradeIds) {
    Write-Log "  • $id" 'White'
}
Write-Log "──────────────────────────────────────────────────────" 'Cyan'
Write-Host ""

$confirm = Read-Host "Deseja prosseguir com o upgrade de todos os pacotes? (S/N)"
if ($confirm -notmatch '^[Ss]') {
    Write-Log "Operacao cancelada pelo usuario." 'Yellow'
    Write-Log "=== Concluido ===" 'Yellow'
    Write-Host "`nLog salvo em: $logFile" -ForegroundColor DarkGray
    exit 0
}

Write-Host ""

# Upgrade one by one
$success = 0
$failed  = @()

for ($i = 0; $i -lt $upgradeIds.Count; $i++) {
    $id      = $upgradeIds[$i]
    $current = $i + 1
    $total   = $upgradeIds.Count

    Write-Host ""
    Write-Log "[$current/$total] Atualizando: $id" 'Cyan'
    Write-Log "──────────────────────────────────────────────────────" 'DarkGray'

    # Stream winget output live to console and log
    $exitCode = 0
    $proc = Start-Process -FilePath 'winget' `
        -ArgumentList "upgrade --id `"$id`" --accept-source-agreements --accept-package-agreements" `
        -NoNewWindow -Wait -PassThru

    $exitCode = $proc.ExitCode

    if ($exitCode -eq 0) {
        Write-Log "[$current/$total] OK: $id atualizado com sucesso." 'Green'
        $success++
    } else {
        Write-Log "[$current/$total] FALHA: $id (exit code $exitCode)" 'Red'
        $failed += $id
    }
}

# Final report
Write-Host ""
Write-Log "══════════════════════════════════════════════════════" 'Yellow'
Write-Log "RESULTADO FINAL" 'Yellow'
Write-Log "  Total  : $($upgradeIds.Count)" 'White'
Write-Log "  Sucesso: $success" 'Green'
Write-Log "  Falhas : $($failed.Count)" $(if ($failed.Count -gt 0) { 'Red' } else { 'Green' })

if ($failed.Count -gt 0) {
    Write-Log "  Pacotes com falha:" 'Red'
    foreach ($f in $failed) {
        Write-Log "    • $f" 'Red'
    }
}

Write-Log "══════════════════════════════════════════════════════" 'Yellow'
Write-Log "=== Get-WingetUpgrade concluido ===" 'Yellow'

Write-Host ""
Write-Host "Log completo salvo em:" -ForegroundColor DarkGray
Write-Host "  $logFile" -ForegroundColor Cyan
