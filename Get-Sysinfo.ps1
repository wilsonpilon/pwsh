# Script para listar informações principais da máquina

Write-Host "=== INFORMAÇÕES DO SISTEMA ===" -ForegroundColor Cyan

# Versão do Windows
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
Write-Host "Windows Version: $($osInfo.Caption)" -ForegroundColor Green
Write-Host "Build: $($osInfo.BuildNumber)" -ForegroundColor Green

# Versão do PowerShell
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Green

# Edição do Windows (Pro, Home, etc.)
$edition = (Get-CimInstance -ClassName Win32_OperatingSystem).OperatingSystemSKU
Write-Host "Windows Edition: $edition" -ForegroundColor Green

# Nome da máquina na rede
Write-Host "Computer Name: $env:COMPUTERNAME" -ForegroundColor Green

# IP Principal
$ipConfig = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object {$_.IPAddress -and $_.IPAddress.Count -gt 0} | Select-Object -First 1
Write-Host "IP Principal: $($ipConfig.IPAddress[0])" -ForegroundColor Green

# Processador
$processor = Get-CimInstance -ClassName Win32_Processor
Write-Host "Processador: $($processor.Name)" -ForegroundColor Green
Write-Host "Núcleos: $($processor.NumberOfCores) | Threads: $($processor.NumberOfLogicalProcessors)" -ForegroundColor Green

# Memória Física
$memory = Get-CimInstance -ClassName Win32_ComputerSystem
$memoryGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
Write-Host "Memória Física: $memoryGB GB" -ForegroundColor Green

# Tamanho dos Discos
Write-Host "Discos:" -ForegroundColor Green
Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object {$_.DriveType -eq 3} | ForEach-Object {
    $sizeGB = [math]::Round($_.Size / 1GB, 2)
    $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)
    Write-Host "  $($_.Name) - Total: $sizeGB GB | Livre: $freeGB GB" -ForegroundColor Yellow
}

# Resolução da Tela
$screen = Get-CimInstance -ClassName Win32_VideoController
Write-Host "Placa de Vídeo: $($screen.Name)" -ForegroundColor Green

$resolution = Get-CimInstance -ClassName Win32_DisplayConfiguration | Select-Object -First 1
Write-Host "Resolução: $($resolution.PelsWidth) x $($resolution.PelsHeight)" -ForegroundColor Green
