#Requires -Version 5.1
<#
.SYNOPSIS
    Busca programas no winget e no scoop e instala os selecionados.
.DESCRIPTION
    Recebe um termo de busca, consulta 'winget search' e 'scoop search',
    junta os resultados numa única lista (mostrando de qual repositório
    cada item vem) ordenada por proximidade com o termo digitado, e
    apresenta uma lista com checkboxes para escolher o que instalar.
    Os pacotes marcados são instalados em sequência com o gerenciador
    correspondente (winget ou scoop).
.PARAMETER Query
    Termo de busca (nome completo ou parte do nome do programa).
.PARAMETER Columns
    Número de colunas da lista de seleção. 0 (padrão) calcula automaticamente
    quantas colunas cabem na tela para evitar rolagem quando possível.
.EXAMPLE
    .\Search-Tool.ps1 vscode
.EXAMPLE
    .\Search-Tool.ps1
    (pede o termo de busca interativamente)
.EXAMPLE
    .\Search-Tool.ps1 notepad -Columns 2
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Query,

    [int]$Columns = 0
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

# Tamanho do terminal, com fallback para sessões sem console interativo.
function Get-ConsoleSize {
    try {
        $h = [Console]::WindowHeight
        $w = [Console]::WindowWidth
        if ($h -le 0) { $h = 25 }
        if ($w -le 0) { $w = 80 }
        [pscustomobject]@{ Height = $h; Width = $w }
    }
    catch {
        [pscustomobject]@{ Height = 25; Width = 80 }
    }
}

# Fatia uma linha de texto de largura fixa entre duas posições de coluna.
function Get-ColumnSlice {
    param([string]$Line, [int]$Start, [int]$End)
    if ($Start -ge $Line.Length) { return '' }
    $len = if ($End -gt 0 -and $End -le $Line.Length) { $End - $Start } else { $Line.Length - $Start }
    if ($len -le 0) { return '' }
    $Line.Substring($Start, $len).Trim()
}

# ── Busca: winget ─────────────────────────────────────────────────────────────
function Get-WingetSearchResults {
    param([string]$Query)

    $raw = & winget search $Query --accept-source-agreements 2>$null | Out-String -Stream

    $headerIndex = -1
    for ($i = 0; $i -lt $raw.Count; $i++) {
        if ($raw[$i] -match '^\s*Name\s+Id\s+Version' -or $raw[$i] -match '^\s*Nome\s+ID\s+Vers') {
            $headerIndex = $i
            break
        }
    }
    if ($headerIndex -lt 0) { return @() }

    $header = $raw[$headerIndex]
    $cols = @()
    foreach ($token in [regex]::Matches($header, '\S+')) { $cols += $token.Index }
    if ($cols.Count -lt 3) { return @() }

    $items = @()
    for ($i = $headerIndex + 2; $i -lt $raw.Count; $i++) {
        $line = $raw[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*-+\s*$') { continue }
        if ($line -match 'No package found|Nenhum pacote encontrado') { continue }
        if ($line.Length -le $cols[1]) { continue }

        $name    = Get-ColumnSlice $line $cols[0] $cols[1]
        $id      = Get-ColumnSlice $line $cols[1] $cols[2]
        $version = if ($cols.Count -ge 4) { Get-ColumnSlice $line $cols[2] $cols[3] } else { Get-ColumnSlice $line $cols[2] 0 }
        $source  = Get-ColumnSlice $line $cols[-1] 0

        if (-not $id -or $id -notmatch '\S') { continue }

        $items += [pscustomobject]@{
            Name    = $name
            Id      = $id
            Version = $version
            Repo    = if ($source) { $source } else { 'winget' }
            Manager = 'winget'
        }
    }
    return $items
}

# ── Busca: scoop ──────────────────────────────────────────────────────────────
function Get-ScoopSearchResults {
    param([string]$Query)

    $raw = & scoop search $Query 2>$null | Out-String -Stream

    $headerIndex = -1
    for ($i = 0; $i -lt $raw.Count; $i++) {
        if ($raw[$i] -match '^\s*Name\s+Version\s+Source') {
            $headerIndex = $i
            break
        }
    }

    $items = @()

    if ($headerIndex -ge 0) {
        $header = $raw[$headerIndex]
        $cols = @()
        foreach ($token in [regex]::Matches($header, '\S+')) { $cols += $token.Index }
        if ($cols.Count -lt 2) { return @() }

        for ($i = $headerIndex + 2; $i -lt $raw.Count; $i++) {
            $line = $raw[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '^\s*-+\s*$') { continue }
            if ($line.Length -le $cols[0]) { continue }

            $name    = Get-ColumnSlice $line $cols[0] $cols[1]
            $version = if ($cols.Count -ge 3) { Get-ColumnSlice $line $cols[1] $cols[2] } else { Get-ColumnSlice $line $cols[1] 0 }
            $source  = if ($cols.Count -ge 3) { Get-ColumnSlice $line $cols[2] $(if ($cols.Count -ge 4) { $cols[3] } else { 0 }) } else { '' }

            if (-not $name) { continue }

            $items += [pscustomobject]@{
                Name    = $name
                Id      = $name
                Version = $version
                Repo    = if ($source) { "scoop/$source" } else { 'scoop' }
                Manager = 'scoop'
            }
        }
        return $items
    }

    # Formato antigo do scoop (lista por bucket, sem tabela).
    $bucket = $null
    foreach ($line in $raw) {
        if ($line -match "^'(.+)' bucket:") { $bucket = $Matches[1]; continue }
        if ($line -match '^\s*(\S+)\s+\(([^)]+)\)') {
            $items += [pscustomobject]@{
                Name    = $Matches[1]
                Id      = $Matches[1]
                Version = $Matches[2]
                Repo    = if ($bucket) { "scoop/$bucket" } else { 'scoop' }
                Manager = 'scoop'
            }
        }
    }
    return $items
}

# ── Relevância (quão perto o nome está do termo buscado) ─────────────────────
function Get-RelevanceRank {
    param([string]$Name, [string]$Query)
    if ([string]::IsNullOrEmpty($Name)) { return 9 }
    if ($Name -ieq $Query) { return 0 }
    if ($Name -imatch "^$([regex]::Escape($Query))") { return 1 }
    if ($Name -imatch [regex]::Escape($Query)) { return 2 }
    return 3
}

# ── Lista com checkboxes (com rolagem e colunas) ─────────────────────────────
function Select-Items {
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [int]$Columns = 0
    )

    $count   = $Items.Count
    $checked = New-Object bool[] $count
    $cursor  = 0
    $rowScroll = 0

    $nameWidth = ($Items | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    if ($nameWidth -gt 34) { $nameWidth = 34 }
    if ($nameWidth -lt 12) { $nameWidth = 12 }

    $repoWidth = ($Items | ForEach-Object { $_.Repo.Length } | Measure-Object -Maximum).Maximum
    if ($repoWidth -lt 6) { $repoWidth = 6 }

    $versionWidth = ($Items | ForEach-Object { $_.Version.Length } | Measure-Object -Maximum).Maximum
    if ($versionWidth -gt 16) { $versionWidth = 16 }
    if ($versionWidth -lt 7) { $versionWidth = 7 }

    # ponteiro(2) + checkbox(4) + nome + repo + versão + espaçamento entre campos/colunas
    $cellWidth = 2 + 4 + $nameWidth + 2 + $repoWidth + 2 + $versionWidth + 3

    # linhas reservadas para título, dica de teclas e rodapé (com folga p/ indicadores de rolagem)
    $reservedLines = 10

    while ($true) {
        $size = Get-ConsoleSize
        $viewportRows = $size.Height - $reservedLines
        if ($viewportRows -lt 3) { $viewportRows = 3 }

        $maxColumnsFit = [Math]::Max(1, [Math]::Floor($size.Width / [double]$cellWidth))
        $neededColumns = [Math]::Max(1, [Math]::Ceiling($count / [double]$viewportRows))

        if ($Columns -gt 0) { $numColumns = [Math]::Min($Columns, $maxColumnsFit) }
        else { $numColumns = [Math]::Min($neededColumns, $maxColumnsFit) }
        if ($numColumns -lt 1) { $numColumns = 1 }

        $rowsPerColumn = [Math]::Ceiling($count / [double]$numColumns)

        $curCol = [Math]::Floor($cursor / $rowsPerColumn)
        $curRow = $cursor % $rowsPerColumn

        # mantém o cursor dentro da janela visível
        if ($curRow -lt $rowScroll) { $rowScroll = $curRow }
        elseif ($curRow -ge $rowScroll + $viewportRows) { $rowScroll = $curRow - $viewportRows + 1 }
        $maxScroll = [Math]::Max(0, $rowsPerColumn - $viewportRows)
        if ($rowScroll -gt $maxScroll) { $rowScroll = $maxScroll }
        if ($rowScroll -lt 0) { $rowScroll = 0 }

        Clear-Host
        Write-Title "Resultados da busca ($count)"
        $navHint = if ($numColumns -gt 1) { '↑/↓/←/→ mover   PgUp/PgDn página' } else { '↑/↓ mover   PgUp/PgDn página' }
        Write-Host "  $navHint   ESPAÇO marcar   A todos   N nenhum   ENTER instalar   ESC cancelar" -ForegroundColor DarkGray
        Write-Host ''

        if ($rowScroll -gt 0) { Write-Host '  ▲ mais itens acima' -ForegroundColor DarkGray }
        else { Write-Host '' }

        $lastRow = [Math]::Min($rowScroll + $viewportRows, $rowsPerColumn) - 1
        for ($r = $rowScroll; $r -le $lastRow; $r++) {
            for ($c = 0; $c -lt $numColumns; $c++) {
                $idx = $c * $rowsPerColumn + $r
                if ($idx -ge $count) {
                    Write-Host ('  ' + (' ' * $cellWidth)) -NoNewline
                    continue
                }

                $it   = $Items[$idx]
                $mark = if ($checked[$idx]) { '[x]' } else { '[ ]' }
                $ptr  = if ($idx -eq $cursor) { '>' } else { ' ' }
                $name = if ($it.Name.Length -gt $nameWidth) { $it.Name.Substring(0, $nameWidth - 1) + '…' } else { $it.Name }
                $ver  = if ($it.Version.Length -gt $versionWidth) { $it.Version.Substring(0, $versionWidth - 1) + '…' } else { $it.Version }
                $cell = "{0} {1} {2}  {3}  {4}" -f $ptr, $mark, $name.PadRight($nameWidth), $it.Repo.PadRight($repoWidth), $ver.PadRight($versionWidth)
                $cell = $cell.PadRight($cellWidth)

                if ($idx -eq $cursor) {
                    Write-Host "  $cell" -ForegroundColor Black -BackgroundColor Cyan -NoNewline
                }
                elseif ($checked[$idx]) {
                    Write-Host "  $cell" -ForegroundColor Green -NoNewline
                }
                else {
                    Write-Host "  $cell" -ForegroundColor Gray -NoNewline
                }
            }
            Write-Host ''
        }

        if ($rowScroll + $viewportRows -lt $rowsPerColumn) { Write-Host '  ▼ mais itens abaixo' -ForegroundColor DarkGray }
        else { Write-Host '' }

        $selected = ($checked | Where-Object { $_ }).Count
        Write-Host ''
        Write-Host "  Selecionados: $selected de $count   (item $($cursor + 1) de $count)" -ForegroundColor Yellow

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow' {
                $curRow--
                if ($curRow -lt 0) { $curRow = $rowsPerColumn - 1 }
                $cursor = $curCol * $rowsPerColumn + $curRow
                if ($cursor -ge $count) { $cursor = $count - 1 }
            }
            'DownArrow' {
                $curRow++
                if ($curRow -ge $rowsPerColumn) { $curRow = 0 }
                $newCursor = $curCol * $rowsPerColumn + $curRow
                if ($newCursor -ge $count) { $newCursor = $curCol * $rowsPerColumn }
                $cursor = $newCursor
            }
            'LeftArrow' {
                $newCol = $curCol
                for ($step = 0; $step -lt $numColumns; $step++) {
                    $newCol--
                    if ($newCol -lt 0) { $newCol = $numColumns - 1 }
                    $newCursor = $newCol * $rowsPerColumn + $curRow
                    if ($newCursor -lt $count) { $cursor = $newCursor; break }
                }
            }
            'RightArrow' {
                $newCol = $curCol
                for ($step = 0; $step -lt $numColumns; $step++) {
                    $newCol++
                    if ($newCol -ge $numColumns) { $newCol = 0 }
                    $newCursor = $newCol * $rowsPerColumn + $curRow
                    if ($newCursor -lt $count) { $cursor = $newCursor; break }
                }
            }
            'PageUp' {
                $colStart = $curCol * $rowsPerColumn
                $cursor = [Math]::Max($colStart, $cursor - $viewportRows)
            }
            'PageDown' {
                $colEnd = [Math]::Min(($curCol + 1) * $rowsPerColumn, $count) - 1
                $cursor = [Math]::Min($colEnd, $cursor + $viewportRows)
            }
            'Home'       { $cursor = 0 }
            'End'        { $cursor = $count - 1 }
            'Spacebar'   { $checked[$cursor] = -not $checked[$cursor] }
            'Escape'     { return @() }
            'Enter'      {
                $result = @()
                for ($i = 0; $i -lt $count; $i++) { if ($checked[$i]) { $result += $Items[$i] } }
                return $result
            }
            default {
                switch ("$($key.KeyChar)".ToUpperInvariant()) {
                    'A' { for ($i = 0; $i -lt $count; $i++) { $checked[$i] = $true } }
                    'N' { for ($i = 0; $i -lt $count; $i++) { $checked[$i] = $false } }
                    'Q' { return @() }
                }
            }
        }
    }
}

# ── Instalação dos pacotes marcados ───────────────────────────────────────────
function Invoke-Install {
    param([Parameter(Mandatory)][object[]]$Packages)

    $total  = $Packages.Count
    $ok     = @()
    $failed = @()
    $index  = 0

    foreach ($pkg in $Packages) {
        $index++
        Write-Title ("[{0}/{1}] {2} ({3}) — {4}" -f $index, $total, $pkg.Name, $pkg.Repo, $pkg.Version)

        try {
            if ($pkg.Manager -eq 'winget') {
                $sourceArgs = @()
                if ($pkg.Repo -eq 'msstore') { $sourceArgs = @('--source', 'msstore') }
                & winget install --id $pkg.Id --exact `
                    --accept-package-agreements --accept-source-agreements @sourceArgs
            }
            else {
                & scoop install $pkg.Id
            }
            $code = $LASTEXITCODE
        }
        catch {
            Write-Err $_.Exception.Message
            $code = 1
        }

        if ($code -eq 0) {
            Write-Ok "$($pkg.Name) instalado."
            $ok += $pkg.Name
        }
        else {
            Write-Err "$($pkg.Name) falhou (exit code $code)."
            $failed += $pkg.Name
        }
    }

    Write-Title 'Resumo'
    Write-Host "  Instalados: $($ok.Count)" -ForegroundColor Green
    foreach ($n in $ok) { Write-Host "    • $n" -ForegroundColor DarkGreen }
    if ($failed.Count) {
        Write-Host "  Falhas: $($failed.Count)" -ForegroundColor Red
        foreach ($n in $failed) { Write-Host "    • $n" -ForegroundColor DarkRed }
    }
}

# ── Fluxo principal ───────────────────────────────────────────────────────────
function Start-ToolSearch {
    if (-not $Query) {
        $Query = Read-Host 'Digite o nome (ou parte do nome) do programa'
    }
    $Query = $Query.Trim()
    if (-not $Query) {
        Write-Warn2 'Nenhum termo informado.'
        return
    }

    $hasWinget = Test-Manager 'winget'
    $hasScoop  = Test-Manager 'scoop'
    if (-not $hasWinget -and -not $hasScoop) {
        Write-Err 'Nem winget nem scoop foram encontrados no PATH.'
        return
    }

    $items = @()

    if ($hasWinget) {
        Write-Title "Buscando no winget: $Query"
        $items += Get-WingetSearchResults -Query $Query
    }
    else {
        Write-Warn2 'winget não encontrado — pulando.'
    }

    if ($hasScoop) {
        Write-Title "Buscando no scoop: $Query"
        $items += Get-ScoopSearchResults -Query $Query
    }
    else {
        Write-Warn2 'scoop não encontrado — pulando.'
    }

    if (-not $items -or $items.Count -eq 0) {
        Write-Warn2 "Nenhum resultado encontrado para '$Query'."
        return
    }

    $items = @($items | Sort-Object { Get-RelevanceRank $_.Name $Query }, Name)

    $selection = Select-Items -Items $items -Columns $Columns
    if (-not $selection -or $selection.Count -eq 0) {
        Write-Warn2 'Nenhum pacote selecionado.'
        return
    }

    Invoke-Install -Packages $selection
}

Start-ToolSearch
