# Script para instalar todas as Nerd Fonts disponíveis no Scoop

# Verifica se o Scoop está instalado
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "Scoop não está instalado. Instalando Scoop..." -ForegroundColor Yellow
    
    # Verifica se o ExecutionPolicy permite a instalação
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    
    # Instala o Scoop
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Host "Erro ao instalar o Scoop. Por favor, instale manualmente." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Scoop instalado com sucesso!" -ForegroundColor Green
} else {
    Write-Host "Scoop já está instalado." -ForegroundColor Green
}

# Verifica se o bucket nerd-fonts está adicionado
Write-Host "Verificando buckets instalados..." -ForegroundColor Cyan
$bucketList = scoop bucket list | Out-String
if ($bucketList -match 'nerd-fonts') {
    Write-Host "Bucket 'nerd-fonts' já está adicionado." -ForegroundColor Green
} else {
    Write-Host "Bucket 'nerd-fonts' não encontrado. Adicionando..." -ForegroundColor Yellow
    scoop bucket add nerd-fonts
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Erro ao adicionar o bucket nerd-fonts." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Bucket 'nerd-fonts' adicionado com sucesso!" -ForegroundColor Green
}

# Atualiza o Scoop e os buckets
Write-Host "`nAtualizando Scoop..." -ForegroundColor Cyan
scoop update

# Lista todas as Nerd Fonts disponíveis
Write-Host "`nListando todas as Nerd Fonts disponíveis..." -ForegroundColor Cyan

# Localiza o diretório do bucket nerd-fonts
$scoopDir = if ($env:SCOOP) { $env:SCOOP } else { "$env:USERPROFILE\scoop" }
$bucketPath = "$scoopDir\buckets\nerd-fonts\bucket"

if (-not (Test-Path $bucketPath)) {
    Write-Host "Erro: Diretório do bucket nerd-fonts não encontrado em $bucketPath" -ForegroundColor Red
    exit 1
}

# Lista todos os arquivos .json do bucket (cada arquivo é uma fonte)
$nerdFonts = Get-ChildItem -Path $bucketPath -Filter "*.json" | 
    Select-Object -ExpandProperty BaseName | 
    Where-Object { $_ -match 'Nerd-Font|-NF-' } | 
    Sort-Object

if ($nerdFonts.Count -eq 0) {
    Write-Host "Nenhuma Nerd Font encontrada no bucket." -ForegroundColor Yellow
    exit 0
}

Write-Host "`nEncontradas $($nerdFonts.Count) Nerd Fonts:" -ForegroundColor Green
$nerdFonts | ForEach-Object { Write-Host "  - $_" }

# Pergunta ao usuário se deseja continuar
Write-Host "`nDeseja instalar todas as $($nerdFonts.Count) Nerd Fonts? (S/N)" -ForegroundColor Yellow
$response = Read-Host
if ($response -notmatch '^[SsYy]') {
    Write-Host "Instalação cancelada pelo usuário." -ForegroundColor Yellow
    exit 0
}

# Instala cada Nerd Font
Write-Host "`nIniciando instalação das Nerd Fonts..." -ForegroundColor Cyan
$installed = 0
$failed = 0

foreach ($font in $nerdFonts) {
    Write-Host "`nInstalando $font..." -ForegroundColor Cyan
    
    scoop install "nerd-fonts/$font"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ $font instalada com sucesso!" -ForegroundColor Green
        $installed++
    } else {
        Write-Host "✗ Erro ao instalar $font" -ForegroundColor Red
        $failed++
    }
}

# Resumo final
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Instalação concluída!" -ForegroundColor Cyan
Write-Host "Fontes instaladas com sucesso: $installed" -ForegroundColor Green
Write-Host "Fontes com erro: $failed" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Cyan
