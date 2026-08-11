#Requires -Version 5.1
<#!
.SYNOPSIS
    Lista atualizacoes disponiveis do winget e permite selecionar quais instalar.

.DESCRIPTION
    Consulta o comando winget upgrade, mostra uma lista em console com marcadores
    tipo checkbox e permite que o usuario escolha quais pacotes devem receber
    upgrade. Os itens selecionados sao atualizados um a um.

.PARAMETER ListOnly
    Apenas lista as atualizacoes disponiveis e encerra sem instalar.

.PARAMETER IncludeUnknown
    Inclui pacotes desconhecidos na consulta do winget.
#>

[CmdletBinding()]
param(
    [switch]$ListOnly,
    [switch]$IncludeUnknown
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section {
    param(
        [string]$Message,
        [string]$Color = 'Cyan'
    )

    Write-Host $Message -ForegroundColor $Color
}

function ConvertTo-Array {
    param([Parameter(ValueFromPipeline = $true)]$InputObject)

    process {
        if ($null -eq $InputObject) {
            return @()
        }

        if ($InputObject -is [System.Array]) {
            return @($InputObject)
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
            return @($InputObject)
        }

        return @($InputObject)
    }
}

function Get-ItemCount {
    param($Value)

    if ($null -eq $Value) {
        return 0
    }

    return @($Value).Count
}

function Get-WingetUpdates {
    $textArguments = @('upgrade', '--disable-interactivity')
    if ($IncludeUnknown) {
        $textArguments += '--include-unknown'
    }

    $rawText = & winget @textArguments 2>&1
    $lines = @()
    foreach ($line in @($rawText)) {
        if ($null -ne $line) {
            $lines += [string]$line
        }
    }

    if ((Get-ItemCount -Value $lines) -eq 0) {
        return @()
    }

    $packages = @()
    $inTable = $false

    for ($i = 0; $i -lt (Get-ItemCount -Value $lines); $i++) {
        $line = $lines[$i].Trim()
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match '(?i)\bNome\b' -and $line -match '(?i)\bID\b') {
            $inTable = $true
            continue
        }

        if (-not $inTable) {
            continue
        }

        if ($line -match '^[-]{3,}$') {
            continue
        }

        if ($line -match '^[0-9]+\s+atualiza[cç][aã]o(?:es)?\s+dispon[íi]veis') {
            break
        }

        $tokens = @($line -split '\s+') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ((Get-ItemCount -Value $tokens) -lt 2) {
            continue
        }

        $idIndex = -1
        for ($tokenIndex = 0; $tokenIndex -lt (Get-ItemCount -Value $tokens); $tokenIndex++) {
            $token = $tokens[$tokenIndex]
            if ($token -match '^[A-Za-z][A-Za-z0-9_.+-]*\.[A-Za-z0-9_.+-]+$') {
                $idIndex = $tokenIndex
                break
            }
        }

        if ($idIndex -lt 0) {
            continue
        }

        $id = $tokens[$idIndex]
        $nameTokens = @($tokens[0..($idIndex - 1)])
        $name = ($nameTokens -join ' ').Trim()
        $availableVersion = ''

        if ($name -match '^(Nome|Name|Vers[ãa]o|Version|Dispon[ií]vel|Available|Origem|Source)$') {
            continue
        }

        if ($id -match '^(Nome|Name|Vers[ãa]o|Version|Dispon[ií]vel|Available|Origem|Source)$') {
            continue
        }

        $packages += [pscustomobject]@{
            Id = $id
            Name = $name
            AvailableVersion = $availableVersion
        }
    }

    return @($packages | Select-Object -Unique Id, Name, AvailableVersion)
}

function Resolve-Selection {
    param(
        [string]$InputText,
        [int]$TotalItems
    )

    if ([string]::IsNullOrWhiteSpace($InputText)) {
        return @()
    }

    $normalized = $InputText.Trim().ToLowerInvariant()
    if ($normalized -eq 'q' -or $normalized -eq 'quit' -or $normalized -eq 'sair') {
        return $null
    }

    if ($normalized -eq 'all' -or $normalized -eq 'todos') {
        return 1..$TotalItems
    }

    if ($normalized -eq 'none' -or $normalized -eq 'nenhum') {
        return @()
    }

    $indices = New-Object System.Collections.Generic.List[int]
    foreach ($segment in ($InputText -split ',')) {
        $segment = $segment.Trim()
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }

        if ($segment -match '^(\d+)-(\d+)$') {
            $start = [int]$matches[1]
            $end = [int]$matches[2]
            if ($start -gt $end) {
                $temp = $start
                $start = $end
                $end = $temp
            }

            for ($i = $start; $i -le $end; $i++) {
                if ($i -ge 1 -and $i -le $TotalItems) {
                    $indices.Add($i)
                }
            }
        }
        elseif ($segment -match '^\d+$') {
            $value = [int]$segment
            if ($value -ge 1 -and $value -le $TotalItems) {
                $indices.Add($value)
            }
        }
    }

    return @($indices | Select-Object -Unique)
}

function Show-SelectionMenu {
    param([object[]]$Packages)

    Write-Host ''
    Write-Section 'Atualizacoes disponiveis:' 'Cyan'
    Write-Section 'Use [ ] para cada item abaixo e escolha pelos numeros.' 'Yellow'

    for ($i = 0; $i -lt (Get-ItemCount -Value $Packages); $i++) {
        $pkg = $Packages[$i]
        $suffix = ''
        if (-not [string]::IsNullOrWhiteSpace($pkg.AvailableVersion)) {
            $suffix = " -> $($pkg.AvailableVersion)"
        }

        Write-Host ("[ ] {0}. {1} [{2}]{3}" -f ($i + 1), $pkg.Name, $pkg.Id, $suffix) -ForegroundColor White
    }

    Write-Host ''
    Write-Host "Digite os numeros desejados (ex.: 1,3,5-7), 'all', 'none' ou 'q' para sair." -ForegroundColor Yellow
    $selectionInput = Read-Host 'Selecao'
    return Resolve-Selection -InputText $selectionInput -TotalItems (Get-ItemCount -Value $Packages)
}

Write-Section '=== Winget Update Selector ===' 'Yellow'

$updates = @(Get-WingetUpdates)
$updates = ConvertTo-Array -InputObject $updates
if ((Get-ItemCount -Value $updates) -eq 0) {
    Write-Section 'Nao foi possivel encontrar atualizacoes disponiveis ou nao ha nada para atualizar.' 'Green'
    exit 0
}

$selectedIndexes = Show-SelectionMenu -Packages $updates
if ($null -eq $selectedIndexes) {
    Write-Section 'Operacao cancelada pelo usuario.' 'Yellow'
    exit 0
}

$selectedIndexes = ConvertTo-Array -InputObject $selectedIndexes
if ((Get-ItemCount -Value $selectedIndexes) -eq 0) {
    Write-Section 'Nenhum pacote selecionado. Nada para fazer.' 'Yellow'
    exit 0
}

if ($ListOnly) {
    Write-Section 'Modo somente lista ativado. Nenhum upgrade foi executado.' 'Green'
    exit 0
}

$selectedPackages = @()
foreach ($index in $selectedIndexes) {
    $selectedPackages += $updates[$index - 1]
}

Write-Host ''
Write-Section ('Serao atualizados ' + (Get-ItemCount -Value $selectedPackages) + ' pacote(s):') 'Cyan'
foreach ($package in $selectedPackages) {
    Write-Host (' - ' + $package.Name + ' [' + $package.Id + ']') -ForegroundColor White
}

$confirm = Read-Host 'Deseja prosseguir? (S/N)'
if ($confirm -notmatch '^[Ss]') {
    Write-Section 'Operacao cancelada pelo usuario.' 'Yellow'
    exit 0
}

$success = 0
$failed = @()

foreach ($package in $selectedPackages) {
    Write-Host ''
    Write-Section ('Atualizando: ' + $package.Name + ' [' + $package.Id + ']') 'Cyan'

    $arguments = @('upgrade', '--id', $package.Id, '--exact', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    & winget @arguments
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        $success++
        Write-Section 'OK: atualizado com sucesso.' 'Green'
    }
    else {
        $failed += $package.Id
        Write-Section ('FALHA: ' + $package.Id + ' (exit code ' + $exitCode + ')') 'Red'
    }
}

Write-Host ''
Write-Section 'Resumo final' 'Yellow'
Write-Host ('  Total: ' + (Get-ItemCount -Value $selectedPackages)) -ForegroundColor White
Write-Host ('  Sucesso: ' + $success) -ForegroundColor Green
Write-Host ('  Falhas: ' + (Get-ItemCount -Value $failed)) -ForegroundColor Red

if ((Get-ItemCount -Value $failed) -gt 0) {
    Write-Host '  Pacotes com falha:' -ForegroundColor Red
    foreach ($item in $failed) {
        Write-Host ('    - ' + $item) -ForegroundColor Red
    }
}
