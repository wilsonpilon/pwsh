#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('doctor','status','identities','config')]
    [string]$Command = 'doctor',
    [switch]$Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppName = 'DevContext'
$script:AppVersion = '0.1.1'
$script:ConfigRoot = Join-Path $env:LOCALAPPDATA $script:AppName
$script:ConfigFile = Join-Path $script:ConfigRoot 'config.json'
$script:IdentityFile = Join-Path $script:ConfigRoot 'identities.json'
$script:LogRoot = Join-Path $script:ConfigRoot 'logs'

function Initialize-DevContextStorage {
    foreach ($p in @($script:ConfigRoot,$script:LogRoot)) {
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
    if (-not (Test-Path -LiteralPath $script:ConfigFile)) {
        $cfg = [ordered]@{
            schemaVersion = 1
            projectRoots = [ordered]@{
                personal = @('C:\dos\pwsh','D:\dos\pwsh','E:\pwsh')
                enterprise = @('C:\dos\pwsh','D:\dos\pwsh','E:\pwsh')
                extra = @('C:\dos\extra','D:\dos\extra','E:\extra')
            }
        }
        $cfg | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:ConfigFile -Encoding utf8
    }
    if (-not (Test-Path -LiteralPath $script:IdentityFile)) {
        [ordered]@{
            schemaVersion = 1
            identities = [ordered]@{
                Personal   = @{ configured = $false }
                Enterprise = @{ configured = $false }
                Extra      = @{ configured = $false; isolated = $true }
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:IdentityFile -Encoding utf8
    }
}

function Get-CommandInfoSafe([string]$Name) {
    $c = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $c) { return $null }
    $version = $null
    try {
        switch ($Name) {
            'git'     { $version = (& $c.Source --version 2>$null) -join ' ' }
            'gh'      { $version = (& $c.Source --version 2>$null | Select-Object -First 1) }
            'code'    { $version = (& $c.Source --version 2>$null | Select-Object -First 1) }
            'ssh'     { $version = (& $c.Source -V 2>&1 | Select-Object -First 1) }
            'git-credential-manager' { $version = (& $c.Source --version 2>$null | Select-Object -First 1) }
            'copilot' { $version = (& $c.Source --version 2>$null | Select-Object -First 1) }
        }
    } catch { $version = 'Installed; version unavailable' }
    [pscustomobject]@{ Name=$Name; Path=$c.Source; Version=[string]$version }
}

function Get-GitHubCliStatus {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) { return [pscustomobject]@{ Installed=$false; Accounts=@() } }
    $text = (& gh auth status 2>&1 | Out-String).Trim()
    # 0.1 intentionally reports the CLI's own text instead of parsing tokens/accounts.
    [pscustomobject]@{ Installed=$true; Accounts=@(); RawStatus=$text }
}

function Get-ProjectRootDiscovery {
    $cfg = Get-Content -LiteralPath $script:ConfigFile -Raw | ConvertFrom-Json
    $rows = foreach ($kind in @('personal','enterprise','extra')) {
        foreach ($candidate in $cfg.projectRoots.$kind) {
            [pscustomobject]@{
                Context=$kind
                Path=[string]$candidate
                Exists=Test-Path -LiteralPath $candidate
                IsGitRepository=Test-Path -LiteralPath (Join-Path $candidate '.git')
            }
        }
    }
    @($rows)
}


function Get-NativeText([scriptblock]$Script) {
    try { return ((& $Script 2>&1 | ForEach-Object { "$_" }) -join "`n").Trim() } catch { return '' }
}

function Get-GitDiagnostics {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return [pscustomobject]@{ Installed=$false } }
    $inside = (Get-NativeText { git rev-parse --is-inside-work-tree }) -eq 'true'
    $root = if ($inside) { Get-NativeText { git rev-parse --show-toplevel } } else { $null }
    $branch = if ($inside) { Get-NativeText { git branch --show-current } } else { $null }
    $remote = if ($inside) { Get-NativeText { git remote get-url origin } } else { $null }
    [pscustomobject]@{
        Installed=$true
        Global=[pscustomobject]@{
            UserName=Get-NativeText { git config --global --get user.name }
            UserEmail=Get-NativeText { git config --global --get user.email }
        }
        Local=if($inside){[pscustomobject]@{
            UserName=Get-NativeText { git config --local --get user.name }
            UserEmail=Get-NativeText { git config --local --get user.email }
        }}else{$null}
        CredentialHelpers=@(Get-NativeText { git config --show-origin --get-all credential.helper } -split "`n" | Where-Object { $_ })
        CurrentRepository=[pscustomobject]@{ IsRepository=$inside; Root=$root; Branch=$branch; Origin=$remote }
    }
}

function Get-SshDiagnostics {
    $sshRoot=Join-Path $HOME '.ssh'; $cfg=Join-Path $sshRoot 'config'
    $keys=@()
    if(Test-Path $sshRoot){
        $keys=@(Get-ChildItem -LiteralPath $sshRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^id_' -and $_.Extension -ne '.pub' } |
            ForEach-Object { $_.Name })
    }
    [pscustomobject]@{ Directory=$sshRoot; ConfigExists=(Test-Path $cfg); PrivateKeyFileNames=$keys; PrivateKeyCount=$keys.Count }
}

function Get-VSCodeDiagnostics {
    $code=Get-Command code -ErrorAction SilentlyContinue
    if(-not $code){ return [pscustomobject]@{ Installed=$false } }
    $ext=@(Get-NativeText { code --list-extensions --show-versions } -split "`n" | Where-Object { $_ })
    $userData=Join-Path $env:APPDATA 'Code\User'
    $profileDir=Join-Path $userData 'profiles'
    [pscustomobject]@{
        Installed=$true; Executable=$code.Source; UserData=$userData
        ProfileDirectories=if(Test-Path $profileDir){@(Get-ChildItem $profileDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {$_.FullName})}else{@()}
        Extensions=[pscustomobject]@{
            GitHubCopilot=@($ext | Where-Object { $_ -match '^github\.copilot@' })
            GitHubCopilotChat=@($ext | Where-Object { $_ -match '^github\.copilot-chat@' })
            PowerShell=@($ext | Where-Object { $_ -match '^ms-vscode\.powershell@' })
        }
    }
}

function Get-CopilotDiagnostics {
    $c=Get-Command copilot -ErrorAction SilentlyContinue
    if(-not $c){return [pscustomobject]@{Installed=$false}}
    $src='Other'
    if($c.Source -match '[\\/]Microsoft VS Code[\\/].*copilot-shim'){ $src='VSCodeShim' }
    [pscustomobject]@{Installed=$true; Path=$c.Source; Source=$src; Version=(Get-NativeText { copilot --version })}
}

function Invoke-DevDoctor {
    Initialize-DevContextStorage
    $tools = foreach ($n in @('git','gh','code','ssh','git-credential-manager','copilot')) {
        $i = Get-CommandInfoSafe $n
        [pscustomobject]@{ Tool=$n; Installed=[bool]$i; Path=if($i){$i.Path}else{$null}; Version=if($i){$i.Version}else{$null} }
    }
    $pwshOK = $PSVersionTable.PSVersion.Major -ge 7
    $roots = Get-ProjectRootDiscovery
    $github = Get-GitHubCliStatus
    $report = [pscustomobject]@{
        App="$script:AppName $script:AppVersion"
        Timestamp=(Get-Date).ToString('o')
        Computer=$env:COMPUTERNAME
        User=$env:USERNAME
        PowerShell=[pscustomobject]@{ Version=$PSVersionTable.PSVersion.ToString(); MeetsRequirement=$pwshOK; Edition=$PSVersionTable.PSEdition }
        Tools=@($tools)
        GitHubCli=$github
        Git=Get-GitDiagnostics
        SSH=Get-SshDiagnostics
        VSCode=Get-VSCodeDiagnostics
        CopilotCLI=Get-CopilotDiagnostics
        ProjectRoots=@($roots)
        ConfigFile=$script:ConfigFile
        IdentityFile=$script:IdentityFile
        ReadOnlyDiagnostics=$true
    }
    if ($Json) { $report | ConvertTo-Json -Depth 10; return }
    Write-Host "DevContext $script:AppVersion - Doctor" -ForegroundColor Cyan
    Write-Host ("Computer: {0}   User: {1}" -f $env:COMPUTERNAME,$env:USERNAME)
    Write-Host ("PowerShell: {0} ({1})" -f $PSVersionTable.PSVersion, $(if($pwshOK){'OK'}else{'REQUIRES 7+'}))
    Write-Host ''
    $tools | Format-Table Tool,Installed,Version,Path -AutoSize
    Write-Host 'Project roots:' -ForegroundColor Cyan
    $roots | Format-Table Context,Exists,IsGitRepository,Path -AutoSize
    Write-Host "Config: $script:ConfigFile"
    Write-Host "Identities: $script:IdentityFile"
    if ($github.RawStatus) { Write-Host ''; Write-Host 'GitHub CLI auth status:' -ForegroundColor Cyan; Write-Host $github.RawStatus }
}

function Show-Identities {
    Initialize-DevContextStorage
    Get-Content -LiteralPath $script:IdentityFile -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 8
}
function Show-Config {
    Initialize-DevContextStorage
    Get-Content -LiteralPath $script:ConfigFile -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 8
}

switch ($Command) {
    'doctor'     { Invoke-DevDoctor }
    'status'     { Invoke-DevDoctor }
    'identities' { Show-Identities }
    'config'     { Show-Config }
}
