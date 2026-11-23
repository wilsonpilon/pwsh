#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Position=0)][ValidateSet('doctor','help')][string]$Command='help')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Script:AppName='BrowserProfileSync'
$Script:Version='0.1.6'
function Write-BpsHeader { Write-Host ''; Write-Host "$Script:AppName $Script:Version" -ForegroundColor Cyan; Write-Host ('='*60) -ForegroundColor DarkGray; Write-Host '' }
function Write-BpsCheck { param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][ValidateSet('PASS','WARN','FAIL','INFO','TODO')][string]$Result,[string]$Detail=''); $c=switch($Result){PASS{'Green'} WARN{'Yellow'} FAIL{'Red'} INFO{'Cyan'} TODO{'DarkYellow'}}; Write-Host ('{0,-30}' -f $Name) -NoNewline; Write-Host ('{0,-8}' -f "[$Result]") -ForegroundColor $c; if(-not [string]::IsNullOrWhiteSpace($Detail)){Write-Host (' '*32+$Detail) -ForegroundColor DarkGray} }
function Test-BpsPowerShell { try {$v=$PSVersionTable.PSVersion;$e=$PSVersionTable.PSEdition;$a=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture;$r=if($v.Major-lt 7){'FAIL'}elseif($e-ne'Core'){'WARN'}else{'PASS'};Write-BpsCheck 'PowerShell' $r "Version $v | $e | $a"}catch{Write-BpsCheck 'PowerShell' 'FAIL' $_.Exception.Message} }
function Test-BpsWindows { try {if(-not $IsWindows){Write-BpsCheck 'Windows' 'FAIL' 'BrowserProfileSync currently requires Windows.';return};$os=Get-CimInstance Win32_OperatingSystem;Write-BpsCheck 'Windows' 'PASS' "$($os.Caption) | Version $($os.Version) | Build $($os.BuildNumber) | $($os.OSArchitecture)";Write-BpsCheck 'Computer' 'INFO' ([Environment]::MachineName)}catch{Write-BpsCheck 'Windows' 'FAIL' $_.Exception.Message} }
function Get-BpsOneDriveRoots { $r=@();foreach($x in @(@{V='OneDriveConsumer';T='Personal'},@{V='OneDriveCommercial';T='Business'},@{V='OneDrive';T='Unknown'})){$p=[Environment]::GetEnvironmentVariable($x.V,'Process');if(-not [string]::IsNullOrWhiteSpace($p)){$r+=[pscustomobject]@{Type=$x.T;Path=$p.TrimEnd('\');Source=$x.V;Exists=Test-Path -LiteralPath $p -PathType Container}}};$r|Sort-Object Path -Unique }
function Test-BpsOneDrive { try {$r=@(Get-BpsOneDriveRoots);if(!$r.Count){Write-BpsCheck 'OneDrive' 'WARN' 'No OneDrive roots were detected.';return};Write-BpsCheck 'OneDrive' 'PASS' "$($r.Count) root(s) detected.";foreach($x in $r){Write-BpsCheck "  $($x.Type)" $(if($x.Exists){'PASS'}else{'WARN'}) $x.Path}}catch{Write-BpsCheck 'OneDrive' 'FAIL' $_.Exception.Message} }
function Test-BpsBackupLocation { Write-BpsCheck 'Backup location' 'TODO' 'Backup path validation not implemented yet.' }
function Get-BpsBrowserInfo { param([Parameter(Mandatory)][ValidateSet('Edge','Chrome','Vivaldi')][string]$Browser);$la=[Environment]::GetFolderPath('LocalApplicationData');$pf=[Environment]::GetFolderPath('ProgramFiles');$px=[Environment]::GetFolderPath('ProgramFilesX86');switch($Browser){Edge{$n='Microsoft Edge';$u=Join-Path $la 'Microsoft\Edge\User Data';$c=@((Join-Path $pf 'Microsoft\Edge\Application\msedge.exe'),(Join-Path $px 'Microsoft\Edge\Application\msedge.exe'),(Join-Path $la 'Microsoft\Edge\Application\msedge.exe'))}Chrome{$n='Google Chrome';$u=Join-Path $la 'Google\Chrome\User Data';$c=@((Join-Path $pf 'Google\Chrome\Application\chrome.exe'),(Join-Path $px 'Google\Chrome\Application\chrome.exe'),(Join-Path $la 'Google\Chrome\Application\chrome.exe'))}Vivaldi{$n='Vivaldi';$u=Join-Path $la 'Vivaldi\User Data';$c=@((Join-Path $la 'Vivaldi\Application\vivaldi.exe'),(Join-Path $pf 'Vivaldi\Application\vivaldi.exe'),(Join-Path $px 'Vivaldi\Application\vivaldi.exe'))}};$exe=$c|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1;$ver=if($exe){(Get-Item -LiteralPath $exe).VersionInfo.ProductVersion}else{$null};[pscustomobject]@{Name=$n;Executable=$exe;Version=$ver;UserData=$u;UserDataExists=Test-Path -LiteralPath $u -PathType Container} }
function Test-BpsBrowser { param([ValidateSet('Edge','Chrome','Vivaldi')][string]$Browser);try{$i=Get-BpsBrowserInfo $Browser;if($i.Executable){Write-BpsCheck $i.Name 'PASS' "Version $($i.Version) | $($i.Executable)"}elseif($i.UserDataExists){Write-BpsCheck $i.Name 'WARN' 'Executable not found in standard locations; User Data exists.'}else{Write-BpsCheck $i.Name 'WARN' 'Browser not detected in standard locations.';return};Write-BpsCheck '  User Data' $(if($i.UserDataExists){'PASS'}else{'WARN'}) $i.UserData}catch{Write-BpsCheck $Browser 'FAIL' $_.Exception.Message} }
function Test-BpsEdge {Test-BpsBrowser Edge};function Test-BpsChrome {Test-BpsBrowser Chrome};function Test-BpsVivaldi {Test-BpsBrowser Vivaldi}
function Test-BpsBrowserProcesses {try{$defs=@(@{N='Microsoft Edge';P='msedge'},@{N='Google Chrome';P='chrome'},@{N='Vivaldi';P='vivaldi'});$run=@();foreach($d in $defs){$p=@(Get-Process -Name $d.P -ErrorAction SilentlyContinue);if($p.Count){$run+=[pscustomobject]@{Name=$d.N;Count=$p.Count}}};if(!$run.Count){Write-BpsCheck 'Browser processes' 'PASS' 'No supported browsers are running.';return};Write-BpsCheck 'Browser processes' 'WARN' 'One or more supported browsers are running.';foreach($x in $run){Write-BpsCheck "  $($x.Name)" 'INFO' "$($x.Count) process(es)"}}catch{Write-BpsCheck 'Browser processes' 'FAIL' $_.Exception.Message} }
function Get-BpsBrowserProfiles {param([ValidateSet('Edge','Chrome','Vivaldi')][string]$Browser);$i=Get-BpsBrowserInfo $Browser;if(-not $i.UserDataExists){return @()};$names=@{};$ls=Join-Path $i.UserData 'Local State';if(Test-Path -LiteralPath $ls -PathType Leaf){try{$j=Get-Content -LiteralPath $ls -Raw -Encoding UTF8|ConvertFrom-Json;if($j.profile.info_cache){foreach($p in $j.profile.info_cache.PSObject.Properties){if($p.Value.name){$names[$p.Name]=[string]$p.Value.name}}}}catch{}};$dirs=@(Get-ChildItem -LiteralPath $i.UserData -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name-eq'Default'-or $_.Name-match'^Profile [0-9]+$'}|Sort-Object @{Expression={if($_.Name-eq'Default'){0}else{1}}},Name);@($dirs|ForEach-Object{[pscustomobject]@{Browser=$i.Name;DirectoryName=$_.Name;FriendlyName=$(if($names.ContainsKey($_.Name)){$names[$_.Name]}else{$null});Path=$_.FullName}}) }
function Test-BpsBrowserProfiles {try{$total=0;foreach($b in @('Edge','Chrome','Vivaldi')){$i=Get-BpsBrowserInfo $b;if(-not $i.UserDataExists){continue};$p=@(Get-BpsBrowserProfiles $b);$total+=$p.Count;if(!$p.Count){Write-BpsCheck $i.Name 'WARN' 'User Data exists, but no standard profiles were detected.';continue};Write-BpsCheck $i.Name 'PASS' "$($p.Count) profile(s) detected.";foreach($x in $p){$d=$x.DirectoryName;if(-not [string]::IsNullOrWhiteSpace($x.FriendlyName)){$d="$d - $($x.FriendlyName)"};Write-BpsCheck "  $d" 'PASS' $x.Path}};if(!$total){Write-BpsCheck 'Browser profiles' 'WARN' 'No standard Chromium profiles were detected.'}}catch{Write-BpsCheck 'Browser profiles' 'FAIL' $_.Exception.Message} }
function Get-BpsPathSize {
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            return [int64](Get-Item -LiteralPath $Path -ErrorAction Stop).Length
        }
        if (Test-Path -LiteralPath $Path -PathType Container) {
            $sum = (Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sum) { return [int64]0 }
            return [int64]$sum
        }
    } catch {}
    return [int64]0
}
function Format-BpsSize {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}
function Write-BpsDataItem {
    param([string]$Name,[string]$Path)
    $exists = Test-Path -LiteralPath $Path
    if ($exists) {
        $bytes = Get-BpsPathSize -Path $Path
        Write-BpsCheck -Name "    $Name" -Result 'PASS' -Detail "$(Format-BpsSize $bytes) | $Path"
    } else {
        Write-BpsCheck -Name "    $Name" -Result 'INFO' -Detail 'Not present'
    }
}
function Test-BpsLocalStorage {
    try {
        Write-BpsCheck -Name 'Local storage' -Result 'INFO' -Detail 'Read-only inventory of Chromium profile data.'
        foreach ($browser in @('Edge','Chrome','Vivaldi')) {
            $bi = Get-BpsBrowserInfo $browser
            if (-not $bi.UserDataExists) { continue }
            $profiles = @(Get-BpsBrowserProfiles $browser)
            foreach ($profile in $profiles) {
                $label = $profile.DirectoryName
                if (-not [string]::IsNullOrWhiteSpace($profile.FriendlyName)) { $label += " - $($profile.FriendlyName)" }
                Write-BpsCheck -Name "$($bi.Name) / $label" -Result 'INFO' -Detail $profile.Path
                Write-BpsCheck -Name '  Web application data' -Result 'INFO' -Detail ''
                Write-BpsDataItem 'IndexedDB' (Join-Path $profile.Path 'IndexedDB')
                Write-BpsDataItem 'Local Storage' (Join-Path $profile.Path 'Local Storage')
                Write-BpsDataItem 'Session Storage' (Join-Path $profile.Path 'Session Storage')
                Write-BpsDataItem 'WebStorage' (Join-Path $profile.Path 'WebStorage')
                Write-BpsDataItem 'Service Worker' (Join-Path $profile.Path 'Service Worker')
                Write-BpsCheck -Name '  Browser databases' -Result 'INFO' -Detail ''
                Write-BpsDataItem 'Cookies' (Join-Path $profile.Path 'Network\Cookies')
                Write-BpsDataItem 'History' (Join-Path $profile.Path 'History')
                Write-BpsDataItem 'Login Data' (Join-Path $profile.Path 'Login Data')
                Write-BpsDataItem 'Web Data' (Join-Path $profile.Path 'Web Data')
                Write-BpsDataItem 'Favicons' (Join-Path $profile.Path 'Favicons')
                Write-BpsDataItem 'Preferences' (Join-Path $profile.Path 'Preferences')
                Write-BpsDataItem 'Secure Preferences' (Join-Path $profile.Path 'Secure Preferences')
            }
        }
    } catch {
        Write-BpsCheck -Name 'Local storage' -Result 'FAIL' -Detail $_.Exception.Message
    }
}
function Invoke-BpsDoctor {Write-BpsHeader;Write-Host 'System';Write-Host '------' -ForegroundColor DarkGray;Test-BpsPowerShell;Test-BpsWindows;Write-Host '';Write-Host 'Storage';Write-Host '-------' -ForegroundColor DarkGray;Test-BpsOneDrive;Test-BpsBackupLocation;Write-Host '';Write-Host 'Browsers';Write-Host '--------' -ForegroundColor DarkGray;Test-BpsEdge;Test-BpsChrome;Test-BpsVivaldi;Test-BpsBrowserProcesses;Write-Host '';Write-Host 'Profiles';Write-Host '--------' -ForegroundColor DarkGray;Test-BpsBrowserProfiles;Test-BpsLocalStorage;Write-Host '';Write-Host ('='*60) -ForegroundColor DarkGray;Write-Host '';Write-Host 'Doctor completed.' -ForegroundColor Cyan;Write-Host 'No files were modified.' -ForegroundColor DarkGray;Write-Host ''}
function Show-BpsHelp {Write-BpsHeader;Write-Host 'Usage:';Write-Host '  pwsh -File .\BrowserProfileSync.ps1 <command>';Write-Host '';Write-Host 'Commands:';Write-Host '  doctor    Check environment and browser configuration';Write-Host '  help      Show this help'}
try{switch($Command){doctor{Invoke-BpsDoctor}help{Show-BpsHelp}};exit 0}catch{Write-Host '';Write-Host 'BrowserProfileSync encountered an unexpected error.' -ForegroundColor Red;Write-Host $_.Exception.Message -ForegroundColor Red;exit 1}
