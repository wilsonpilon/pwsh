#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('doctor','backup','help')]
    [string]$Command='help',
    [string]$Destination
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Script:AppName='BrowserProfileSync'
$Script:Version='0.2.0'

function Write-BpsCheck {
    param([string]$Name,[ValidateSet('PASS','WARN','FAIL','INFO','TODO')][string]$Result,[string]$Detail='')
    $color=switch($Result){PASS{'Green'}WARN{'Yellow'}FAIL{'Red'}INFO{'Cyan'}TODO{'DarkYellow'}}
    Write-Host ('{0,-40}' -f $Name) -NoNewline
    Write-Host ('{0,-8}' -f "[$Result]") -ForegroundColor $color
    if(-not [string]::IsNullOrWhiteSpace($Detail)){Write-Host (' '*42+$Detail) -ForegroundColor DarkGray}
}
function Write-BpsHeader { Write-Host '';Write-Host "$Script:AppName $Script:Version" -ForegroundColor Cyan;Write-Host ('='*60) -ForegroundColor DarkGray;Write-Host '' }
function Format-BpsSize {param([int64]$Bytes);if($Bytes-ge 1GB){'{0:N2} GB'-f($Bytes/1GB)}elseif($Bytes-ge 1MB){'{0:N2} MB'-f($Bytes/1MB)}elseif($Bytes-ge 1KB){'{0:N2} KB'-f($Bytes/1KB)}else{"$Bytes B"}}

function Get-BpsBrowserInfo {
    param([ValidateSet('Edge','Chrome','Vivaldi')][string]$Browser)
    $la=[Environment]::GetFolderPath('LocalApplicationData');$pf=[Environment]::GetFolderPath('ProgramFiles');$px=[Environment]::GetFolderPath('ProgramFilesX86')
    switch($Browser){
        Edge{$n='Microsoft Edge';$proc='msedge';$u=Join-Path $la 'Microsoft\Edge\User Data';$c=@((Join-Path $pf 'Microsoft\Edge\Application\msedge.exe'),(Join-Path $px 'Microsoft\Edge\Application\msedge.exe'),(Join-Path $la 'Microsoft\Edge\Application\msedge.exe'))}
        Chrome{$n='Google Chrome';$proc='chrome';$u=Join-Path $la 'Google\Chrome\User Data';$c=@((Join-Path $pf 'Google\Chrome\Application\chrome.exe'),(Join-Path $px 'Google\Chrome\Application\chrome.exe'),(Join-Path $la 'Google\Chrome\Application\chrome.exe'))}
        Vivaldi{$n='Vivaldi';$proc='vivaldi';$u=Join-Path $la 'Vivaldi\User Data';$c=@((Join-Path $la 'Vivaldi\Application\vivaldi.exe'),(Join-Path $pf 'Vivaldi\Application\vivaldi.exe'),(Join-Path $px 'Vivaldi\Application\vivaldi.exe'))}
    }
    $exe=$c|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1
    $ver=if($exe){(Get-Item -LiteralPath $exe).VersionInfo.ProductVersion}else{$null}
    [pscustomobject]@{Key=$Browser;Name=$n;Process=$proc;Executable=$exe;Version=$ver;UserData=$u;UserDataExists=(Test-Path -LiteralPath $u -PathType Container)}
}
function Get-BpsBrowserProfiles {
    param([ValidateSet('Edge','Chrome','Vivaldi')][string]$Browser)
    $i=Get-BpsBrowserInfo $Browser;if(-not $i.UserDataExists){return @()}
    $names=@{};$ls=Join-Path $i.UserData 'Local State'
    if(Test-Path -LiteralPath $ls -PathType Leaf){try{$j=Get-Content -LiteralPath $ls -Raw -Encoding UTF8|ConvertFrom-Json;if($j.profile.info_cache){foreach($p in $j.profile.info_cache.PSObject.Properties){if($p.Value.name){$names[$p.Name]=[string]$p.Value.name}}}}catch{}}
    $dirs=@(Get-ChildItem -LiteralPath $i.UserData -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name-eq'Default'-or $_.Name-match'^Profile [0-9]+$'}|Sort-Object @{Expression={if($_.Name-eq'Default'){0}else{1}}},Name)
    @($dirs|ForEach-Object{[pscustomobject]@{Browser=$i.Name;DirectoryName=$_.Name;FriendlyName=$(if($names.ContainsKey($_.Name)){$names[$_.Name]}else{$null});Path=$_.FullName}})
}
function Get-BpsRunningBrowserSummary {
    $r=@();foreach($b in @('Edge','Chrome','Vivaldi')){$i=Get-BpsBrowserInfo $b;$p=@(Get-Process -Name $i.Process -ErrorAction SilentlyContinue);if($p.Count){$r+=[pscustomobject]@{Name=$i.Name;Count=$p.Count}}};@($r)
}
function Get-BpsPathSize {param([string]$Path);if(Test-Path -LiteralPath $Path -PathType Leaf){return [int64](Get-Item -LiteralPath $Path).Length};if(Test-Path -LiteralPath $Path -PathType Container){$m=Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue|Measure-Object Length -Sum;return [int64]$(if($null-eq$m.Sum){0}else{$m.Sum})};[int64]0}
function Get-BpsBackupItems {param($Profile);$r=@();foreach($x in @('IndexedDB','Local Storage','Session Storage','WebStorage','Service Worker','Network\Cookies','History','Login Data','Web Data','Favicons','Preferences','Secure Preferences')){$s=Join-Path $Profile.Path $x;if(Test-Path -LiteralPath $s){$r+=[pscustomobject]@{RelativePath=$x;Source=$s}}};@($r)}
function Get-BpsTreeMetrics {param([string]$Path);if(Test-Path -LiteralPath $Path -PathType Leaf){$f=Get-Item -LiteralPath $Path;return [pscustomobject]@{Files=[int64]1;Bytes=[int64]$f.Length}};$m=Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction Stop|Measure-Object Length -Sum;[pscustomobject]@{Files=[int64]$m.Count;Bytes=[int64]$(if($null-eq$m.Sum){0}else{$m.Sum})}}
function Copy-BpsItemVerified {
    param([string]$Source,[string]$Target)
    $parent=Split-Path -Parent $Target;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    if(Test-Path -LiteralPath $Source -PathType Container){New-Item -ItemType Directory -Path $Target -Force|Out-Null;Get-ChildItem -LiteralPath $Source -Force|Copy-Item -Destination $Target -Recurse -Force -ErrorAction Stop}else{Copy-Item -LiteralPath $Source -Destination $Target -Force -ErrorAction Stop}
    $a=Get-BpsTreeMetrics $Source;$b=Get-BpsTreeMetrics $Target
    if($a.Files-ne$b.Files-or$a.Bytes-ne$b.Bytes){throw "Verification failed: $Source"};$b
}
function Get-BpsConfiguredBackupLocation {if(-not[string]::IsNullOrWhiteSpace($Destination)){return $Destination};$v=[Environment]::GetEnvironmentVariable('BROWSERPROFILESYNC_BACKUP','Process');if([string]::IsNullOrWhiteSpace($v)){return $null};$v}

function Invoke-BpsDoctor {
    Write-BpsHeader
    $v=$PSVersionTable.PSVersion;Write-BpsCheck 'PowerShell' 'PASS' "Version $v | $($PSVersionTable.PSEdition) | $([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture)"
    $os=Get-CimInstance Win32_OperatingSystem;Write-BpsCheck 'Windows' 'PASS' "$($os.Caption) | Build $($os.BuildNumber) | $($os.OSArchitecture)"
    foreach($b in @('Edge','Chrome','Vivaldi')){$i=Get-BpsBrowserInfo $b;if($i.Executable){Write-BpsCheck $i.Name 'PASS' "Version $($i.Version) | $($i.Executable)";Write-BpsCheck '  User Data' $(if($i.UserDataExists){'PASS'}else{'WARN'}) $i.UserData}else{Write-BpsCheck $i.Name 'WARN' 'Browser not detected in standard locations.'}}
    $run=@(Get-BpsRunningBrowserSummary);if($run.Count){Write-BpsCheck 'Browser processes' 'WARN' 'One or more supported browsers are running.';foreach($x in $run){Write-BpsCheck "  $($x.Name)" 'INFO' "$($x.Count) process(es)"}}else{Write-BpsCheck 'Browser processes' 'PASS' 'No supported browsers are running.'}
    $profiles=0;$bytes=[int64]0
    foreach($b in @('Edge','Chrome','Vivaldi')){$i=Get-BpsBrowserInfo $b;foreach($p in @(Get-BpsBrowserProfiles $b)){$profiles++;$label=$p.DirectoryName;if($p.FriendlyName){$label+=" - $($p.FriendlyName)"};Write-BpsCheck "$($i.Name) / $label" 'PASS' $p.Path;foreach($x in @(Get-BpsBackupItems $p)){$bytes+=Get-BpsPathSize $x.Source}}}
    Write-BpsCheck 'Profiles detected' 'INFO' ([string]$profiles);Write-BpsCheck 'Estimated protected data' 'INFO' (Format-BpsSize $bytes)
    if($run.Count){Write-BpsCheck 'Backup readiness' 'WARN' 'BLOCKED: close supported browsers before backup.'}else{Write-BpsCheck 'Backup readiness' 'PASS' 'READY: no supported browser processes are running.'}
    Write-Host '';Write-Host 'Doctor completed. No files were modified.' -ForegroundColor DarkGray
}
function Invoke-BpsBackup {
    Write-BpsHeader;Write-Host 'Backup';Write-Host '------' -ForegroundColor DarkGray
    $run=@(Get-BpsRunningBrowserSummary);if($run.Count){Write-BpsCheck 'Backup' 'FAIL' 'BLOCKED: close all supported browsers and try again.';foreach($x in $run){Write-BpsCheck "  $($x.Name)" 'INFO' "$($x.Count) process(es) running"};Write-Host 'No files were copied.' -ForegroundColor DarkGray;return 20}
    $base=Get-BpsConfiguredBackupLocation;if([string]::IsNullOrWhiteSpace($base)){Write-BpsCheck 'Backup location' 'FAIL' 'Use -Destination <existing-folder> or set BROWSERPROFILESYNC_BACKUP.';return 21}
    if(-not(Test-Path -LiteralPath $base -PathType Container)){Write-BpsCheck 'Backup location' 'FAIL' "Base folder does not exist: $base";return 22}
    $base=(Resolve-Path -LiteralPath $base).Path
    foreach($b in @('Edge','Chrome','Vivaldi')){$i=Get-BpsBrowserInfo $b;if($i.UserDataExists-and$base.StartsWith($i.UserData,[StringComparison]::OrdinalIgnoreCase)){Write-BpsCheck 'Backup location' 'FAIL' 'Destination cannot be inside browser User Data.';return 23}}
    $root=Join-Path $base "$([Environment]::MachineName)-$(Get-Date -Format 'yyyyMMdd-HHmmss')";New-Item -ItemType Directory -Path $root|Out-Null
    $started=(Get-Date).ToUniversalTime();$entries=@();$files=[int64]0;$bytes=[int64]0
    try{
        foreach($b in @('Edge','Chrome','Vivaldi')){$i=Get-BpsBrowserInfo $b;if(-not$i.UserDataExists){continue};$bn=$i.Name-replace'[^A-Za-z0-9._-]','_';$br=Join-Path $root "Browsers\$bn"
            $ls=Join-Path $i.UserData 'Local State';if(Test-Path -LiteralPath $ls){$t=Join-Path $br 'Local State';$m=Copy-BpsItemVerified $ls $t;$files+=$m.Files;$bytes+=$m.Bytes;$entries+=[pscustomobject]@{Browser=$i.Name;Profile=$null;Item='Local State';Source=$ls;Target=$t;Files=$m.Files;Bytes=$m.Bytes;Verified=$true}}
            foreach($p in @(Get-BpsBrowserProfiles $b)){foreach($x in @(Get-BpsBackupItems $p)){$t=Join-Path $br "Profiles\$($p.DirectoryName)\$($x.RelativePath)";Write-BpsCheck "$($i.Name) / $($p.DirectoryName)" 'INFO' $x.RelativePath;$m=Copy-BpsItemVerified $x.Source $t;$files+=$m.Files;$bytes+=$m.Bytes;$entries+=[pscustomobject]@{Browser=$i.Name;Profile=$p.DirectoryName;FriendlyName=$p.FriendlyName;Item=$x.RelativePath;Source=$x.Source;Target=$t;Files=$m.Files;Bytes=$m.Bytes;Verified=$true}}}
        }
        $manifest=[ordered]@{SchemaVersion=1;Application=$Script:AppName;ApplicationVersion=$Script:Version;Computer=[Environment]::MachineName;StartedUtc=$started.ToString('o');CompletedUtc=(Get-Date).ToUniversalTime().ToString('o');BackupRoot=$root;Status='Complete';Verification='FileCountAndByteCount';TotalFiles=$files;TotalBytes=$bytes;Items=$entries}
        $mp=Join-Path $root 'manifest.json';$manifest|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $mp -Encoding UTF8
        Write-BpsCheck 'Backup' 'PASS' 'Backup completed and verified.';Write-BpsCheck 'Backup folder' 'INFO' $root;Write-BpsCheck 'Files copied' 'INFO' ([string]$files);Write-BpsCheck 'Data copied' 'INFO' (Format-BpsSize $bytes);Write-BpsCheck 'Manifest' 'PASS' $mp;return 0
    }catch{$failure=[ordered]@{SchemaVersion=1;ApplicationVersion=$Script:Version;Status='Incomplete';Error=$_.Exception.Message;BackupRoot=$root;Items=$entries};$failure|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $root 'manifest.incomplete.json') -Encoding UTF8 -ErrorAction SilentlyContinue;Write-BpsCheck 'Backup' 'FAIL' $_.Exception.Message;Write-BpsCheck 'Incomplete folder' 'WARN' $root;return 25}
}
function Show-BpsHelp {Write-BpsHeader;Write-Host 'Commands:';Write-Host '  doctor';Write-Host '  backup -Destination D:\BrowserProfileSync';Write-Host '  help'}
try{switch($Command){doctor{Invoke-BpsDoctor;exit 0}backup{$c=Invoke-BpsBackup;exit $c}help{Show-BpsHelp;exit 0}}}catch{Write-Host $_.Exception.Message -ForegroundColor Red;exit 1}
