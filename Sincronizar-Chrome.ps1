# ==============================================================================
# CONFIGURAÇÃO: Vincule as pastas do Chrome aos remotes criados no 'rclone config'
# ==============================================================================
$MapaNuvens = @{
    "Default"   = "onedrive_pessoal:Backups_Chrome/Pessoal"
    "Profile 1" = "onedrive_profissional:Backups_Chrome/Profissional"
    "Profile 2" = "onedrive_projeto:Backups_Chrome/Projeto"
}
# ==============================================================================

$ChromeUserData = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$LocalStatePath = Join-Path $ChromeUserData "Local State"

# Verifica se o Rclone está instalado
if (-not (Get-Command "rclone" -ErrorAction SilentlyContinue)) {
    Write-Host "Erro: Rclone não encontrado. Instale com: winget install Rclone.Rclone" -ForegroundColor Red
    Pause
    exit
}

# Tenta ler os nomes reais dos perfis se o Chrome já tiver sido aberto neste PC
$ProfilesInfo = $null
if (Test-Path $LocalStatePath) {
    $JsonData = Get-Content $LocalStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $ProfilesInfo = $JsonData.profile.info_cache
}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "       SINCRONIZADOR DE PERFIS DO CHROME (VENICE.AI)      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " O que você deseja fazer?" -ForegroundColor White
Write-Host " [1] ENVIAR para a nuvem (Fazer Backup deste PC)" -ForegroundColor Green
Write-Host " [2] BAIXAR da nuvem (Restaurar dados neste PC)" -ForegroundColor Yellow
Write-Host " [S] Sair" -ForegroundColor Gray
Write-Host ""

$Direcao = Read-Host "Escolha uma opção (1 ou 2)"
if ($Direcao -eq 'S' -or $Direcao -eq 's') { exit }
if ($Direcao -ne '1' -and $Direcao -ne '2') {
    Write-Host "Opção inválida." -ForegroundColor Red; Pause; exit
}

# Monta a lista de perfis com base no mapeamento configurado
$ListaPerfis = @()
$Index = 1

Write-Host "`n----------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " Selecione o perfil:" -ForegroundColor White

foreach ($PastaNome in $MapaNuvens.Keys | Sort-Object) {
    $DestinoNuvem = $MapaNuvens[$PastaNome]
    $NomeExibicao = $PastaNome

    # Se o perfil existir localmente, pega o nome amigável do Chrome
    if ($ProfilesInfo -and $ProfilesInfo.$PastaNome) {
        $NomeExibicao = "$($ProfilesInfo.$PastaNome.name) ($PastaNome)"
    }

    $ListaPerfis += [PSCustomObject]@{
        ID      = $Index
        Pasta   = $PastaNome
        Nome    = $NomeExibicao
        Nuvem   = $DestinoNuvem
    }

    Write-Host " [$Index] $NomeExibicao" -ForegroundColor Cyan
    Write-Host "     Nuvem: $DestinoNuvem" -ForegroundColor Gray
    $Index++
}

Write-Host " Sincronizar TODOS os 3 perfis" -ForegroundColor Magenta
Write-Host " [S] Sair`n" -ForegroundColor Gray

$EscolhaPerfil = Read-Host "Digite o número do perfil"
if ($EscolhaPerfil -eq 'S' -or $EscolhaPerfil -eq 's') { exit }

$PerfisSelecionados = @()
if ($EscolhaPerfil -eq '0') {
    $PerfisSelecionados = $ListaPerfis
} else {
    $Selecionado = $ListaPerfis | Where-Object { $_.ID -eq [int]$EscolhaPerfil }
    if ($null -eq $Selecionado) { Write-Host "Opção inválida." -ForegroundColor Red; Pause; exit }
    $PerfisSelecionados += $Selecionado
}

# Fecha o Chrome antes de qualquer operação para não corromper o IndexedDB
if (Get-Process chrome -ErrorAction SilentlyContinue) {
    Write-Host "`nFechando o Chrome para proteger os bancos do Venice.ai..." -ForegroundColor Magenta
    Stop-Process -Name chrome -Force
    Start-Sleep -Seconds 3
}

# Filtros para ignorar caches pesados e desnecessários
$Exclusoes = @(
    "--exclude", "Cache/**",
    "--exclude", "Code Cache/**",
    "--exclude", "GPUCache/**",
    "--exclude", "DawnCache/**",
    "--exclude", "GrShaderCache/**",
    "--exclude", "ShaderCache/**",
    "--exclude", "Service Worker/CacheStorage/**",
    "--exclude", "Service Worker/ScriptCache/**"
)

foreach ($Perfil in $PerfisSelecionados) {
    $CaminhoLocal = Join-Path $ChromeUserData $Perfil.Pasta
    $CaminhoNuvem = $Perfil.Nuvem

    if ($Direcao -eq '1') {
        # UPLOAD (PC -> Nuvem)
        if (-not (Test-Path $CaminhoLocal)) {
            Write-Host "`nAviso: A pasta local '$($Perfil.Pasta)' não existe neste PC. Pulando..." -ForegroundColor DarkYellow
            continue
        }
        Write-Host "`n[ENVIANDO] $($Perfil.Nome) -> $CaminhoNuvem" -ForegroundColor Green
        $ArgsRclone = @("sync", "`"$CaminhoLocal`"", "`"$CaminhoNuvem`"", "--progress") + $Exclusoes
    } else {
        # DOWNLOAD (Nuvem -> PC)
        if (-not (Test-Path $CaminhoLocal)) {
            New-Item -ItemType Directory -Path $CaminhoLocal -Force | Out-Null
        }
        Write-Host "`n[BAIXANDO] $CaminhoNuvem -> $($Perfil.Nome)" -ForegroundColor Yellow
        $ArgsRclone = @("sync", "`"$CaminhoNuvem`"", "`"$CaminhoLocal`"", "--progress") + $Exclusoes
    }

    Start-Process -FilePath "rclone" -ArgumentList $ArgsRclone -Wait -NoNewWindow
}

Write-Host "`nOperação concluída com sucesso!" -ForegroundColor Green
Pause
