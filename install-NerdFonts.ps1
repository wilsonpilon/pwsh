# Obtém os resultados da busca e seleciona apenas o nome dos pacotes
scoop bucket add nerd-fonts
$packages = scoop search NF-Mono | Select-Object -Skip 1 | ForEach-Object { $_.Name }
# Loop para instalar cada pacote encontrado
foreach ($package in $packages) {
    # Tenta instalar com Scoop
    if (scoop install $package) {
        Write-Host "Instalado com sucesso: $package"
    } else {
        # Se falhar, tenta instalar com Winget
        if (winget install $package) {
            Write-Host "Instalado com sucesso com Winget: $package"
        } else {
            Write-Host "Falha ao instalar: $package"
        }
    }
}