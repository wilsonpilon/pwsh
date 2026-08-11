# Script to change Windows default font to JetBrainsMonoNL Nerd Font
# and export registry changes to a .REG file

param(
    [string]$FontName = 'JetBrainsMonoNL Nerd Font',
    [string]$RegFilePath = "$PSScriptRoot\Windows-Font-Change.reg"
)

function Test-IsAdministrator {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-FontInstalled {
    param(
        [string]$FontName
    )

    $fontRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

    if (-not (Test-Path -Path $fontRegistryPath)) {
        return $false
    }

    try {
        $fontEntries = Get-ItemProperty -Path $fontRegistryPath -ErrorAction Stop
        foreach ($prop in $fontEntries.PSObject.Properties) {
            if (($prop.Name -and $prop.Name -like "*$FontName*") -or ($prop.Value -and $prop.Value -like "*$FontName*")) {
                return $true
            }
        }

        return $false
    }
    catch {
        Write-Host "Unable to inspect the Windows font registry: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Export-FontRegistry {
    param(
        [string]$RegPath,
        [string]$FontName
    )

    $regContent = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Segoe UI"="$FontName"

[HKEY_CURRENT_USER\Console]
"FaceName"="$FontName"
"FontFamily"=dword:00000036
"FontSize"=dword:000c0010
"FontWeight"=dword:00000190

[HKEY_CURRENT_USER\Control Panel\Desktop]
"FontSmoothing"="2"
"FontSmoothingType"=dword:00000002

[HKEY_CURRENT_USER\Software\Microsoft\Notepad]
"lfFaceName"="$FontName"
"lfHeight"=dword:fffffff4
"lfWeight"=dword:00000190

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Arial"="$FontName"
"Tahoma"="$FontName"
"Microsoft Sans Serif"="$FontName"
"@

    Set-Content -Path $RegPath -Value $regContent -Encoding Unicode -Force
    Write-Host "Registry file created: $RegPath" -ForegroundColor Green
}

function Apply-FontChange {
    param(
        [string]$FontName
    )

    $isAdmin = Test-IsAdministrator

    try {
        Write-Host 'Applying font changes to registry...' -ForegroundColor Cyan

        if ($isAdmin) {
            $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
            New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
            Set-ItemProperty -Path $regPath -Name 'Segoe UI' -Value $FontName -Force
            Set-ItemProperty -Path $regPath -Name 'Arial' -Value $FontName -Force
            Set-ItemProperty -Path $regPath -Name 'Tahoma' -Value $FontName -Force
            Set-ItemProperty -Path $regPath -Name 'Microsoft Sans Serif' -Value $FontName -Force

            Write-Host "Font substitutions updated: Segoe UI, Arial, Tahoma, Microsoft Sans Serif -> $FontName" -ForegroundColor Green
        }
        else {
            Write-Host 'Warning: Administrator privileges are required to modify HKLM font substitutions. Those changes will be written to the .REG file instead.' -ForegroundColor Yellow
        }

        $regPath = 'HKCU:\Console'
        New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $regPath -Name 'FaceName' -Value $FontName -Force
        Set-ItemProperty -Path $regPath -Name 'FontFamily' -Value 54 -Force
        Set-ItemProperty -Path $regPath -Name 'FontSize' -Value 786448 -Force
        Set-ItemProperty -Path $regPath -Name 'FontWeight' -Value 400 -Force

        Write-Host "Console font updated: $FontName" -ForegroundColor Green

        $regPath = 'HKCU:\Software\Microsoft\Notepad'
        New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
        Set-ItemProperty -Path $regPath -Name 'lfFaceName' -Value $FontName -Force

        Write-Host "Notepad font updated: $FontName" -ForegroundColor Green
    }
    catch {
        Write-Host "Error applying registry changes: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    return $true
}

Write-Host "`n=== Windows Font Changer ===" -ForegroundColor Yellow
Write-Host "Font to apply: $FontName`n" -ForegroundColor Cyan

if (Test-FontInstalled -FontName $FontName) {
    Write-Host "Font '$FontName' appears to be installed." -ForegroundColor Green
}
else {
    Write-Host "Warning: Font '$FontName' may not be properly installed. Proceeding anyway..." -ForegroundColor Yellow
}

$success = Apply-FontChange -FontName $FontName

if ($success) {
    Export-FontRegistry -RegPath $RegFilePath -FontName $FontName
    Write-Host "`nFont changes completed successfully!" -ForegroundColor Green
    Write-Host "Registry file exported: $RegFilePath" -ForegroundColor Green
}
else {
    Write-Host "`nFailed to apply font changes." -ForegroundColor Red
    exit 1
}

Write-Host "`nNote: You may need to restart your applications for changes to take effect." -ForegroundColor Yellow
