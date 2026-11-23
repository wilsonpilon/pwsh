#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('doctor','help')]
    [string]$Command = 'help'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Script:AppName = 'BrowserProfileSync'
$Script:Version = '0.1.4'

function Write-BpsHeader {
    Write-Host ''
    Write-Host "$Script:AppName $Script:Version" -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor DarkGray
    Write-Host ''
}

function Write-BpsCheck {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('PASS','WARN','FAIL','INFO','TODO')][string]$Result,
        [string]$Detail = ''
    )
    $color = switch ($Result) {
        'PASS' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        'INFO' { 'Cyan' }
        'TODO' { 'DarkYellow' }
        default { 'White' }
    }
    Write-Host ('{0,-22}' -f $Name) -NoNewline
    Write-Host ('{0,-8}' -f "[$Result]") -ForegroundColor $color
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host (' ' * 24 + $Detail) -ForegroundColor DarkGray
    }
}

function Test-BpsPowerShell {
    try {
        $version = $PSVersionTable.PSVersion
        $edition = $PSVersionTable.PSEdition
        $architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
        if ($version.Major -lt 7) {
            Write-BpsCheck -Name 'PowerShell' -Result 'FAIL' -Detail "Version $version | $edition | $architecture"
            return
        }
        if ($edition -ne 'Core') {
            Write-BpsCheck -Name 'PowerShell' -Result 'WARN' -Detail "Version $version | $edition | $architecture"
            return
        }
        Write-BpsCheck -Name 'PowerShell' -Result 'PASS' -Detail "Version $version | $edition | $architecture"
    }
    catch {
        Write-BpsCheck -Name 'PowerShell' -Result 'FAIL' -Detail $_.Exception.Message
    }
}

function Test-BpsWindows {
    try {
        if (-not $IsWindows) {
            Write-BpsCheck -Name 'Windows' -Result 'FAIL' -Detail 'BrowserProfileSync currently requires Windows.'
            return
        }
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        Write-BpsCheck -Name 'Windows' -Result 'PASS' -Detail "$($os.Caption) | Version $($os.Version) | Build $($os.BuildNumber) | $($os.OSArchitecture)"
        Write-BpsCheck -Name 'Computer' -Result 'INFO' -Detail ([System.Environment]::MachineName)
    }
    catch {
        Write-BpsCheck -Name 'Windows' -Result 'FAIL' -Detail $_.Exception.Message
    }
}

function Get-BpsOneDriveRoots {
    $roots = [System.Collections.Generic.List[object]]::new()
    $candidates = @(
        @{ Variable = 'OneDriveConsumer'; Type = 'Personal' },
        @{ Variable = 'OneDriveCommercial'; Type = 'Business' },
        @{ Variable = 'OneDrive'; Type = 'Unknown' }
    )
    foreach ($candidate in $candidates) {
        $value = [System.Environment]::GetEnvironmentVariable($candidate.Variable, [System.EnvironmentVariableTarget]::Process)
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $roots.Add([PSCustomObject]@{
            Type = $candidate.Type
            Path = $value
            Source = $candidate.Variable
            Exists = Test-Path -LiteralPath $value -PathType Container
        })
    }
    $uniqueRoots = @{}
    foreach ($root in $roots) {
        $normalizedPath = $root.Path.TrimEnd('\')
        if (-not $uniqueRoots.ContainsKey($normalizedPath)) {
            $uniqueRoots[$normalizedPath] = [PSCustomObject]@{
                Type = $root.Type
                Path = $normalizedPath
                Sources = @($root.Source)
                Exists = $root.Exists
            }
            continue
        }
        $existing = $uniqueRoots[$normalizedPath]
        $existing.Sources += $root.Source
        if (($existing.Type -eq 'Unknown') -and ($root.Type -ne 'Unknown')) {
            $existing.Type = $root.Type
        }
    }
    return @($uniqueRoots.Values | Sort-Object Type, Path)
}

function Test-BpsOneDrive {
    try {
        $roots = @(Get-BpsOneDriveRoots)
        if ($roots.Count -eq 0) {
            Write-BpsCheck -Name 'OneDrive' -Result 'WARN' -Detail 'No OneDrive roots were detected.'
            return
        }
        Write-BpsCheck -Name 'OneDrive' -Result 'PASS' -Detail "$($roots.Count) root(s) detected."
        foreach ($root in $roots) {
            $status = if ($root.Exists) { 'PASS' } else { 'WARN' }
            Write-BpsCheck -Name "  $($root.Type)" -Result $status -Detail $root.Path
            Write-BpsCheck -Name '    Source' -Result 'INFO' -Detail ($root.Sources -join ', ')
        }
    }
    catch {
        Write-BpsCheck -Name 'OneDrive' -Result 'FAIL' -Detail $_.Exception.Message
    }
}

function Test-BpsBackupLocation {
    Write-BpsCheck -Name 'Backup location' -Result 'TODO' -Detail 'Backup path validation not implemented yet.'
}

function Get-BpsBrowserInfo {
    param(
        [Parameter(Mandatory)][ValidateSet('Edge','Chrome','Vivaldi')][string]$Browser
    )

    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')

    switch ($Browser) {
        'Edge' {
            $displayName = 'Microsoft Edge'
            $userData = Join-Path $localAppData 'Microsoft\Edge\User Data'
            $candidates = @(
                (Join-Path $programFiles 'Microsoft\Edge\Application\msedge.exe'),
                (Join-Path $programFilesX86 'Microsoft\Edge\Application\msedge.exe'),
                (Join-Path $localAppData 'Microsoft\Edge\Application\msedge.exe')
            )
        }
        'Chrome' {
            $displayName = 'Google Chrome'
            $userData = Join-Path $localAppData 'Google\Chrome\User Data'
            $candidates = @(
                (Join-Path $programFiles 'Google\Chrome\Application\chrome.exe'),
                (Join-Path $programFilesX86 'Google\Chrome\Application\chrome.exe'),
                (Join-Path $localAppData 'Google\Chrome\Application\chrome.exe')
            )
        }
        'Vivaldi' {
            $displayName = 'Vivaldi'
            $userData = Join-Path $localAppData 'Vivaldi\User Data'
            $candidates = @(
                (Join-Path $localAppData 'Vivaldi\Application\vivaldi.exe'),
                (Join-Path $programFiles 'Vivaldi\Application\vivaldi.exe'),
                (Join-Path $programFilesX86 'Vivaldi\Application\vivaldi.exe')
            )
        }
    }

    $exePath = $null
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $exePath = $candidate
            break
        }
    }

    $version = $null
    if ($null -ne $exePath) {
        try {
            $version = (Get-Item -LiteralPath $exePath).VersionInfo.ProductVersion
        }
        catch {
            $version = $null
        }
    }

    [PSCustomObject]@{
        Name = $displayName
        Executable = $exePath
        Version = $version
        UserData = $userData
        UserDataExists = Test-Path -LiteralPath $userData -PathType Container
    }
}

function Test-BpsBrowser {
    param(
        [Parameter(Mandatory)][ValidateSet('Edge','Chrome','Vivaldi')][string]$Browser
    )

    try {
        $info = Get-BpsBrowserInfo -Browser $Browser

        if ($null -ne $info.Executable) {
            $detail = $info.Executable
            if (-not [string]::IsNullOrWhiteSpace($info.Version)) {
                $detail = "Version $($info.Version) | $detail"
            }
            Write-BpsCheck -Name $info.Name -Result 'PASS' -Detail $detail
        }
        elseif ($info.UserDataExists) {
            Write-BpsCheck -Name $info.Name -Result 'WARN' -Detail 'Executable not found in standard locations; User Data exists.'
        }
        else {
            Write-BpsCheck -Name $info.Name -Result 'WARN' -Detail 'Browser not detected in standard locations.'
            return
        }

        $userDataStatus = if ($info.UserDataExists) { 'PASS' } else { 'WARN' }
        Write-BpsCheck -Name '  User Data' -Result $userDataStatus -Detail $info.UserData
    }
    catch {
        $name = switch ($Browser) { 'Edge' { 'Microsoft Edge' } 'Chrome' { 'Google Chrome' } 'Vivaldi' { 'Vivaldi' } }
        Write-BpsCheck -Name $name -Result 'FAIL' -Detail $_.Exception.Message
    }
}

function Test-BpsEdge { Test-BpsBrowser -Browser 'Edge' }
function Test-BpsChrome { Test-BpsBrowser -Browser 'Chrome' }
function Test-BpsVivaldi { Test-BpsBrowser -Browser 'Vivaldi' }

function Test-BpsBrowserProcesses {
    try {
        $definitions = @(
            @{ Name = 'Microsoft Edge'; Process = 'msedge' },
            @{ Name = 'Google Chrome'; Process = 'chrome' },
            @{ Name = 'Vivaldi'; Process = 'vivaldi' }
        )

        $running = [System.Collections.Generic.List[object]]::new()

        foreach ($definition in $definitions) {
            $processes = @(Get-Process -Name $definition.Process -ErrorAction SilentlyContinue)
            if ($processes.Count -gt 0) {
                $running.Add([PSCustomObject]@{
                    Name = $definition.Name
                    Count = $processes.Count
                })
            }
        }

        if ($running.Count -eq 0) {
            Write-BpsCheck -Name 'Browser processes' -Result 'PASS' -Detail 'No supported browsers are running.'
            return
        }

        Write-BpsCheck -Name 'Browser processes' -Result 'WARN' -Detail 'One or more supported browsers are running.'
        foreach ($item in $running) {
            Write-BpsCheck -Name "  $($item.Name)" -Result 'INFO' -Detail "$($item.Count) process(es)"
        }
    }
    catch {
        Write-BpsCheck -Name 'Browser processes' -Result 'FAIL' -Detail $_.Exception.Message
    }
}

function Test-BpsBrowserProfiles {
    Write-BpsCheck -Name 'Browser profiles' -Result 'TODO' -Detail 'Profile discovery not implemented yet.'
}

function Test-BpsLocalStorage {
    Write-BpsCheck -Name 'Local storage' -Result 'TODO' -Detail 'IndexedDB/Local Storage detection not implemented yet.'
}

function Invoke-BpsDoctor {
    Write-BpsHeader
    Write-Host 'System' -ForegroundColor White
    Write-Host '------' -ForegroundColor DarkGray
    Test-BpsPowerShell
    Test-BpsWindows

    Write-Host ''
    Write-Host 'Storage' -ForegroundColor White
    Write-Host '-------' -ForegroundColor DarkGray
    Test-BpsOneDrive
    Test-BpsBackupLocation

    Write-Host ''
    Write-Host 'Browsers' -ForegroundColor White
    Write-Host '--------' -ForegroundColor DarkGray
    Test-BpsEdge
    Test-BpsChrome
    Test-BpsVivaldi
    Test-BpsBrowserProcesses

    Write-Host ''
    Write-Host 'Profiles' -ForegroundColor White
    Write-Host '--------' -ForegroundColor DarkGray
    Test-BpsBrowserProfiles
    Test-BpsLocalStorage

    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Doctor completed.' -ForegroundColor Cyan
    Write-Host 'No files were modified.' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-BpsHelp {
    Write-BpsHeader
    Write-Host 'Usage:'
    Write-Host ''
    Write-Host '  pwsh -File .\BrowserProfileSync.ps1 <command>'
    Write-Host ''
    Write-Host 'Commands:'
    Write-Host ''
    Write-Host '  doctor    Check environment and browser configuration'
    Write-Host '  help      Show this help'
    Write-Host ''
}

try {
    switch ($Command) {
        'doctor' { Invoke-BpsDoctor }
        'help' { Show-BpsHelp }
        default { Show-BpsHelp }
    }
    exit 0
}
catch {
    Write-Host ''
    Write-Host 'BrowserProfileSync encountered an unexpected error.' -ForegroundColor Red
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    exit 1
}
