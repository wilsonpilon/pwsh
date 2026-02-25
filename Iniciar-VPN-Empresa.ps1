# 1. Verifica e solicita privilégios de Administrador automaticamente
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Solicitando privilégios de Administrador para gerenciar os serviços de rede..."
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   Gerenciador de VPN: Modo Corporativo  " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# 2. Desativa os serviços do CyberGhost
Write-Host "[*] Desativando a blindagem do CyberGhost..." -ForegroundColor Yellow
Stop-Service -Name "CGVPNSvc", "CyberGhost.Service" -Force -ErrorAction SilentlyContinue

# 3. Inicia o OpenVPN Connect
Write-Host "[*] Iniciando o OpenVPN Connect..." -ForegroundColor Green
$ovpnPath = "C:\Program Files\OpenVPN Connect\OpenVPNConnect.exe"

if (Test-Path $ovpnPath) {
    Start-Process -FilePath $ovpnPath
} else {
    Write-Host "[!] OpenVPN Connect não encontrado no caminho padrão. Inicie-o manualmente." -ForegroundColor Red
}

Write-Host ""
Write-Host ">>> REDE LIBERADA <<<" -ForegroundColor Cyan
Write-Host "Conecte-se normalmente à rede da empresa pelo OpenVPN."
Write-Host ""

# 4. Pausa a execução aguardando o fim do seu expediente/uso
Read-Host "Pressione [ENTER] aqui APÓS DESCONECTAR da empresa para religar o CyberGhost"

# 5. Derruba processos residuais do OpenVPN (evita estados fantasmas futuros)
Write-Host "[*] Encerrando processos residuais do OpenVPN..." -ForegroundColor Yellow
Stop-Process -Name "OpenVPNConnect", "ovpnagent" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "OpenVPNConnectService" -Force -ErrorAction SilentlyContinue

# 6. Reativa os serviços do CyberGhost
Write-Host "[*] Reativando o motor e o Kill Switch do CyberGhost..." -ForegroundColor Green
Start-Service -Name "CGVPNSvc" -ErrorAction SilentlyContinue
Start-Service -Name "CyberGhost.Service" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   CyberGhost reativado com sucesso!      " -ForegroundColor Cyan
Write-Host "   A janela será fechada em 5 segundos.   " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Start-Sleep -Seconds 5