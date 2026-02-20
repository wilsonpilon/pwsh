# Script to change Windows default font to JetBrainsMonoNL Nerd Font
# and export registry changes to a .REG file

param(
    [string]$FontName = "JetBrainsMonoNL Nerd Font",
    [string]$RegFilePath = "$PSScriptRoot\Windows-Font-Change.reg"
)

# Function to create registry file
function Export-FontRegistry {
    param(
        [string]$RegPath,
        [string]$FontName
    )
    
    $regContent = @"
Windows Registry Editor Version 5.00

; Font Substitution and Default Font Changes
; Replacing Segoe UI with $FontName

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Segoe UI"="$FontName"

; Console Font
[HKEY_CURRENT_USER\Console]
"FaceName"="$FontName"
"FontFamily"=dword:00000036
"FontSize"=dword:000c0010
"FontWeight"=dword:00000190

; Font Smoothing
[HKEY_CURRENT_USER\Control Panel\Desktop]
"FontSmoothing"="2"
"FontSmoothingType"=dword:00000002

; Notepad Font
[HKEY_CURRENT_USER\Software\Microsoft\Notepad]
"lfFaceName"="$FontName"
"lfHeight"=dword:fffffff4
"lfWeight"=dword:00000190

; Terminal Font
[HKEY_CURRENT_USER\Software\Microsoft\Windows Terminal\Profiles\%s]
"fontFace"="$FontName"
"fontSize"=11

; UI Font Changes
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts]

; Dialog Font
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion]

; Additional Font Substitutes
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Arial"="$FontName"
"Tahoma"="$FontName"
"Microsoft Sans Serif"="$FontName"

"@

    Set-Content -Path $RegPath -Value $regContent -Encoding Unicode -Force
    Write-Host "Registry file created: $RegPath" -ForegroundColor Green
}

# Function to apply registry changes
function Apply-FontChange {
    param(
        [string]$FontName
    )
    
    try {
        Write-Host "Applying font changes to registry..." -ForegroundColor Cyan
        
        # Font substitution
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes"
        New-Item -Path $regPath -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name "Segoe UI" -Value $FontName -Force
        Set-ItemProperty -Path $regPath -Name "Arial" -Value $FontName -Force
        Set-ItemProperty -Path $regPath -Name "Tahoma" -Value $FontName -Force
        Set-ItemProperty -Path $regPath -Name "Microsoft Sans Serif" -Value $FontName -Force
        
        Write-Host "Font substitutions updated: Segoe UI, Arial, Tahoma, Microsoft Sans Serif -> $FontName" -ForegroundColor Green
        
        # Current user console
        $regPath = "HKCU:\Console"
        New-Item -Path $regPath -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name "FaceName" -Value $FontName -Force
        Set-ItemProperty -Path $regPath -Name "FontFamily" -Value 54 -Force
        Set-ItemProperty -Path $regPath -Name "FontSize" -Value 786448 -Force
        Set-ItemProperty -Path $regPath -Name "FontWeight" -Value 400 -Force
        
        Write-Host "Console font updated: $FontName" -ForegroundColor Green
        
        # Notepad
        $regPath = "HKCU:\Software\Microsoft\Notepad"
        New-Item -Path $regPath -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name "lfFaceName" -Value $FontName -Force
        
        Write-Host "Notepad font updated: $FontName" -ForegroundColor Green
        
    }
    catch {
        Write-Host "Error applying registry changes: $_" -ForegroundColor Red
        return $false
    }
    
    return $true
}

# Main execution
Write-Host "`n=== Windows Font Changer ===" -ForegroundColor Yellow
Write-Host "Font to apply: $FontName`n" -ForegroundColor Cyan

# Check if font is installed
$fontPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
$installedFonts = Get-ItemProperty -Path $fontPath | Select-Object -ExpandProperty PSObject.Properties | Where-Object { $_.Value -like "*$FontName*" }

if (-not $installedFonts) {
    Write-Host "Warning: Font '$FontName' may not be properly installed. Proceeding anyway..." -ForegroundColor Yellow
}

# Apply changes to registry
$success = Apply-FontChange -FontName $FontName

if ($success) {
    # Export registry file
    Export-FontRegistry -RegPath $RegFilePath -FontName $FontName
    Write-Host "`n✓ Font changes completed successfully!" -ForegroundColor Green
    Write-Host "Registry file exported: $RegFilePath" -ForegroundColor Green
    Write-Host "`nYou can import this .REG file on other machines to replicate these changes." -ForegroundColor Cyan
}
else {
    Write-Host "`n✗ Failed to apply font changes." -ForegroundColor Red
    exit 1
}

# Optional: Import the registry file
$response = Read-Host "`nDo you want to import the registry file now? (Y/N)"
if ($response -eq 'Y' -or $response -eq 'y') {
    try {
        Write-Host "Importing registry file..." -ForegroundColor Cyan
        & reg import $RegFilePath
        Write-Host "Registry file imported successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "Error importing registry file: $_" -ForegroundColor Red
    }
}

Write-Host "`nNote: You may need to restart your applications for changes to take effect." -ForegroundColor Yellow
