#Requires -Version 5.1
<#
.SYNOPSIS
    Update seletivo de ferramentas instaladas no Windows (winget / scoop).
.DESCRIPTION
    Detecta os gerenciadores disponíveis, busca as atualizações pendentes e
    apresenta uma lista com checkboxes para escolher quais pacotes atualizar.
    Os upgrades são executados um a um, na sequência.
.EXAMPLE
    .\select-winget-upgrades.ps1
.EXAMPLE
    .\select-winget-upgrades.ps1 -Manager scoop
#>

[CmdletBinding()]
param(
    [ValidateSet('winget', 'scoop', 'ask')]
    [string]$Manager = 'ask'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ── Helpers de saída ──────────────────────────────────────────────────────────
function Write-Title ([string]$Text) {
    $line = '─' * ($Text.Length + 2)
    Write-Host ''
    Write-Host "┌$line┐" -ForegroundColor Cyan
    Write-Host "│ $Text │" -ForegroundColor Cyan
    Write-Host "└$line┘" -ForegroundColor Cyan
}

function Write-Info  ([string]$m) { Write-Host "  $m" -ForegroundColor Gray }
function Write-Ok    ([string]$m) { Write-Host "  ✔ $m" -ForegroundColor Green }
function Write-Warn2 ([string]$m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Write-Err   ([string]$m) { Write-Host "  ✘ $m" -ForegroundColor Red }

function Test-Manager ([string]$Name) {
    [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# ── Coleta de atualizações: winget ────────────────────────────────────────────
function Get-WingetUpdates {
    $raw = & winget upgrade --include-unknown --accept-source-agreements 2>$null |
        Out-String -Stream

    # Localiza o cabeçalho da tabela para descobrir as posições das colunas.
    $headerIndex = -1
    for ($i = 0; $i -lt $raw.Count; $i++) {
        if ($raw[$i] -match '^\s*Name\s+Id\s+Version\s+Available' -or
            $raw[$i] -match '^\s*Nome\s+ID\s+Vers') {
            $headerIndex = $i
            break
        }
    }
    if ($headerIndex -lt 0) { return @() }

    $header = $raw[$headerIndex]
    $cols = @()
    foreach ($token in [regex]::Matches($header, '\S+')) { $cols += $token.Index }
    # Colunas esperadas: Name, Id, Version, Available, Source
    if ($cols.Count -lt 4) { return @() }

    $items = @()
    for ($i = $headerIndex + 2; $i -lt $raw.Count; $i++) {
        $line = $raw[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match 'upgrades? available' -or $line -match 'atualiza') { continue }
        if ($line -match '^\s*-+\s*$') { continue }
        if ($line.Length -le $cols[1]) { continue }

        $slice = {
            param($start, $end)
            if ($start -ge $line.Length) { return '' }
            $len = if ($end -gt 0 -and $end -le $line.Length) { $end - $start } else { $line.Length - $start }
            if ($len -le 0) { return '' }
            $line.Substring($start, $len).Trim()
        }

        $name      = & $slice $cols[0] $cols[1]
        $id        = & $slice $cols[1] $cols[2]
        $current   = & $slice $cols[2] $cols[3]
        $available = if ($cols.Count -ge 5) { & $slice $cols[3] $cols[4] } else { & $slice $cols[3] 0 }

        if (-not $id -or -not $available) { continue }
        if ($id -notmatch '\S') { continue }

        $items += [pscustomobject]@{
            Name      = $name
            Id        = $id
            Current   = $current
            Available = $available
        }
    }
    return $items
}

# ── Coleta de atualizações: scoop ─────────────────────────────────────────────
function Get-ScoopUpdates {
    Write-Info 'Atualizando os buckets do scoop (scoop update)...'
    & scoop update *> $null

    $status = & scoop status 6>$null
    $items = @()
    foreach ($row in $status) {
        $name = $row.Name
        if (-not $name) { continue }
        $current   = $row.'Installed Version'
        if (-not $current) { $current = $row.Version }
        $available = $row.'Latest Version'
        if (-not $available) { continue }
        if ($current -eq $available) { continue }

        $items += [pscustomobject]@{
            Name      = $name
            Id        = $name
            Current   = "$current"
            Available = "$available"
        }
    }
    return $items
}

# ── Menu de seleção do gerenciador ────────────────────────────────────────────
function Select-Manager {
    $hasWinget = Test-Manager 'winget'
    $hasScoop  = Test-Manager 'scoop'

    if (-not $hasWinget -and -not $hasScoop) {
        Write-Err 'Nem winget nem scoop foram encontrados no PATH.'
        return $null
    }

    Write-Title 'Gerenciadores de pacotes'
    $options = @()
    if ($hasWinget) { $options += 'winget' }
    if ($hasScoop)  { $options += 'scoop'  }

    for ($i = 0; $i -lt $options.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $options[$i]) -ForegroundColor White
    }
    if ($options.Count -gt 1) {
        Write-Host ("  [{0}] ambos (em sequência)" -f ($options.Count + 1)) -ForegroundColor White
    }
    Write-Host '  [Q] sair' -ForegroundColor DarkGray
    Write-Host ''

    while ($true) {
        $choice = Read-Host 'Escolha uma opção'
        if ($choice -match '^[Qq]$') { return @() }
        if ($choice -match '^\d+$') {
            $n = [int]$choice
            if ($n -ge 1 -and $n -le $options.Count) { return @($options[$n - 1]) }
            if ($options.Count -gt 1 -and $n -eq ($options.Count + 1)) { return $options }
        }
        Write-Warn2 'Opção inválida.'
    }
}

# ── Lista com checkboxes ──────────────────────────────────────────────────────
function Select-Packages {
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][string]$ManagerName
    )

    $checked = New-Object bool[] $Items.Count
    $cursor  = 0
    $nameWidth = ($Items | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    if ($nameWidth -gt 38) { $nameWidth = 38 }
    if ($nameWidth -lt 12) { $nameWidth = 12 }

    while ($true) {
        Clear-Host
        Write-Title "Atualizações disponíveis — $ManagerName ($($Items.Count))"
        Write-Host '  ↑/↓ mover   ESPAÇO marcar   A todos   N nenhum   ENTER confirmar   ESC cancelar' -ForegroundColor DarkGray
        Write-Host ''

        for ($i = 0; $i -lt $Items.Count; $i++) {
            $it   = $Items[$i]
            $mark = if ($checked[$i]) { '[x]' } else { '[ ]' }
            $ptr  = if ($i -eq $cursor) { '>' } else { ' ' }
            $name = if ($it.Name.Length -gt $nameWidth) { $it.Name.Substring(0, $nameWidth - 1) + '…' } else { $it.Name }
            $text = "{0} {1} {2}  {3} → {4}" -f $ptr, $mark, $name.PadRight($nameWidth), $it.Current, $it.Available

            if ($i -eq $cursor) {
                Write-Host "  $text" -ForegroundColor Black -BackgroundColor Cyan
            }
            elseif ($checked[$i]) {
                Write-Host "  $text" -ForegroundColor Green
            }
            else {
                Write-Host "  $text" -ForegroundColor Gray
            }
        }

        $selected = ($checked | Where-Object { $_ }).Count
        Write-Host ''
        Write-Host "  Selecionados: $selected de $($Items.Count)" -ForegroundColor Yellow

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'    { $cursor = if ($cursor -eq 0) { $Items.Count - 1 } else { $cursor - 1 } }
            'DownArrow'  { $cursor = ($cursor + 1) % $Items.Count }
            'Home'       { $cursor = 0 }
            'End'        { $cursor = $Items.Count - 1 }
            'Spacebar'   { $checked[$cursor] = -not $checked[$cursor] }
            'Escape'     { return @() }
            'Enter'      {
                $result = @()
                for ($i = 0; $i -lt $Items.Count; $i++) { if ($checked[$i]) { $result += $Items[$i] } }
                return $result
            }
            default {
                switch ("$($key.KeyChar)".ToUpperInvariant()) {
                    'A' { for ($i = 0; $i -lt $Items.Count; $i++) { $checked[$i] = $true } }
                    'N' { for ($i = 0; $i -lt $Items.Count; $i++) { $checked[$i] = $false } }
                    'Q' { return @() }
                }
            }
        }
    }
}

# ── Execução dos upgrades ─────────────────────────────────────────────────────
function Invoke-Upgrades {
    param(
        [Parameter(Mandatory)][object[]]$Packages,
        [Parameter(Mandatory)][string]$ManagerName
    )

    $total   = $Packages.Count
    $ok      = @()
    $failed  = @()
    $index   = 0

    foreach ($pkg in $Packages) {
        $index++
        Write-Title ("[{0}/{1}] {2} — {3} → {4}" -f $index, $total, $pkg.Name, $pkg.Current, $pkg.Available)

        try {
            if ($ManagerName -eq 'winget') {
                & winget upgrade --id $pkg.Id --exact --silent `
                    --accept-package-agreements --accept-source-agreements --include-unknown
            }
            else {
                & scoop update $pkg.Id
            }
            $code = $LASTEXITCODE
        }
        catch {
            Write-Err $_.Exception.Message
            $code = 1
        }

        if ($code -eq 0) {
            Write-Ok "$($pkg.Name) atualizado."
            $ok += $pkg.Name
        }
        else {
            Write-Err "$($pkg.Name) falhou (exit code $code)."
            $failed += $pkg.Name
        }
    }

    Write-Title 'Resumo'
    Write-Host "  Atualizados: $($ok.Count)" -ForegroundColor Green
    foreach ($n in $ok) { Write-Host "    • $n" -ForegroundColor DarkGreen }
    if ($failed.Count) {
        Write-Host "  Falhas: $($failed.Count)" -ForegroundColor Red
        foreach ($n in $failed) { Write-Host "    • $n" -ForegroundColor DarkRed }
    }
}

# ── Fluxo principal ───────────────────────────────────────────────────────────
function Start-SelectiveUpdate {
    if ($Manager -eq 'ask') {
        $managers = Select-Manager
    }
    else {
        if (-not (Test-Manager $Manager)) {
            Write-Err "'$Manager' não foi encontrado no PATH."
            return
        }
        $managers = @($Manager)
    }

    if (-not $managers -or $managers.Count -eq 0) {
        Write-Info 'Nada a fazer.'
        return
    }

    foreach ($mgr in $managers) {
        Write-Title "Buscando atualizações — $mgr"
        $items = if ($mgr -eq 'winget') { Get-WingetUpdates } else { Get-ScoopUpdates }

        if (-not $items -or $items.Count -eq 0) {
            Write-Ok "Nenhuma atualização pendente no $mgr."
            continue
        }

        $selection = Select-Packages -Items $items -ManagerName $mgr
        if (-not $selection -or $selection.Count -eq 0) {
            Write-Warn2 "Nenhum pacote selecionado para o $mgr."
            continue
        }

        Invoke-Upgrades -Packages $selection -ManagerName $mgr
    }
}

Start-SelectiveUpdate
