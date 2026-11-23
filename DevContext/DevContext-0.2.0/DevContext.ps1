#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('doctor','status','identities','config','identity-setup','identity-test')]
    [string]$Command = 'doctor',
    [switch]$Json,
    [ValidateSet('Personal','Enterprise','Extra')]
    [string]$Identity
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppName = 'DevContext'
$script:AppVersion = '0.2.0'
$script:ConfigRoot = Join-Path $env:LOCALAPPDATA $script:AppName
$script:ConfigFile = Join-Path $script:ConfigRoot 'config.json'
$script:IdentityFile = Join-Path $script:ConfigRoot 'identities.json'
$script:LogRoot = Join-Path $script:ConfigRoot 'logs'

function Get-NativeLines([scriptblock]$Script) {
    try { @(& $Script 2>&1 | ForEach-Object { [string]$_ }) } catch { @() }
}
function Get-NativeText([scriptblock]$Script) { ((Get-NativeLines $Script) -join "`n").Trim() }

function Initialize-DevContextStorage {
    foreach ($p in @($script:ConfigRoot,$script:LogRoot)) {
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
    if (-not (Test-Path -LiteralPath $script:ConfigFile)) {
        [ordered]@{
            schemaVersion=2
            projectRootCandidates=@('C:\dos\pwsh','D:\dos\pwsh','E:\pwsh')
            extraRootCandidates=@('C:\dos\extra','D:\dos\extra','E:\extra')
        } | ConvertTo-Json -Depth 8 | Set-Content $script:ConfigFile -Encoding utf8
    }
    if (-not (Test-Path -LiteralPath $script:IdentityFile)) {
        New-IdentityStore | ConvertTo-Json -Depth 10 | Set-Content $script:IdentityFile -Encoding utf8
    }
}

function Get-Tool([string]$Name) {
    $c=Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $c){return [pscustomobject]@{Name=$Name;Installed=$false;Path=$null;Version=$null}}
    $v=switch($Name){
        'git' {Get-NativeText {& $c.Source --version}}
        'gh' {((Get-NativeLines {& $c.Source --version}) | Select-Object -First 1)}
        'code' {((Get-NativeLines {& $c.Source --version}) | Select-Object -First 1)}
        'ssh' {((Get-NativeLines {& $c.Source -V}) | Select-Object -First 1)}
        'copilot' {((Get-NativeLines {& $c.Source --version}) | Select-Object -First 1)}
        default {''}
    }
    [pscustomobject]@{Name=$Name;Installed=$true;Path=$c.Source;Version=[string]$v}
}

function Get-Roots {
    $defaults=[ordered]@{project=@('C:\dos\pwsh','D:\dos\pwsh','E:\pwsh');extra=@('C:\dos\extra','D:\dos\extra','E:\extra')}
    try {
        $cfg=Get-Content $script:ConfigFile -Raw | ConvertFrom-Json
        if($cfg.projectRootCandidates){$defaults.project=@($cfg.projectRootCandidates)}
        if($cfg.extraRootCandidates){$defaults.extra=@($cfg.extraRootCandidates)}
        # Compatibility with config created by 0.1/0.1.1
        if($cfg.projectRoots){$defaults.project=@($cfg.projectRoots.personal);$defaults.extra=@($cfg.projectRoots.extra)}
    } catch {}
    $p=@($defaults.project | ForEach-Object {[pscustomobject]@{Path=$_;Exists=(Test-Path $_);IsGitRepository=(Test-Path (Join-Path $_ '.git'))}})
    $e=@($defaults.extra | ForEach-Object {[pscustomobject]@{Path=$_;Exists=(Test-Path $_);IsGitRepository=(Test-Path (Join-Path $_ '.git'))}})
    [pscustomobject]@{ProjectCandidates=$p;SelectedProjectRoot=($p|Where-Object Exists|Select-Object -First 1 -ExpandProperty Path);ExtraCandidates=$e;SelectedExtraRoot=($e|Where-Object Exists|Select-Object -First 1 -ExpandProperty Path)}
}

function Get-GitDiagnostics {
    if(-not (Get-Command git -ErrorAction SilentlyContinue)){return [pscustomobject]@{Installed=$false}}
    $inside=(Get-NativeText {git rev-parse --is-inside-work-tree}) -eq 'true'
    $helpers=@(Get-NativeLines {git config --show-origin --get-all credential.helper}|Where-Object {$_})
    [pscustomobject]@{
        Installed=$true
        Global=[pscustomobject]@{UserName=Get-NativeText {git config --global --get user.name};UserEmail=Get-NativeText {git config --global --get user.email}}
        Local=if($inside){[pscustomobject]@{UserName=Get-NativeText {git config --local --get user.name};UserEmail=Get-NativeText {git config --local --get user.email}}}else{$null}
        Credential=[pscustomobject]@{Configured=($helpers.Count -gt 0);Helpers=$helpers;ManagerConfigured=[bool]($helpers -match '(?i)manager')}
        CurrentRepository=[pscustomobject]@{IsRepository=$inside;Root=if($inside){Get-NativeText {git rev-parse --show-toplevel}}else{$null};Branch=if($inside){Get-NativeText {git branch --show-current}}else{$null};Origin=if($inside){Get-NativeText {git remote get-url origin}}else{$null}}
    }
}

function Get-SshDiagnostics {
    $root=Join-Path $HOME '.ssh';$file=Join-Path $root 'config';$hosts=@();$current=$null
    if(Test-Path $file){
        foreach($line in Get-Content $file){
            $t=$line.Trim();if(-not $t -or $t.StartsWith('#')){continue}
            if($t -match '^(?i)Host\s+(.+)$'){
                if($current){$hosts+=[pscustomobject]$current}
                $current=[ordered]@{Host=$Matches[1];HostName=$null;User=$null;IdentityFile=@()};continue
            }
            if($current -and $t -match '^(?i)HostName\s+(.+)$'){$current.HostName=$Matches[1];continue}
            if($current -and $t -match '^(?i)User\s+(.+)$'){$current.User=$Matches[1];continue}
            if($current -and $t -match '^(?i)IdentityFile\s+(.+)$'){$current.IdentityFile+=@($Matches[1]);continue}
        }
        if($current){$hosts+=[pscustomobject]$current}
    }
    [pscustomobject]@{Directory=$root;ConfigExists=(Test-Path $file);ConfigPath=$file;Hosts=@($hosts);GitHubAliases=@($hosts|Where-Object {$_.HostName -match '(?i)github\.com' -or $_.Host -match '(?i)github'});PrivateKeyContentsRead=$false}
}

function Get-GitHubCliDiagnostics {
    if(-not(Get-Command gh -ErrorAction SilentlyContinue)){return [pscustomobject]@{Installed=$false;Accounts=@()}}
    $lines=Get-NativeLines {gh auth status}
    $accounts=@();$ghHostName=$null;$cur=$null
    foreach($raw in $lines){
        $line=($raw -replace '[^\x00-\x7F]','').Trim()
        if($line -match '^([\w.-]+)$'){$ghHostName=$Matches[1];continue}
        if($line -match 'Logged in to\s+\S+\s+account\s+(\S+)'){
            if($cur){$accounts+=[pscustomobject]$cur}
            $cur=[ordered]@{Host=$ghHostName;Account=$Matches[1];Active=$false;Protocol=$null;Storage=$null}
            if($line -match '\(([^)]+)\)'){$cur.Storage=$Matches[1]};continue
        }
        if($cur -and $line -match 'Active account:\s*(true|false)'){$cur.Active=[bool]::Parse($Matches[1]);continue}
        if($cur -and $line -match 'Git operations protocol:\s*(\S+)'){$cur.Protocol=$Matches[1];continue}
    }
    if($cur){$accounts+=[pscustomobject]$cur}
    [pscustomobject]@{Installed=$true;Accounts=@($accounts);ActiveAccount=($accounts|Where-Object Active|Select-Object -First 1 -ExpandProperty Account);TokenValuesCaptured=$false}
}

function Get-VSCodeDiagnostics {
    $code=Get-Command code -ErrorAction SilentlyContinue;if(-not $code){return [pscustomobject]@{Installed=$false}}
    $ext=@(Get-NativeLines {code --list-extensions --show-versions}|Where-Object {$_ -match '@'})
    $diskRoot=Join-Path $HOME '.vscode\extensions'
    $disk=@();if(Test-Path $diskRoot){$disk=@(Get-ChildItem $diskRoot -Directory -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Name)}
    $combined=@($ext+$disk|Sort-Object -Unique)
    $user=Join-Path $env:APPDATA 'Code\User';$prof=Join-Path $user 'profiles';$p=@()
    if(Test-Path $prof){$p=@(Get-ChildItem $prof -Directory -ErrorAction SilentlyContinue|ForEach-Object {[pscustomobject]@{Id=$_.Name;Path=$_.FullName}})}
    [pscustomobject]@{
        Installed=$true;Executable=$code.Source;UserData=$user;ExtensionRoot=$diskRoot;Profiles=@($p)
        Extensions=[pscustomobject]@{
            GitHubCopilot=@($combined|Where-Object {$_ -match '(?i)^github\.copilot@|^github\.copilot-\d|^github\.copilot-'})
            GitHubCopilotChat=@($combined|Where-Object {$_ -match '(?i)^github\.copilot-chat'})
            PowerShell=@($combined|Where-Object {$_ -match '(?i)^ms-vscode\.powershell'})
        }
    }
}
function Get-CopilotDiagnostics {$c=Get-Command copilot -ErrorAction SilentlyContinue;if(-not$c){return [pscustomobject]@{Installed=$false}};$src=if($c.Source -match '[\\/]Microsoft VS Code[\\/].*copilot-shim'){'VSCodeShim'}else{'Other'};[pscustomobject]@{Installed=$true;Path=$c.Source;Source=$src;Version=((Get-NativeLines {copilot --version})|Select-Object -First 1)}}

function Get-Readiness($roots,$git,$gh,$ssh,$vscode,$copilot){
    $personalCandidate=[bool]($gh.ActiveAccount -and $git.Global.UserEmail)
    $sshPersonal=@($ssh.GitHubAliases|Where-Object {$_.Host -match '(?i)pessoal|personal'})
    [pscustomobject]@{
        ProjectRootFound=[bool]$roots.SelectedProjectRoot;ExtraRootFound=[bool]$roots.SelectedExtraRoot
        PersonalCandidateDetected=$personalCandidate;PersonalGitHubCandidate=$gh.ActiveAccount;PersonalSshAliasCandidates=@($sshPersonal|Select-Object -ExpandProperty Host)
        EnterpriseConfigured=$false;ExtraConfigured=$false;VSCodeReady=[bool]$vscode.Installed;CopilotCliReady=[bool]$copilot.Installed
        Status=if($roots.SelectedProjectRoot -and $personalCandidate){'READY_FOR_IDENTITY_SETUP'}else{'NEEDS_ATTENTION'}
    }
}


function New-IdentityStore {
    [ordered]@{
        schemaVersion = 2
        updatedAt = $null
        identities = [ordered]@{
            Personal = [ordered]@{ configured=$false; git=[ordered]@{userName=$null;userEmail=$null;sshAlias=$null;githubAccount=$null}; copilot=[ordered]@{provider='GitHub';account=$null}; microsoft365=$false; isolated=$false }
            Enterprise = [ordered]@{ configured=$false; git=[ordered]@{userName=$null;userEmail=$null;sshAlias=$null;githubAccount=$null}; copilot=[ordered]@{provider='GitHub';account=$null}; microsoft365=$true; isolated=$false }
            Extra = [ordered]@{ configured=$false; git=[ordered]@{userName=$null;userEmail=$null;sshAlias=$null;githubAccount=$null}; copilot=[ordered]@{provider='GitHub';account=$null}; microsoft365=$false; isolated=$true }
        }
    }
}

function Read-IdentityStore {
    Initialize-DevContextStorage
    try {
        $store=Get-Content $script:IdentityFile -Raw | ConvertFrom-Json -AsHashtable
        if([int]$store.schemaVersion -lt 2){ throw 'Legacy schema' }
        return $store
    } catch {
        $legacyBackup="$script:IdentityFile.legacy-$(Get-Date -Format yyyyMMdd-HHmmss).json"
        if(Test-Path $script:IdentityFile){Copy-Item $script:IdentityFile $legacyBackup -Force}
        $store=New-IdentityStore
        $store | ConvertTo-Json -Depth 10 | Set-Content $script:IdentityFile -Encoding utf8
        return $store
    }
}

function Write-IdentityStore([hashtable]$Store) {
    $Store.updatedAt=(Get-Date).ToString('o')
    $temp="$script:IdentityFile.tmp"
    $Store | ConvertTo-Json -Depth 10 | Set-Content $temp -Encoding utf8
    Move-Item $temp $script:IdentityFile -Force
}

function Read-Required([string]$Prompt,[string]$Default='') {
    $suffix=if($Default){" [$Default]"}else{''}
    while($true){
        $value=Read-Host "$Prompt$suffix"
        if([string]::IsNullOrWhiteSpace($value)){$value=$Default}
        if(-not [string]::IsNullOrWhiteSpace($value)){return $value.Trim()}
        Write-Host 'Valor obrigatorio.' -ForegroundColor Yellow
    }
}

function Select-FromList([string]$Prompt,[array]$Items,[string]$DisplayProperty='') {
    if(-not $Items -or $Items.Count -eq 0){return $null}
    Write-Host $Prompt -ForegroundColor Cyan
    for($i=0;$i -lt $Items.Count;$i++){
        $label=if($DisplayProperty){$Items[$i].$DisplayProperty}else{[string]$Items[$i]}
        Write-Host ("  [{0}] {1}" -f ($i+1),$label)
    }
    while($true){
        $choice=Read-Host 'Numero'
        $n=0
        if([int]::TryParse($choice,[ref]$n) -and $n -ge 1 -and $n -le $Items.Count){return $Items[$n-1]}
        Write-Host 'Selecao invalida.' -ForegroundColor Yellow
    }
}

function Invoke-IdentitySetup {
    Initialize-DevContextStorage
    $store=Read-IdentityStore
    $ssh=Get-SshDiagnostics
    $gh=Get-GitHubCliDiagnostics
    $git=Get-GitDiagnostics
    $targets=if($Identity){@($Identity)}else{@('Personal','Enterprise','Extra')}
    foreach($name in $targets){
        Write-Host "`nIdentity Setup: $name" -ForegroundColor Cyan
        $current=$store.identities[$name]
        $defaultName=if($name -eq 'Personal'){$git.Global.UserName}else{$current.git.userName}
        $defaultEmail=if($name -eq 'Personal'){$git.Global.UserEmail}else{$current.git.userEmail}
        $gitName=Read-Required 'Git user.name' $defaultName
        $gitEmail=Read-Required 'Git user.email' $defaultEmail
        $aliases=@($ssh.GitHubAliases)
        $preferred=$aliases | Where-Object {
            ($name -eq 'Personal' -and $_.Host -match '(?i)pessoal|personal') -or
            ($name -eq 'Enterprise' -and $_.Host -match '(?i)cindumel|empresa|enterprise') -or
            ($name -eq 'Extra' -and $_.Host -match '(?i)extra|larissa')
        }
        if($preferred){$aliases=@($preferred)+@($aliases|Where-Object {$_.Host -notin $preferred.Host})}
        $selected=Select-FromList 'Selecione o alias SSH do GitHub:' $aliases 'Host'
        if(-not $selected){throw 'Nenhum alias GitHub foi encontrado em ~/.ssh/config.'}
        $defaultAccount=if($name -eq 'Personal'){$gh.ActiveAccount}else{$current.git.githubAccount}
        $account=Read-Required 'Nome da conta GitHub' $defaultAccount
        $copilotDefault=if($current.copilot.account){$current.copilot.account}else{$account}
        $copilotAccount=Read-Required 'Conta GitHub Copilot pretendida' $copilotDefault
        $current.git.userName=$gitName
        $current.git.userEmail=$gitEmail
        $current.git.sshAlias=$selected.Host
        $current.git.githubAccount=$account
        $current.copilot.provider='GitHub'
        $current.copilot.account=$copilotAccount
        $current.microsoft365=($name -eq 'Enterprise')
        $current.isolated=($name -eq 'Extra')
        $current.configured=$true
        $store.identities[$name]=$current
        Write-Host "$name configurada. Nenhum token, senha ou chave foi armazenado." -ForegroundColor Green
    }
    Write-IdentityStore $store
    Show-Identities
}

function Test-OneIdentity([string]$Name,[hashtable]$Data) {
    $ssh=Get-SshDiagnostics
    $alias=@($ssh.GitHubAliases|Where-Object Host -eq $Data.git.sshAlias)
    $issues=@()
    if(-not $Data.configured){$issues+='Not configured'}
    if(-not $Data.git.userName){$issues+='Missing Git user.name'}
    if(-not $Data.git.userEmail){$issues+='Missing Git user.email'}
    if(-not $alias){$issues+='SSH alias not found'}
    if(-not $Data.git.githubAccount){$issues+='Missing GitHub account'}
    if($Name -eq 'Extra' -and -not $Data.isolated){$issues+='Extra must be isolated'}
    [pscustomobject]@{Identity=$Name;Configured=[bool]$Data.configured;GitHubAccount=$Data.git.githubAccount;SshAlias=$Data.git.sshAlias;CopilotAccount=$Data.copilot.account;Microsoft365=[bool]$Data.microsoft365;Isolated=[bool]$Data.isolated;Valid=($issues.Count -eq 0);Issues=$issues}
}

function Invoke-IdentityTest {
    $store=Read-IdentityStore
    $names=if($Identity){@($Identity)}else{@('Personal','Enterprise','Extra')}
    $results=@($names|ForEach-Object {Test-OneIdentity $_ $store.identities[$_]})
    if($Json){$results|ConvertTo-Json -Depth 8}else{$results|Format-Table Identity,Configured,GitHubAccount,SshAlias,CopilotAccount,Microsoft365,Isolated,Valid -AutoSize;foreach($r in $results|Where-Object {-not $_.Valid}){Write-Host "$($r.Identity): $($r.Issues -join '; ')" -ForegroundColor Yellow}}
}

function Show-Identities {
    $store=Read-IdentityStore
    $safe=[ordered]@{schemaVersion=$store.schemaVersion;updatedAt=$store.updatedAt;identities=$store.identities}
    $safe|ConvertTo-Json -Depth 10
}

function Invoke-DevDoctor {
    Initialize-DevContextStorage
    $tools=@('git','gh','code','ssh','copilot')|ForEach-Object {Get-Tool $_}
    $roots=Get-Roots;$git=Get-GitDiagnostics;$gh=Get-GitHubCliDiagnostics;$ssh=Get-SshDiagnostics;$vs=Get-VSCodeDiagnostics;$cop=Get-CopilotDiagnostics
    $r=[pscustomobject]@{App="$script:AppName $script:AppVersion";Timestamp=(Get-Date).ToString('o');Computer=$env:COMPUTERNAME;User=$env:USERNAME;PowerShell=[pscustomobject]@{Version=$PSVersionTable.PSVersion.ToString();MeetsRequirement=($PSVersionTable.PSVersion.Major-ge 7);Edition=$PSVersionTable.PSEdition};Tools=@($tools);Roots=$roots;Git=$git;GitHubCli=$gh;SSH=$ssh;VSCode=$vs;CopilotCLI=$cop;Readiness=(Get-Readiness $roots $git $gh $ssh $vs $cop);ConfigFile=$script:ConfigFile;IdentityFile=$script:IdentityFile;ReadOnlyDiagnostics=$true}
    if($Json){$r|ConvertTo-Json -Depth 12;return}
    Write-Host "DevContext $script:AppVersion - Doctor" -ForegroundColor Cyan
    Write-Host "Machine................. $env:COMPUTERNAME"
    Write-Host "PowerShell.............. $($PSVersionTable.PSVersion)"
    Write-Host "Project Root............ $($roots.SelectedProjectRoot)"
    Write-Host "Extra Root.............. $(if($roots.SelectedExtraRoot){$roots.SelectedExtraRoot}else{'Not configured'})"
    Write-Host "GitHub active........... $($gh.ActiveAccount)"
    Write-Host "Readiness............... $($r.Readiness.Status)" -ForegroundColor $(if($r.Readiness.Status -eq 'READY_FOR_IDENTITY_SETUP'){'Green'}else{'Yellow'})
}

Initialize-DevContextStorage
switch($Command){
    'doctor'{Invoke-DevDoctor}
    'status'{Invoke-DevDoctor}
    'identities'{Show-Identities}
    'identity-setup'{Invoke-IdentitySetup}
    'identity-test'{Invoke-IdentityTest}
    'config'{Get-Content $script:ConfigFile -Raw}
}
