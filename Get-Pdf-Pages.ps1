<#
.SYNOPSIS
    Lista os PDFs do diretorio corrente com a quantidade de paginas.
.DESCRIPTION
    Garante que o xpdf-tools (scoop) esteja instalado e usa o pdfinfo para
    obter o numero de paginas de cada PDF encontrado.
.PARAMETER Path
    Diretorio a ser percorrido. Padrao: diretorio corrente.
.PARAMETER Recurse
    Percorre tambem os subdiretorios.
.PARAMETER LogPath
    Arquivo de log gerado. Padrao: Get-Pdf-Pages.log no diretorio analisado.
.PARAMETER Like
    Coringas que o nome do arquivo deve casar. Ex: -Like *fundo_branco*
.PARAMETER No
    Coringas que excluem arquivos. Ex: -No *fundo_colorido*
.EXAMPLE
    .\Get-Pdf-Pages.ps1 -Like *fundo_branco* -No *rascunho*
#>
[CmdletBinding()]
param(
    [string]$Path = (Get-Location).Path,
    [switch]$Recurse,
    [string]$LogPath,
    [Alias('Include', 'Match')]
    [string[]]$Like,
    [Alias('Exclude', 'Not')]
    [string[]]$No
)

$ErrorActionPreference = 'Stop'

function Install-XpdfTools {
    if (Get-Command pdfinfo -ErrorAction SilentlyContinue) { return }

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        throw "Scoop nao encontrado. Instale em https://scoop.sh e execute novamente."
    }

    Write-Host "xpdf-tools nao encontrado. Instalando via scoop..." -ForegroundColor Yellow
    scoop install xpdf-tools
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao instalar xpdf-tools via scoop."
    }

    # Atualiza o PATH da sessao para enxergar o shim recem-criado.
    $env:Path = @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) -join ';'

    if (-not (Get-Command pdfinfo -ErrorAction SilentlyContinue)) {
        throw "pdfinfo continua indisponivel. Abra um novo terminal e tente de novo."
    }
}

function Get-PdfPageCount {
    param([string]$FilePath)

    $output = & pdfinfo -- $FilePath 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }

    foreach ($line in $output) {
        if ($line -match '^\s*Pages:\s+(\d+)\s*$') { return [int]$Matches[1] }
    }
    return $null
}

Install-XpdfTools

if (-not $LogPath) {
    $LogPath = Join-Path $Path 'Get-Pdf-Pages.log'
}

$files = Get-ChildItem -LiteralPath $Path -Filter *.pdf -File -Recurse:$Recurse |
Where-Object {
    $nome = $_.Name
    $incluir = (-not $Like) -or ($Like | Where-Object { $nome -like $_ })
    $excluir = $No -and ($No | Where-Object { $nome -like $_ })
    $incluir -and -not $excluir
} |
Sort-Object FullName

if (-not $files) {
    Write-Host "Nenhum PDF encontrado em '$Path' com os filtros informados." -ForegroundColor Yellow
    return
}

$total = 0
$linhas = foreach ($file in $files) {
    $pages = Get-PdfPageCount -FilePath $file.FullName
    if ($null -ne $pages) { $total += $pages }

    [pscustomobject]@{
        Nome    = $file.Name
        Paginas = $pages
        Ok      = ($null -ne $pages)
    }
}

$colNome = [Math]::Max(7, ($linhas | ForEach-Object { $_.Nome.Length } | Measure-Object -Maximum).Maximum)
$colPag = 10
$sepTopo = '+' + ('-' * ($colNome + 2)) + '+' + ('-' * ($colPag + 2)) + '+'
$fmt = "| {0,-$colNome} | {1,$colPag} |"

$saida = New-Object System.Collections.Generic.List[string]
$saida.Add($sepTopo)
$saida.Add(($fmt -f 'Arquivo', 'Paginas'))
$saida.Add($sepTopo)

foreach ($linha in $linhas) {
    $valor = if ($linha.Ok) { [string]$linha.Paginas } else { 'erro' }
    $saida.Add(($fmt -f $linha.Nome, $valor))
}

$saida.Add($sepTopo)
$saida.Add(($fmt -f 'TOTAL', [string]$total))
$saida.Add($sepTopo)
$saida.Add(("Arquivos: {0}" -f $files.Count))
if ($Like) { $saida.Add("Filtro -Like: " + ($Like -join ', ')) }
if ($No) { $saida.Add("Filtro -No:   " + ($No -join ', ')) }

$saida | ForEach-Object { Write-Host $_ }

$saida | Set-Content -LiteralPath $LogPath -Encoding UTF8
Write-Host ("Log gravado em: {0}" -f $LogPath) -ForegroundColor Cyan
