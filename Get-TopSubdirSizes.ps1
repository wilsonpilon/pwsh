<#
.SYNOPSIS
  Mostra o tamanho de cada subdiretório (apenas primeiro nível) de um diretório.

.DESCRIPTION
  Lista somente os diretórios do primeiro nível do caminho informado e calcula o
  tamanho total (recursivo) de cada um, exibindo resultado em formato legível.

.PARAMETER Path
  Caminho do diretório raiz onde os subdiretórios serão avaliados.

.PARAMETER Sort
  Ordena a saída por tamanho. Valores: None, Asc, Desc. Padrão: Desc.

.EXAMPLE
  .\Get-TopSubdirSizes.ps1 -Path "C:\Dados" -Sort Desc
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $Path = ".",

    [ValidateSet("None","Asc","Desc")]
    [string] $Sort = "Desc"
)

function Convert-ToReadableSize {
    param([nullable[ulong]]$Bytes)

    if ($Bytes -eq $null) { return "Acesso negado/erro" }
    if ($Bytes -lt 1KB) { return "$Bytes B" }

    $units = "KB","MB","GB","TB","PB","EB"
    $size = [double]$Bytes
    foreach ($u in $units) {
        $size = $size / 1KB
        if ($size -lt 1024) {
            return ("{0:N2} {1}" -f $size, $u)
        }
    }
    return ("{0:N2} ZB" -f ($size / 1024))
}

# Resolve o caminho e valida
try {
    $root = Resolve-Path -LiteralPath $Path -ErrorAction Stop
} catch {
    Write-Error "Caminho inválido: '$Path'. $_"
    exit 1
}

# Primeiro nível de subdiretórios
$items = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue

$result = foreach ($dir in $items) {
    # Soma o tamanho de todos os arquivos dentro do subdiretório (recursivo)
    try {
        $sum = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Sum Length).Sum
        if (-not $sum) { $sum = 0 }
    } catch {
        # Em caso de permissão negada ou erro de E/S
        $sum = $null
    }

    [pscustomobject]@{
        Nome          = $dir.Name
        TamanhoBytes  = $sum
        Tamanho       = Convert-ToReadableSize $sum
        Caminho       = $dir.FullName
    }
}

switch ($Sort) {
    "Asc"  { $result = $result | Sort-Object {[nullable[ulong]]$_.TamanhoBytes} }
    "Desc" { $result = $result | Sort-Object {[nullable[ulong]]$_.TamanhoBytes} -Descending }
    Default { }
}

# Saída em tabela
$result | Select-Object Nome, Tamanho, TamanhoBytes, Caminho | Format-Table -AutoSize