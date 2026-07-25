# Utilitário para Ejetar Flash Drives USB com Segurança
# PowerShell 7+

param(
    [Parameter(Mandatory = $false)]
    [string]$DriveLetter,
    
    [Parameter(Mandatory = $false)]
    [switch]$List
)

function Get-USBDrives {
    <#
    .SYNOPSIS
    Lista todos os flash drives USB conectados
    #>
    $usbDrives = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.Size -gt 0 }
    
    if ($usbDrives) {
        $usbDrives | Select-Object @{Name='Letra'; Expression={$_.DriveLetter}}, 
                                   @{Name='Nome'; Expression={$_.FileSystemLabel}},
                                   @{Name='Capacidade'; Expression={"{0:N2} GB" -f ($_.Size / 1GB)}},
                                   @{Name='Espaço Livre'; Expression={"{0:N2} GB" -f ($_.SizeRemaining / 1GB)}}
    } else {
        Write-Host "Nenhum flash drive USB encontrado." -ForegroundColor Yellow
    }
}

function Eject-USBDrive {
    <#
    .SYNOPSIS
    Ejeta um flash drive USB com segurança
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Drive
    )
    
    $Drive = $Drive.ToUpper()
    
    # Verificar se a letra da unidade é válida
    if ($Drive -notmatch '^[A-Z]$') {
        Write-Host "Letra de unidade inválida: $Drive" -ForegroundColor Red
        return $false
    }
    
    # Verificar se a unidade existe
    $volume = Get-Volume | Where-Object { $_.DriveLetter -eq $Drive }
    
    if (-not $volume) {
        Write-Host "Unidade $Drive`: não encontrada." -ForegroundColor Red
        return $false
    }
    
    if ($volume.DriveType -ne 'Removable') {
        Write-Host "A unidade $Drive`: não é um dispositivo removível." -ForegroundColor Red
        return $false
    }
    
    try {
        # Fechar arquivos abertos na unidade
        Write-Host "Fechando arquivos abertos..." -ForegroundColor Cyan
        Get-Process | Where-Object {
            try { $null -ne ($_.Modules | Where-Object { $_.FileName -like "$Drive`:\*" }) }
            catch { $false }
        } | ForEach-Object { $_.CloseMainWindow() }
        
        Start-Sleep -Milliseconds 500
        
        Write-Host "Preparando ejeção de $Drive`:\..." -ForegroundColor Cyan
        
        $removalPolicy = @"
using System;
using System.Runtime.InteropServices;

public class RemovalPolicy
{
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
    
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern bool DeviceIoControl(IntPtr hDevice, uint dwIoControlCode, IntPtr lpInBuffer, uint nInBufferSize, IntPtr lpOutBuffer, uint nOutBufferSize, out uint lpBytesReturned, IntPtr lpOverlapped);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);
    
    private const uint FILE_SHARE_READ = 1;
    private const uint FILE_SHARE_WRITE = 2;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_ATTRIBUTE_NORMAL = 0x80;
    private const uint IOCTL_STORAGE_EJECT_MEDIA = 0x2D4808;
    
    public static bool EjectDrive(char driveLetter)
    {
        IntPtr hFile = CreateFileW(@"\\.\" + driveLetter + ":", 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        
        if (hFile == IntPtr.Zero || hFile == new IntPtr(-1)) return false;
        
        uint dummy = 0;
        bool result = DeviceIoControl(hFile, IOCTL_STORAGE_EJECT_MEDIA, IntPtr.Zero, 0, IntPtr.Zero, 0, out dummy, IntPtr.Zero);
        
        CloseHandle(hFile);
        return result;
    }
}
"@
        
        if (-not ('RemovalPolicy' -as [type])) {
            Add-Type -TypeDefinition $removalPolicy
        }
        
        $result = [RemovalPolicy]::EjectDrive($Drive)
        
        if ($result) {
            Write-Host "✓ Unidade $Drive`: ejetada com segurança!" -ForegroundColor Green
            return $true
        } else {
            Write-Host "✗ Falha ao ejetar a unidade $Drive`:" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "Erro: $_" -ForegroundColor Red
        return $false
    }
}

# Main
if ($List) {
    Write-Host "`n=== Flash Drives USB Conectados ===" -ForegroundColor Cyan
    Get-USBDrives
    Write-Host ""
} elseif ($DriveLetter) {
    Write-Host "`n=== Ejetar Flash Drive ===" -ForegroundColor Cyan
    Eject-USBDrive -Drive $DriveLetter
    Write-Host ""
} else {
    Write-Host "`nUso:`n" -ForegroundColor Cyan
    Write-Host "  ./Eject-USB-Drive.ps1 -List                # Listar drives USB"
    Write-Host "  ./Eject-USB-Drive.ps1 -DriveLetter 'E'    # Ejetar unidade E:`n"
}
