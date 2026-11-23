#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('doctor','status','identities','config','identity-setup','identity-test','identity-verify','new')]
    [string]$Command = 'doctor',
    [switch]$Json,
    [ValidateSet('Personal','Enterprise','Extra')]
    [string]$Identity,
    [string]$ProjectName,
    [ValidateSet('Personal-Personal','Personal-Enterprise','Enterprise-Enterprise','Enterprise-Personal','Extra-Extra')]
    [string]$ContextModel,
    [ValidateSet('Monorepo','Standalone')]
    [string]$RepositoryMode,
    [string]$Destination
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppName = 'DevContext'
$script:AppVersion = '0.3.2'
$script:ConfigRoot = Join-Path $env:LOCALAPPDATA $script:AppName
$script:ConfigFile = Join-Path $script:ConfigRoot 'config.json'
$script:IdentityFile = Join-Path $script:ConfigRoot 'identities.json'
$script:LogRoot = Join-Path $script:ConfigRoot 'logs'

function Get-NativeLines {
    param([scriptblock]$Script)
    try { return @(& $Script 2>&1 | ForEach-Object { [string]$_ }) }
    catch { return @([string]$_.Exception.Message) }
}

function Get-NativeText {
    param([scriptblock]$Script)
    return ((Get-NativeLines -Script $Script) -join "`n").Trim()
}

function New-IdentityStore {
    return [ordered]@{
        schemaVersion = 2
        updatedAt = $null
        identities = [ordered]@{
            Personal = [ordered]@{
                configured = $false
                git = [ordered]@{ userName=$null; userEmail=$null; sshAlias=$null; githubAccount=$null }
                copilot = [ordered]@{ provider='GitHub'; account=$null }
                microsoft365 = $false
                isolated = $false
            }
            Enterprise = [ordered]@{
                configured = $false
                git = [ordered]@{ userName=$null; userEmail=$null; sshAlias=$null; githubAccount=$null }
                copilot = [ordered]@{ provider='GitHub'; account=$null }
                microsoft365 = $true
                isolated = $false
            }
            Extra = [ordered]@{
                configured = $false
                git = [ordered]@{ userName=$null; userEmail=$null; sshAlias=$null; githubAccount=$null }
                copilot = [ordered]@{ provider='GitHub'; account=$null }
                microsoft365 = $false
                isolated = $true
            }
        }
    }
}

function Initialize-DevContextStorage {
    foreach ($path in @($script:ConfigRoot, $script:LogRoot)) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
    if (-not (Test-Path -LiteralPath $script:ConfigFile)) {
        [ordered]@{
            schemaVersion = 2
            projectRootCandidates = @('C:\dos\pwsh','D:\dos\pwsh','E:\pwsh')
            extraRootCandidates = @('C:\dos\extra','D:\dos\extra','E:\extra')
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:ConfigFile -Encoding utf8
    }
    if (-not (Test-Path -LiteralPath $script:IdentityFile)) {
        New-IdentityStore | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:IdentityFile -Encoding utf8
    }
}

function Read-IdentityStore {
    Initialize-DevContextStorage
    try {
        $store = Get-Content -LiteralPath $script:IdentityFile -Raw | ConvertFrom-Json -AsHashtable
        if ([int]$store.schemaVersion -lt 2) { throw 'Legacy identity schema.' }
        return $store
    }
    catch {
        $backup = "$script:IdentityFile.legacy-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        if (Test-Path -LiteralPath $script:IdentityFile) { Copy-Item -LiteralPath $script:IdentityFile -Destination $backup -Force }
        $store = New-IdentityStore
        $store | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:IdentityFile -Encoding utf8
        return $store
    }
}

function Write-IdentityStore {
    param([hashtable]$Store)
    $Store.updatedAt = (Get-Date).ToString('o')
    $temp = "$script:IdentityFile.tmp"
    $Store | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temp -Encoding utf8
    Move-Item -LiteralPath $temp -Destination $script:IdentityFile -Force
}

function Get-Roots {
    $projectCandidates = @('C:\dos\pwsh','D:\dos\pwsh','E:\pwsh')
    $extraCandidates = @('C:\dos\extra','D:\dos\extra','E:\extra')
    try {
        $cfg = Get-Content -LiteralPath $script:ConfigFile -Raw | ConvertFrom-Json
        $names = @($cfg.PSObject.Properties.Name)
        if ($names -contains 'projectRootCandidates') { $projectCandidates = @($cfg.projectRootCandidates) }
        elseif ($names -contains 'projectRoots') { $projectCandidates = @($cfg.projectRoots.personal) }
        if ($names -contains 'extraRootCandidates') { $extraCandidates = @($cfg.extraRootCandidates) }
        elseif ($names -contains 'projectRoots') { $extraCandidates = @($cfg.projectRoots.extra) }
    }
    catch { Write-Warning "config.json invalido; usando caminhos padrao. $($_.Exception.Message)" }

    $projects = @($projectCandidates | ForEach-Object {
        [pscustomobject]@{ Path=[string]$_; Exists=(Test-Path -LiteralPath $_); IsGitRepository=(Test-Path -LiteralPath (Join-Path $_ '.git')) }
    })
    $extras = @($extraCandidates | ForEach-Object {
        [pscustomobject]@{ Path=[string]$_; Exists=(Test-Path -LiteralPath $_); IsGitRepository=(Test-Path -LiteralPath (Join-Path $_ '.git')) }
    })
    return [pscustomobject]@{
        ProjectCandidates = $projects
        SelectedProjectRoot = ($projects | Where-Object { $_.Exists } | Select-Object -First 1 -ExpandProperty Path)
        ExtraCandidates = $extras
        SelectedExtraRoot = ($extras | Where-Object { $_.Exists } | Select-Object -First 1 -ExpandProperty Path)
    }
}

function Get-GitDiagnostics {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return [pscustomobject]@{ Installed=$false } }
    $inside = (Get-NativeText { git rev-parse --is-inside-work-tree }) -eq 'true'
    $helpers = @(Get-NativeLines { git config --show-origin --get-all credential.helper } | Where-Object { $_ })
    return [pscustomobject]@{
        Installed = $true
        Global = [pscustomobject]@{ UserName=(Get-NativeText { git config --global --get user.name }); UserEmail=(Get-NativeText { git config --global --get user.email }) }
        Local = if ($inside) { [pscustomobject]@{ UserName=(Get-NativeText { git config --local --get user.name }); UserEmail=(Get-NativeText { git config --local --get user.email }) } } else { $null }
        Credential = [pscustomobject]@{ Configured=($helpers.Count -gt 0); Helpers=$helpers; ManagerConfigured=[bool]($helpers -match '(?i)manager') }
        CurrentRepository = [pscustomobject]@{
            IsRepository=$inside
            Root=if($inside){Get-NativeText { git rev-parse --show-toplevel }}else{$null}
            Branch=if($inside){Get-NativeText { git branch --show-current }}else{$null}
            Origin=if($inside){Get-NativeText { git remote get-url origin }}else{$null}
        }
    }
}

function Get-SshDiagnostics {
    $root = Join-Path $HOME '.ssh'
    $file = Join-Path $root 'config'
    $hosts = @()
    $current = $null
    if (Test-Path -LiteralPath $file) {
        foreach ($line in Get-Content -LiteralPath $file) {
            $text = $line.Trim()
            if (-not $text -or $text.StartsWith('#')) { continue }
            if ($text -match '^(?i)Host\s+(.+)$') {
                if ($current) { $hosts += [pscustomobject]$current }
                $current = [ordered]@{ Host=$Matches[1]; HostName=$null; User=$null; IdentityFile=@() }
                continue
            }
            if ($current -and $text -match '^(?i)HostName\s+(.+)$') { $current.HostName=$Matches[1]; continue }
            if ($current -and $text -match '^(?i)User\s+(.+)$') { $current.User=$Matches[1]; continue }
            if ($current -and $text -match '^(?i)IdentityFile\s+(.+)$') { $current.IdentityFile += @($Matches[1]); continue }
        }
        if ($current) { $hosts += [pscustomobject]$current }
    }
    return [pscustomobject]@{
        Directory=$root; ConfigExists=(Test-Path -LiteralPath $file); ConfigPath=$file; Hosts=@($hosts)
        GitHubAliases=@($hosts | Where-Object { $_.HostName -match '(?i)github\.com' -or $_.Host -match '(?i)github' })
        PrivateKeyContentsRead=$false
    }
}

function Get-GitHubCliDiagnostics {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return [pscustomobject]@{Installed=$false;Accounts=@()} }
    $lines = Get-NativeLines { gh auth status }
    $accounts=@(); $githubHost=$null; $current=$null
    foreach ($raw in $lines) {
        $line = ($raw -replace '[^\x00-\x7F]','').Trim()
        if ($line -match '^([\w.-]+)$') { $githubHost=$Matches[1]; continue }
        if ($line -match 'Logged in to\s+\S+\s+account\s+(\S+)') {
            if ($current) { $accounts += [pscustomobject]$current }
            $current=[ordered]@{Host=$githubHost;Account=$Matches[1];Active=$false;Protocol=$null;Storage=$null}
            if($line -match '\(([^)]+)\)'){$current.Storage=$Matches[1]}
            continue
        }
        if($current -and $line -match 'Active account:\s*(true|false)'){$current.Active=[bool]::Parse($Matches[1]);continue}
        if($current -and $line -match 'Git operations protocol:\s*(\S+)'){$current.Protocol=$Matches[1];continue}
    }
    if($current){$accounts += [pscustomobject]$current}
    return [pscustomobject]@{Installed=$true;Accounts=@($accounts);ActiveAccount=($accounts|Where-Object Active|Select-Object -First 1 -ExpandProperty Account);TokenValuesCaptured=$false}
}

function Get-SshIdentityProbe {
    param([string]$Alias)
    $ssh = Get-Command ssh -ErrorAction SilentlyContinue
    if(-not $ssh){return [pscustomobject]@{Authenticated=$false;Account=$null;ExitCode=$null;Message='ssh not found'}}
    $lines=@(& $ssh.Source -T -o BatchMode=yes -o ConnectTimeout=8 "git@$Alias" 2>&1 | ForEach-Object {[string]$_})
    $exitCode=$LASTEXITCODE; $text=($lines -join "`n").Trim(); $account=$null
    if($text -match "(?im)Hi\s+([^!\s]+)!\s+You've successfully authenticated"){$account=$Matches[1]}
    return [pscustomobject]@{Authenticated=[bool]$account;Account=$account;ExitCode=$exitCode;Message=$text}
}

function Read-Required {
    param([string]$Prompt,[string]$Default='')
    $suffix=if($Default){" [$Default]"}else{''}
    while($true){
        $value=Read-Host "$Prompt$suffix"
        if([string]::IsNullOrWhiteSpace($value)){$value=$Default}
        if(-not [string]::IsNullOrWhiteSpace($value)){return $value.Trim()}
        Write-Host 'Valor obrigatorio.' -ForegroundColor Yellow
    }
}

function Select-FromList {
    param([string]$Prompt,[array]$Items,[string]$DisplayProperty='')
    if(-not $Items -or $Items.Count -eq 0){return $null}
    Write-Host $Prompt -ForegroundColor Cyan
    for($i=0;$i -lt $Items.Count;$i++){$label=if($DisplayProperty){$Items[$i].$DisplayProperty}else{[string]$Items[$i]};Write-Host ("  [{0}] {1}" -f ($i+1),$label)}
    while($true){$answer=Read-Host 'Numero';$number=0;if([int]::TryParse($answer,[ref]$number)-and$number-ge1-and$number-le$Items.Count){return $Items[$number-1]};Write-Host 'Selecao invalida.' -ForegroundColor Yellow}
}

function Show-Identities { Read-IdentityStore | ConvertTo-Json -Depth 10 }

function Invoke-IdentitySetup {
    $store=Read-IdentityStore; $ssh=Get-SshDiagnostics; $gh=Get-GitHubCliDiagnostics; $git=Get-GitDiagnostics
    $names=if($Identity){@($Identity)}else{@('Personal','Enterprise','Extra')}
    foreach($name in $names){
        Write-Host "`nIdentity Setup: $name" -ForegroundColor Cyan
        $data=$store.identities[$name]
        $gitName=Read-Required 'Git user.name' $(if($name -eq 'Personal'){$git.Global.UserName}else{$data.git.userName})
        $gitEmail=Read-Required 'Git user.email' $(if($name -eq 'Personal'){$git.Global.UserEmail}else{$data.git.userEmail})
        $aliases=@($ssh.GitHubAliases)
        $preferred=@($aliases|Where-Object{($name-eq'Personal'-and$_.Host-match'(?i)pessoal|personal')-or($name-eq'Enterprise'-and$_.Host-match'(?i)cindumel|empresa|enterprise')-or($name-eq'Extra'-and$_.Host-match'(?i)extra|larissa')})
        if($preferred){$aliases=@($preferred)+@($aliases|Where-Object{$_.Host -notin $preferred.Host})}
        $selected=Select-FromList 'Selecione o alias SSH do GitHub:' $aliases 'Host'
        if(-not $selected){throw 'Nenhum alias GitHub encontrado.'}
        $account=Read-Required 'Nome da conta GitHub' $(if($name-eq'Personal'){$gh.ActiveAccount}else{$data.git.githubAccount})
        $copilot=Read-Required 'Conta GitHub Copilot pretendida' $(if($data.copilot.account){$data.copilot.account}else{$account})
        $data.git.userName=$gitName; $data.git.userEmail=$gitEmail; $data.git.sshAlias=$selected.Host; $data.git.githubAccount=$account
        $data.copilot.provider='GitHub'; $data.copilot.account=$copilot; $data.microsoft365=($name-eq'Enterprise'); $data.isolated=($name-eq'Extra'); $data.configured=$true
        $store.identities[$name]=$data
        Write-Host "$name configurada. Nenhum token, senha ou chave foi armazenado." -ForegroundColor Green
    }
    Write-IdentityStore $store
    Show-Identities
}

function Test-OneIdentity {
    param([string]$Name,[hashtable]$Data)
    $ssh=Get-SshDiagnostics; $alias=@($ssh.GitHubAliases|Where-Object Host -eq $Data.git.sshAlias); $issues=@()
    if(-not $Data.configured){$issues+='Not configured'};if(-not $Data.git.userName){$issues+='Missing Git user.name'};if(-not $Data.git.userEmail){$issues+='Missing Git user.email'};if(-not $alias){$issues+='SSH alias not found'};if(-not $Data.git.githubAccount){$issues+='Missing GitHub account'};if($Name-eq'Extra'-and-not$Data.isolated){$issues+='Extra must be isolated'}
    return [pscustomobject]@{Identity=$Name;Configured=[bool]$Data.configured;GitHubAccount=$Data.git.githubAccount;SshAlias=$Data.git.sshAlias;CopilotAccount=$Data.copilot.account;Microsoft365=[bool]$Data.microsoft365;Isolated=[bool]$Data.isolated;Valid=($issues.Count-eq0);Issues=$issues}
}

function Invoke-IdentityTest {
    $store=Read-IdentityStore;$names=if($Identity){@($Identity)}else{@('Personal','Enterprise','Extra')};$results=@($names|ForEach-Object{Test-OneIdentity $_ $store.identities[$_]})
    if($Json){$results|ConvertTo-Json -Depth 8}else{$results|Format-Table Identity,Configured,GitHubAccount,SshAlias,CopilotAccount,Microsoft365,Isolated,Valid -AutoSize}
}

function Invoke-IdentityVerify {
    $store=Read-IdentityStore;$names=if($Identity){@($Identity)}else{@('Personal','Enterprise','Extra')};$results=@()
    foreach($name in $names){
        $data=$store.identities[$name];$expected=[string]$data.git.githubAccount;$alias=[string]$data.git.sshAlias
        if(-not$data.configured-or-not$expected-or-not$alias){$results+=[pscustomobject]@{Identity=$name;Expected=$expected;SshAlias=$alias;Authenticated=$null;AccountMatch=$false;IsolationValid=($name-ne'Extra'-or[bool]$data.isolated);Result='NOT_CONFIGURED'};continue}
        $probe=Get-SshIdentityProbe $alias;$match=$probe.Authenticated-and($probe.Account-ieq$expected);$isolation=($name-ne'Extra')-or[bool]$data.isolated
        $state=if(-not$probe.Authenticated){'SSH_FAILED'}elseif(-not$match){'IDENTITY_MISMATCH'}elseif(-not$isolation){'ISOLATION_FAILED'}else{'PASS'}
        $results+=[pscustomobject]@{Identity=$name;Expected=$expected;SshAlias=$alias;Authenticated=$probe.Account;AccountMatch=$match;IsolationValid=$isolation;Result=$state;ExitCode=$probe.ExitCode}
    }
    $overall=if(@($results|Where-Object{$_.Result-ne'PASS'}).Count-eq0){'VERIFIED'}else{'FAILED'}
    $report=[pscustomobject]@{App="$script:AppName $script:AppVersion";Overall=$overall;Results=$results}
    if($Json){$report|ConvertTo-Json -Depth 8}else{$results|Format-Table Identity,Expected,SshAlias,Authenticated,AccountMatch,IsolationValid,Result -AutoSize;Write-Host "Overall: $overall" -ForegroundColor $(if($overall-eq'VERIFIED'){'Green'}else{'Red'})}
}

function Invoke-DevDoctor {
    Initialize-DevContextStorage;$roots=Get-Roots;$git=Get-GitDiagnostics;$gh=Get-GitHubCliDiagnostics;$ssh=Get-SshDiagnostics
    $report=[pscustomobject]@{App="$script:AppName $script:AppVersion";Timestamp=(Get-Date).ToString('o');Computer=$env:COMPUTERNAME;User=$env:USERNAME;PowerShell=$PSVersionTable.PSVersion.ToString();Roots=$roots;Git=$git;GitHubCli=$gh;SSH=$ssh;ConfigFile=$script:ConfigFile;IdentityFile=$script:IdentityFile}
    if($Json){$report|ConvertTo-Json -Depth 12}else{Write-Host "DevContext $script:AppVersion - Doctor" -ForegroundColor Cyan;Write-Host "Project Root............ $($roots.SelectedProjectRoot)";Write-Host "GitHub active........... $($gh.ActiveAccount)"}
}

function Read-Choice { param([string]$Prompt,[string[]]$Options); Write-Host $Prompt -ForegroundColor Cyan;for($i=0;$i-lt$Options.Count;$i++){Write-Host("  [{0}] {1}"-f($i+1),$Options[$i])};while($true){$a=Read-Host'Numero';$n=0;if([int]::TryParse($a,[ref]$n)-and$n-ge1-and$n-le$Options.Count){return$Options[$n-1]};Write-Host'Selecao invalida.' -ForegroundColor Yellow} }
function Get-ProjectModel { param([string]$Name);$models=@{'Personal-Personal'=@{RepositoryIdentity='Personal';CopilotIdentity='Personal';Microsoft365=$false;Color='#1F6FEB';Label='GIT PERSONAL | COPILOT PERSONAL'};'Personal-Enterprise'=@{RepositoryIdentity='Personal';CopilotIdentity='Enterprise';Microsoft365=$true;Color='#6F42C1';Label='GIT PERSONAL | COPILOT ENTERPRISE'};'Enterprise-Enterprise'=@{RepositoryIdentity='Enterprise';CopilotIdentity='Enterprise';Microsoft365=$true;Color='#8B1E1E';Label='GIT ENTERPRISE | COPILOT ENTERPRISE'};'Enterprise-Personal'=@{RepositoryIdentity='Enterprise';CopilotIdentity='Personal';Microsoft365=$false;Color='#B45309';Label='GIT ENTERPRISE | COPILOT PERSONAL'};'Extra-Extra'=@{RepositoryIdentity='Extra';CopilotIdentity='Extra';Microsoft365=$false;Color='#0F766E';Label='EXTRA ISOLATED'}};return$models[$Name] }
function Assert-IdentityVerified { param([string]$IdentityName);$store=Read-IdentityStore;$data=$store.identities[$IdentityName];if(-not$data-or-not$data.configured){throw"Identidade $IdentityName nao configurada."};$probe=Get-SshIdentityProbe$data.git.sshAlias;if(-not$probe.Authenticated){throw'Falha SSH.'};if($probe.Account-ine$data.git.githubAccount){throw"Identity mismatch: $($probe.Account)"};if($IdentityName-eq'Extra'-and-not$data.isolated){throw'Extra deve estar isolada.'};return$data }
function ConvertTo-SafeProjectName {param([string]$Name);$safe=$Name.Trim()-replace'[<>:"/\\|?*]','-';$safe=$safe-replace'\s+','-';$safe=$safe.Trim('.','-',' ');if([string]::IsNullOrWhiteSpace($safe)){throw'Nome invalido.'};return$safe}
function Write-Utf8Json {param($Value,[string]$Path,[int]$Depth=12);$Value|ConvertTo-Json -Depth $Depth|Set-Content -LiteralPath $Path -Encoding utf8}

function New-DevProject {
    $store=Read-IdentityStore;$roots=Get-Roots;$selectedModel=$ContextModel;if(-not$selectedModel){$selectedModel=Read-Choice'Selecione o contexto do projeto:'@('Personal-Personal','Personal-Enterprise','Enterprise-Enterprise','Enterprise-Personal','Extra-Extra')}
    $model=Get-ProjectModel$selectedModel;$repositoryIdentity=Assert-IdentityVerified$model.RepositoryIdentity;$copilotIdentity=$store.identities[$model.CopilotIdentity];if(-not$copilotIdentity.configured){throw'Identidade Copilot nao configurada.'}
    $name=if($ProjectName){$ProjectName}else{Read-Host'Nome do projeto'};$safeName=ConvertTo-SafeProjectName$name;$mode=if($RepositoryMode){$RepositoryMode}else{Read-Choice'Modo do repositorio:'@('Monorepo','Standalone')};if($selectedModel-eq'Extra-Extra'-and$mode-eq'Monorepo'){throw'Extra exige Standalone.'}
    $target=$Destination;if(-not$target){if($mode-eq'Monorepo'){$target=Join-Path$roots.SelectedProjectRoot$safeName}elseif($selectedModel-eq'Extra-Extra'){$base=$roots.SelectedExtraRoot;if(-not$base){$base=Read-Host'Diretorio-base Extra'};$target=Join-Path$base$safeName}else{$base=Read-Host'Diretorio-base standalone';$target=Join-Path$base$safeName}}
    $target=[IO.Path]::GetFullPath($target);if(Test-Path -LiteralPath $target){if(@(Get-ChildItem -LiteralPath $target -Force).Count-gt0){throw"Destino nao vazio: $target"}}else{New-Item -ItemType Directory -Path $target -Force|Out-Null};foreach($folder in@('.github','.vscode','docs','src','tests','tools')){New-Item -ItemType Directory -Path(Join-Path$target$folder)-Force|Out-Null}
    $context=[ordered]@{schemaVersion=1;projectName=$safeName;createdAt=(Get-Date).ToString('o');createdBy="$script:AppName $script:AppVersion";contextModel=$selectedModel;repositoryMode=$mode;repository=[ordered]@{identity=$model.RepositoryIdentity;gitHubAccount=$repositoryIdentity.git.githubAccount;sshAlias=$repositoryIdentity.git.sshAlias;userName=$repositoryIdentity.git.userName;userEmail=$repositoryIdentity.git.userEmail};copilot=[ordered]@{identity=$model.CopilotIdentity;account=$copilotIdentity.copilot.account;provider='GitHub';automaticAccountSwitch=$false};microsoft365Copilot=[ordered]@{enabled=[bool]$model.Microsoft365;automaticContextTransfer=$false};isolation=[ordered]@{required=($selectedModel-eq'Extra-Extra')}}
    Write-Utf8Json $context (Join-Path$target'.project-context.json')
    $workspace=[ordered]@{folders=@(@{path='.'});settings=[ordered]@{'window.title'="$safeName [$($model.Label)]";'workbench.colorCustomizations'=[ordered]@{'titleBar.activeBackground'=$model.Color;'titleBar.activeForeground'='#FFFFFF';'statusBar.background'=$model.Color;'statusBar.foreground'='#FFFFFF'};'powershell.powerShellDefaultVersion'='PowerShell 7';'files.encoding'='utf8'};extensions=[ordered]@{recommendations=@('ms-vscode.powershell','github.copilot','github.copilot-chat')}};$workspacePath=Join-Path$target"$safeName.code-workspace";Write-Utf8Json $workspace $workspacePath
    Set-Content -LiteralPath(Join-Path$target'.github\copilot-instructions.md')-Encoding utf8 -Value"# Copilot instructions for $safeName`n`nProject context: $selectedModel`nRepository: $($repositoryIdentity.git.githubAccount)`nIntended Copilot: $($copilotIdentity.copilot.account)`nNever store credentials or private keys."
    Set-Content -LiteralPath(Join-Path$target'README.md')-Encoding utf8 -Value"# $safeName`n`nContext: $selectedModel`nRepository: $($repositoryIdentity.git.githubAccount)`nCopilot: $($copilotIdentity.copilot.account)"
    Set-Content -LiteralPath(Join-Path$target'.gitignore')-Encoding utf8 -Value"*.log`nTemp/`n.local/`n.env`n.env.*"
    $start=@"
#requires -Version 7.0
`$ErrorActionPreference='Stop'
`$root=`$PSScriptRoot
`$context=Get-Content -LiteralPath(Join-Path `$root '.project-context.json')-Raw|ConvertFrom-Json
Write-Host "Project....... `$(`$context.projectName)" -ForegroundColor Cyan
Write-Host "Context....... `$(`$context.contextModel)"
Write-Host "GitHub........ `$(`$context.repository.gitHubAccount)"
Write-Host "Copilot....... `$(`$context.copilot.account)"
Write-Host "M365 Copilot.. `$(`$context.microsoft365Copilot.enabled)"
Write-Host "Confirm GitHub Copilot account preference for this workspace: `$(`$context.copilot.account)" -ForegroundColor Yellow
`$workspace=Join-Path `$root '$safeName.code-workspace'
& code `$workspace
"@
    Set-Content -LiteralPath(Join-Path$target'Start-Dev.ps1')-Value$start-Encoding utf8
    if($mode-eq'Standalone'){Push-Location$target;try{git init|Out-Null;git config --local user.name $repositoryIdentity.git.userName;git config --local user.email $repositoryIdentity.git.userEmail;git add .}finally{Pop-Location}}
    Write-Host'Projeto criado com sucesso.' -ForegroundColor Green;Write-Host"Path........... $target";Write-Host"Repository..... $($repositoryIdentity.git.githubAccount)";Write-Host"Copilot........ $($copilotIdentity.copilot.account)"
}

Initialize-DevContextStorage
switch($Command){'doctor'{Invoke-DevDoctor};'status'{Invoke-DevDoctor};'identities'{Show-Identities};'config'{Get-Content -LiteralPath $script:ConfigFile -Raw};'identity-setup'{Invoke-IdentitySetup};'identity-test'{Invoke-IdentityTest};'identity-verify'{Invoke-IdentityVerify};'new'{New-DevProject}}
