#requires -Version 7.0
[CmdletBinding()]
param(
  [ValidateSet('doctor','status','identities','config','identity-setup','identity-test','identity-verify','new')]
  [string]$Command='doctor',
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
$ErrorActionPreference='Stop'
$script:AppName='DevContext'; $script:AppVersion='0.3.0'
$script:ConfigRoot=Join-Path $env:LOCALAPPDATA $script:AppName
$script:ConfigFile=Join-Path $script:ConfigRoot 'config.json'
$script:IdentityFile=Join-Path $script:ConfigRoot 'identities.json'
$script:LogRoot=Join-Path $script:ConfigRoot 'logs'

function Get-NativeLines([scriptblock]$Script){ try{@(& $Script 2>&1|%{[string]$_})}catch{@()} }
function Get-NativeText([scriptblock]$Script){((Get-NativeLines $Script)-join "`n").Trim()}
function New-IdentityStore { [ordered]@{schemaVersion=2;updatedAt=$null;identities=[ordered]@{
 Personal=[ordered]@{configured=$false;git=[ordered]@{userName=$null;userEmail=$null;sshAlias=$null;githubAccount=$null};copilot=[ordered]@{provider='GitHub';account=$null};microsoft365=$false;isolated=$false}
 Enterprise=[ordered]@{configured=$false;git=[ordered]@{userName=$null;userEmail=$null;sshAlias=$null;githubAccount=$null};copilot=[ordered]@{provider='GitHub';account=$null};microsoft365=$true;isolated=$false}
 Extra=[ordered]@{configured=$false;git=[ordered]@{userName=$null;userEmail=$null;sshAlias=$null;githubAccount=$null};copilot=[ordered]@{provider='GitHub';account=$null};microsoft365=$false;isolated=$true}
}}}
function Initialize-DevContextStorage {
 foreach($p in @($script:ConfigRoot,$script:LogRoot)){if(-not(Test-Path $p)){New-Item -Type Directory $p -Force|Out-Null}}
 if(-not(Test-Path $script:ConfigFile)){[ordered]@{schemaVersion=2;projectRootCandidates=@('C:\dos\pwsh','D:\dos\pwsh','E:\pwsh');extraRootCandidates=@('C:\dos\extra','D:\dos\extra','E:\extra')}|ConvertTo-Json -Depth 8|Set-Content $script:ConfigFile -Encoding utf8}
 if(-not(Test-Path $script:IdentityFile)){New-IdentityStore|ConvertTo-Json -Depth 10|Set-Content $script:IdentityFile -Encoding utf8}
}
function Read-IdentityStore { Initialize-DevContextStorage; try{$s=Get-Content $script:IdentityFile -Raw|ConvertFrom-Json -AsHashtable;if([int]$s.schemaVersion-lt2){throw};$s}catch{$bak="$script:IdentityFile.legacy-$(Get-Date -Format yyyyMMdd-HHmmss).json";Copy-Item $script:IdentityFile $bak -Force;$s=New-IdentityStore;$s|ConvertTo-Json -Depth 10|Set-Content $script:IdentityFile -Encoding utf8;$s} }
function Write-IdentityStore([hashtable]$Store){$Store.updatedAt=(Get-Date).ToString('o');$tmp="$script:IdentityFile.tmp";$Store|ConvertTo-Json -Depth 10|Set-Content $tmp -Encoding utf8;Move-Item $tmp $script:IdentityFile -Force}
function Get-Tool([string]$Name){$c=Get-Command $Name -EA SilentlyContinue|Select -First 1;if(-not$c){return[pscustomobject]@{Name=$Name;Installed=$false;Path=$null}};$v=switch($Name){git{Get-NativeText{&$c.Source --version}} gh{Get-NativeLines{&$c.Source --version}|Select -First 1} code{Get-NativeLines{&$c.Source --version}|Select -First 1} ssh{Get-NativeLines{&$c.Source -V}|Select -First 1} copilot{Get-NativeLines{&$c.Source --version}|Select -First 1}};[pscustomobject]@{Name=$Name;Installed=$true;Path=$c.Source;Version=[string]$v}}
function Get-Roots {$cfg=Get-Content $script:ConfigFile -Raw|ConvertFrom-Json;$pc=if($cfg.projectRootCandidates){@($cfg.projectRootCandidates)}elseif($cfg.projectRoots){@($cfg.projectRoots.personal)}else{@('C:\dos\pwsh','D:\dos\pwsh','E:\pwsh')};$ec=if($cfg.extraRootCandidates){@($cfg.extraRootCandidates)}elseif($cfg.projectRoots){@($cfg.projectRoots.extra)}else{@('C:\dos\extra','D:\dos\extra','E:\extra')};$p=@($pc|%{[pscustomobject]@{Path=$_;Exists=Test-Path $_;IsGitRepository=Test-Path(Join-Path $_ '.git')}});$e=@($ec|%{[pscustomobject]@{Path=$_;Exists=Test-Path $_;IsGitRepository=Test-Path(Join-Path $_ '.git')}});[pscustomobject]@{ProjectCandidates=$p;SelectedProjectRoot=($p|? Exists|Select -First 1 -Expand Path);ExtraCandidates=$e;SelectedExtraRoot=($e|? Exists|Select -First 1 -Expand Path)}}
function Get-GitDiagnostics {$inside=(Get-NativeText{git rev-parse --is-inside-work-tree})-eq'true';$h=@(Get-NativeLines{git config --show-origin --get-all credential.helper}|?{$_});[pscustomobject]@{Installed=[bool](Get-Command git -EA SilentlyContinue);Global=[pscustomobject]@{UserName=Get-NativeText{git config --global --get user.name};UserEmail=Get-NativeText{git config --global --get user.email}};Local=if($inside){[pscustomobject]@{UserName=Get-NativeText{git config --local --get user.name};UserEmail=Get-NativeText{git config --local --get user.email}}}else{$null};Credential=[pscustomobject]@{Configured=$h.Count -gt 0;Helpers=$h;ManagerConfigured=[bool]($h-match'(?i)manager')};CurrentRepository=[pscustomobject]@{IsRepository=$inside;Root=if($inside){Get-NativeText{git rev-parse --show-toplevel}}else{$null};Branch=if($inside){Get-NativeText{git branch --show-current}}else{$null};Origin=if($inside){Get-NativeText{git remote get-url origin}}else{$null}}}}
function Get-SshDiagnostics {$root=Join-Path $HOME '.ssh';$file=Join-Path $root 'config';$hosts=@();$cur=$null;if(Test-Path$file){foreach($line in Get-Content$file){$t=$line.Trim();if(!$t-or$t.StartsWith('#')){continue};if($t-match'^(?i)Host\s+(.+)$'){if($cur){$hosts+=[pscustomobject]$cur};$cur=[ordered]@{Host=$Matches[1];HostName=$null;User=$null;IdentityFile=@()};continue};if($cur-and$t-match'^(?i)HostName\s+(.+)$'){$cur.HostName=$Matches[1];continue};if($cur-and$t-match'^(?i)User\s+(.+)$'){$cur.User=$Matches[1];continue};if($cur-and$t-match'^(?i)IdentityFile\s+(.+)$'){$cur.IdentityFile+=@($Matches[1])}};if($cur){$hosts+=[pscustomobject]$cur}};[pscustomobject]@{Directory=$root;ConfigExists=Test-Path$file;ConfigPath=$file;Hosts=@($hosts);GitHubAliases=@($hosts|?{$_.HostName-match'(?i)github\.com'-or$_.Host-match'(?i)github'});PrivateKeyContentsRead=$false}}
function Get-GitHubCliDiagnostics {$lines=Get-NativeLines{gh auth status};$a=@();$ghHostName=$null;$cur=$null;foreach($raw in $lines){$line=($raw-replace'[^\x00-\x7F]','').Trim();if($line-match'^([\w.-]+)$'){$ghHostName=$Matches[1];continue};if($line-match'Logged in to\s+\S+\s+account\s+(\S+)'){if($cur){$a+=[pscustomobject]$cur};$cur=[ordered]@{Host=$ghHostName;Account=$Matches[1];Active=$false;Protocol=$null;Storage=$null};if($line-match'\(([^)]+)\)'){$cur.Storage=$Matches[1]};continue};if($cur-and$line-match'Active account:\s*(true|false)'){$cur.Active=[bool]::Parse($Matches[1])};if($cur-and$line-match'Git operations protocol:\s*(\S+)'){$cur.Protocol=$Matches[1]}};if($cur){$a+=[pscustomobject]$cur};[pscustomobject]@{Installed=[bool](Get-Command gh -EA SilentlyContinue);Accounts=@($a);ActiveAccount=($a|? Active|Select -First 1 -Expand Account);TokenValuesCaptured=$false}}
function Get-VSCodeDiagnostics {$c=Get-Command code -EA SilentlyContinue;if(!$c){return[pscustomobject]@{Installed=$false}};$ext=@(Get-NativeLines{code --list-extensions --show-versions}|?{$_-match'@'});$disk=Join-Path$HOME '.vscode\extensions';$d=if(Test-Path$disk){@(Get-ChildItem$disk -Directory|Select -Expand Name)}else{@()};$all=@($ext+$d|Sort -Unique);$user=Join-Path$env:APPDATA 'Code\User';$pd=Join-Path$user 'profiles';$p=if(Test-Path$pd){@(Get-ChildItem$pd -Directory|%{[pscustomobject]@{Id=$_.Name;Path=$_.FullName}})}else{@()};[pscustomobject]@{Installed=$true;Executable=$c.Source;UserData=$user;Profiles=$p;Extensions=[pscustomobject]@{GitHubCopilot=@($all|?{$_-match'(?i)^github\.copilot'});PowerShell=@($all|?{$_-match'(?i)^ms-vscode\.powershell'})}}}
function Get-CopilotDiagnostics {$c=Get-Command copilot -EA SilentlyContinue;if(!$c){return[pscustomobject]@{Installed=$false}};[pscustomobject]@{Installed=$true;Path=$c.Source;Source=if($c.Source-match'[\\/]Microsoft VS Code[\\/].*copilot-shim'){'VSCodeShim'}else{'Other'};Version=(Get-NativeLines{copilot --version}|Select -First 1)}}
function Read-Required([string]$Prompt,[string]$Default=''){$s=if($Default){" [$Default]"}else{''};while($true){$v=Read-Host "$Prompt$s";if([string]::IsNullOrWhiteSpace($v)){$v=$Default};if(![string]::IsNullOrWhiteSpace($v)){return $v.Trim()};Write-Host 'Valor obrigatorio.' -ForegroundColor Yellow}}
function Select-FromList([string]$Prompt,[array]$Items,[string]$DisplayProperty=''){if(!$Items-or$Items.Count -eq 0){return$null};Write-Host $Prompt -ForegroundColor Cyan;for($i=0;$i-lt$Items.Count;$i++){$l=if($DisplayProperty){$Items[$i].$DisplayProperty}else{[string]$Items[$i]};Write-Host("  [{0}] {1}"-f($i+1),$l)};while($true){$x=Read-Host 'Numero';$n=0;if([int]::TryParse($x,[ref]$n)-and$n-ge1-and$n-le$Items.Count){return$Items[$n-1]};Write-Host 'Selecao invalida.' -ForegroundColor Yellow}}
function Show-Identities {Read-IdentityStore|ConvertTo-Json -Depth 10}
function Invoke-IdentitySetup {$store=Read-IdentityStore;$ssh=Get-SshDiagnostics;$gh=Get-GitHubCliDiagnostics;$git=Get-GitDiagnostics;$names=if($Identity){@($Identity)}else{@('Personal','Enterprise','Extra')};foreach ($name in $names){Write-Host"`nIdentity Setup: $name" -ForegroundColor Cyan;$d=$store.identities[$name];$gn=Read-Required'Git user.name'$(if($name-eq'Personal'){$git.Global.UserName}else{$d.git.userName});$ge=Read-Required'Git user.email'$(if($name-eq'Personal'){$git.Global.UserEmail}else{$d.git.userEmail});$aliases=@($ssh.GitHubAliases);$pref=@($aliases|?{($name-eq'Personal'-and$_.Host-match'(?i)pessoal|personal')-or($name-eq'Enterprise'-and$_.Host-match'(?i)cindumel|empresa|enterprise')-or($name-eq'Extra'-and$_.Host-match'(?i)extra|larissa')});if($pref){$aliases=@($pref)+@($aliases|?{$_.Host-notin$pref.Host})};$sel=Select-FromList'Selecione o alias SSH do GitHub:'$aliases'Host';if(!$sel){throw'Nenhum alias GitHub encontrado'};$acct=Read-Required'Nome da conta GitHub'$(if($name-eq'Personal'){$gh.ActiveAccount}else{$d.git.githubAccount});$cop=Read-Required'Conta GitHub Copilot pretendida'$(if($d.copilot.account){$d.copilot.account}else{$acct});$d.git.userName=$gn;$d.git.userEmail=$ge;$d.git.sshAlias=$sel.Host;$d.git.githubAccount=$acct;$d.copilot.account=$cop;$d.microsoft365=$name-eq'Enterprise';$d.isolated=$name-eq'Extra';$d.configured=$true;$store.identities[$name]=$d;Write-Host"$name configurada. Nenhum token, senha ou chave foi armazenado." -ForegroundColor Green};Write-IdentityStore $store;Show-Identities }
function Test-OneIdentity([string]$Name,[hashtable]$Data){$ssh=Get-SshDiagnostics;$alias=@($ssh.GitHubAliases|? Host-eq$Data.git.sshAlias);$issues=@();if(!$Data.configured){$issues+='Not configured'};if(!$Data.git.userName){$issues+='Missing Git user.name'};if(!$Data.git.userEmail){$issues+='Missing Git user.email'};if(!$alias){$issues+='SSH alias not found'};if(!$Data.git.githubAccount){$issues+='Missing GitHub account'};if($Name-eq'Extra'-and!$Data.isolated){$issues+='Extra must be isolated'};[pscustomobject]@{Identity=$Name;Configured=[bool]$Data.configured;GitHubAccount=$Data.git.githubAccount;SshAlias=$Data.git.sshAlias;CopilotAccount=$Data.copilot.account;Microsoft365=[bool]$Data.microsoft365;Isolated=[bool]$Data.isolated;Valid=$issues.Count -eq 0;Issues=$issues}}
function Invoke-IdentityTest {$s=Read-IdentityStore;$names=if($Identity){@($Identity)}else{@('Personal','Enterprise','Extra')};$r=@($names|%{Test-OneIdentity $_ $s.identities[$_]});if($Json){$r|ConvertTo-Json -Depth 8}else{$r|Format-Table Identity,Configured,GitHubAccount,SshAlias,CopilotAccount,Microsoft365,Isolated,Valid -AutoSize}}
function Invoke-SshIdentityProbe([string]$Alias){$ssh=Get-Command ssh -EA SilentlyContinue;if (-not $ssh){return[pscustomobject]@{Authenticated=$false;Account=$null;ExitCode=$null;Message='ssh not found'}};$lines=@(&$ssh.Source -T -o BatchMode=yes -o ConnectTimeout=8 "git@$Alias" 2>&1|%{[string]$_});$exit=$LASTEXITCODE;$text=($lines-join"`n").Trim();$acct=$null;if($text-match"(?im)Hi\s+([^!\s]+)!\s+You've successfully authenticated"){$acct=$Matches[1]};[pscustomobject]@{Authenticated=[bool]$acct;Account=$acct;ExitCode=$exit;Message=$text}}
function Invoke-IdentityVerify {$s=Read-IdentityStore;$names=if($Identity){@($Identity)}else{@('Personal','Enterprise','Extra')};$r=@();foreach ($name in $names){$d=$s.identities[$name];$expected=[string]$d.git.githubAccount;$alias=[string]$d.git.sshAlias;if (-not $d.configured -or -not $expected -or -not $alias){$r+=[pscustomobject]@{Identity=$name;Expected=$expected;SshAlias=$alias;Authenticated=$null;AccountMatch=$false;IsolationValid=($name -ne 'Extra'-or [bool]$d.isolated);Result='NOT_CONFIGURED'};continue};$p=Invoke-SshIdentityProbe $alias;$m=$p.Authenticated -and ($p.Account -ieq $expected);$iso=($name -ne 'Extra')-or [bool]$d.isolated;$state=if (-not $p.Authenticated){'SSH_FAILED'}elseif (-not $m){'IDENTITY_MISMATCH'}elseif (-not $iso){'ISOLATION_FAILED'}else{'PASS'};$r+=[pscustomobject]@{Identity=$name;Expected=$expected;SshAlias=$alias;Authenticated=$p.Account;AccountMatch=$m;IsolationValid=$iso;Result=$state;ExitCode=$p.ExitCode}};$overall=if(@($r | Where-Object { $_.Result -ne 'PASS' }).Count -eq 0){'VERIFIED'}else{'FAILED'};$report=[pscustomobject]@{App="$script:AppName $script:AppVersion";Overall=$overall;Results=$r;Note='GitHub SSH normally returns exit code 1 after successful authentication because shell access is disabled; validation uses the GitHub greeting.'};if($Json){$report|ConvertTo-Json -Depth 8}else{$r|Format-Table Identity,Expected,SshAlias,Authenticated,AccountMatch,IsolationValid,Result -AutoSize;Write-Host "Overall: $overall" -ForegroundColor $(if($overall -eq 'VERIFIED'){'Green'}else{'Red'})}}
function Invoke-DevDoctor {Initialize-DevContextStorage;$roots=Get-Roots;$git=Get-GitDiagnostics;$gh=Get-GitHubCliDiagnostics;$ssh=Get-SshDiagnostics;$vs=Get-VSCodeDiagnostics;$cop=Get-CopilotDiagnostics;$r=[pscustomobject]@{App="$script:AppName $script:AppVersion";Timestamp=(Get-Date).ToString('o');Computer=$env:COMPUTERNAME;User=$env:USERNAME;PowerShell=[pscustomobject]@{Version=$PSVersionTable.PSVersion.ToString();MeetsRequirement=$PSVersionTable.PSVersion.Major-ge7;Edition=$PSVersionTable.PSEdition};Tools=@('git','gh','code','ssh','copilot')|%{Get-Tool $_};Roots=$roots;Git=$git;GitHubCli=$gh;SSH=$ssh;VSCode=$vs;CopilotCLI=$cop;Readiness=[pscustomobject]@{ProjectRootFound=[bool]$roots.SelectedProjectRoot;ExtraRootFound=[bool]$roots.SelectedExtraRoot;PersonalCandidateDetected=[bool]($gh.ActiveAccount-and$git.Global.UserEmail);PersonalGitHubCandidate=$gh.ActiveAccount;Status=if($roots.SelectedProjectRoot-and$gh.ActiveAccount){'READY_FOR_IDENTITY_SETUP'}else{'NEEDS_ATTENTION'}};ConfigFile=$script:ConfigFile;IdentityFile=$script:IdentityFile;ReadOnlyDiagnostics=$true};if($Json){$r|ConvertTo-Json -Depth 12}else{Write-Host"DevContext $script:AppVersion - Doctor" -ForegroundColor Cyan;Write-Host"Project Root............ $($roots.SelectedProjectRoot)";Write-Host"GitHub active........... $($gh.ActiveAccount)";Write-Host"Readiness............... $($r.Readiness.Status)"}}

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Options
    )

    Write-Host $Prompt -ForegroundColor Cyan
    for ($index = 0; $index -lt $Options.Count; $index++) {
        Write-Host ("  [{0}] {1}" -f ($index + 1), $Options[$index])
    }

    while ($true) {
        $answer = Read-Host 'Numero'
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and
            $number -ge 1 -and
            $number -le $Options.Count) {
            return $Options[$number - 1]
        }
        Write-Host 'Selecao invalida.' -ForegroundColor Yellow
    }
}

function Get-ProjectModel {
    param([string]$Name)

    $models = @{
        'Personal-Personal' = @{
            RepositoryIdentity = 'Personal'
            CopilotIdentity = 'Personal'
            Microsoft365 = $false
            Color = '#1F6FEB'
            Label = 'GIT PERSONAL | COPILOT PERSONAL'
        }
        'Personal-Enterprise' = @{
            RepositoryIdentity = 'Personal'
            CopilotIdentity = 'Enterprise'
            Microsoft365 = $true
            Color = '#6F42C1'
            Label = 'GIT PERSONAL | COPILOT ENTERPRISE'
        }
        'Enterprise-Enterprise' = @{
            RepositoryIdentity = 'Enterprise'
            CopilotIdentity = 'Enterprise'
            Microsoft365 = $true
            Color = '#8B1E1E'
            Label = 'GIT ENTERPRISE | COPILOT ENTERPRISE'
        }
        'Enterprise-Personal' = @{
            RepositoryIdentity = 'Enterprise'
            CopilotIdentity = 'Personal'
            Microsoft365 = $false
            Color = '#B45309'
            Label = 'GIT ENTERPRISE | COPILOT PERSONAL'
        }
        'Extra-Extra' = @{
            RepositoryIdentity = 'Extra'
            CopilotIdentity = 'Extra'
            Microsoft365 = $false
            Color = '#0F766E'
            Label = 'EXTRA ISOLATED'
        }
    }

    return $models[$Name]
}

function Assert-IdentityVerified {
    param([string]$IdentityName)

    $store = Read-IdentityStore
    $data = $store.identities[$IdentityName]
    if (-not $data -or -not $data.configured) {
        throw "A identidade $IdentityName nao esta configurada. Execute identity-setup."
    }

    $probe = Invoke-SshIdentityProbe -Alias $data.git.sshAlias
    if (-not $probe.Authenticated) {
        throw "Falha ao autenticar o alias SSH $($data.git.sshAlias)."
    }
    if ($probe.Account -ine $data.git.githubAccount) {
        throw "Identity mismatch: esperado $($data.git.githubAccount), recebido $($probe.Account)."
    }
    if ($IdentityName -eq 'Extra' -and -not $data.isolated) {
        throw 'A identidade Extra deve estar isolada.'
    }

    return $data
}

function ConvertTo-SafeProjectName {
    param([string]$Name)

    $safe = $Name.Trim() -replace '[<>:"/\\|?*]', '-'
    $safe = $safe -replace '\s+', '-'
    $safe = $safe.Trim('.', '-', ' ')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        throw 'Nome de projeto invalido.'
    }
    return $safe
}

function Write-Utf8Json {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path,
        [int]$Depth = 12
    )
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding utf8
}

function New-DevProject {
    $store = Read-IdentityStore
    $roots = Get-Roots

    $selectedModel = $ContextModel
    if (-not $selectedModel) {
        $selectedModel = Read-Choice -Prompt 'Selecione o contexto do projeto:' -Options @(
            'Personal-Personal',
            'Personal-Enterprise',
            'Enterprise-Enterprise',
            'Enterprise-Personal',
            'Extra-Extra'
        )
    }

    $model = Get-ProjectModel -Name $selectedModel
    $repositoryIdentity = Assert-IdentityVerified -IdentityName $model.RepositoryIdentity
    $copilotIdentity = $store.identities[$model.CopilotIdentity]
    if (-not $copilotIdentity.configured) {
        throw "A identidade Copilot $($model.CopilotIdentity) nao esta configurada."
    }

    $name = $ProjectName
    if (-not $name) {
        $name = Read-Host 'Nome do projeto'
    }
    $safeName = ConvertTo-SafeProjectName -Name $name

    $mode = $RepositoryMode
    if (-not $mode) {
        $mode = Read-Choice -Prompt 'Modo do repositorio:' -Options @('Monorepo', 'Standalone')
    }

    if ($selectedModel -eq 'Extra-Extra' -and $mode -eq 'Monorepo') {
        throw 'Projetos Extra nao podem ser criados no monorepo pessoal/empresarial.'
    }

    $target = $Destination
    if (-not $target) {
        if ($mode -eq 'Monorepo') {
            if (-not $roots.SelectedProjectRoot) {
                throw 'Nenhum ProjectRoot foi encontrado.'
            }
            $target = Join-Path $roots.SelectedProjectRoot $safeName
        }
        elseif ($selectedModel -eq 'Extra-Extra') {
            $extraBase = $roots.SelectedExtraRoot
            if (-not $extraBase) {
                $extraBase = Read-Host 'Diretorio-base Extra, por exemplo E:\extra'
            }
            $target = Join-Path $extraBase $safeName
        }
        else {
            $base = Read-Host 'Diretorio-base do repositorio standalone'
            $target = Join-Path $base $safeName
        }
    }

    $target = [System.IO.Path]::GetFullPath($target)
    if (Test-Path -LiteralPath $target) {
        if (@(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue).Count -gt 0) {
            throw "O diretorio de destino ja existe e nao esta vazio: $target"
        }
    }
    else {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
    }

    foreach ($folder in @('.github', '.vscode', 'docs', 'src', 'tests', 'tools')) {
        New-Item -ItemType Directory -Path (Join-Path $target $folder) -Force | Out-Null
    }

    $context = [ordered]@{
        schemaVersion = 1
        projectName = $safeName
        createdAt = (Get-Date).ToString('o')
        createdBy = "$script:AppName $script:AppVersion"
        contextModel = $selectedModel
        repositoryMode = $mode
        repository = [ordered]@{
            identity = $model.RepositoryIdentity
            gitHubAccount = $repositoryIdentity.git.githubAccount
            sshAlias = $repositoryIdentity.git.sshAlias
            userName = $repositoryIdentity.git.userName
            userEmail = $repositoryIdentity.git.userEmail
        }
        copilot = [ordered]@{
            identity = $model.CopilotIdentity
            account = $copilotIdentity.copilot.account
            provider = 'GitHub'
            automaticAccountSwitch = $false
        }
        microsoft365Copilot = [ordered]@{
            enabled = [bool]$model.Microsoft365
            automaticContextTransfer = $false
        }
        isolation = [ordered]@{
            required = ($selectedModel -eq 'Extra-Extra')
        }
    }
    Write-Utf8Json -Value $context -Path (Join-Path $target '.project-context.json')

    $workspace = [ordered]@{
        folders = @(@{ path = '.' })
        settings = [ordered]@{
            'window.title' = "$safeName [$($model.Label)]"
            'workbench.colorCustomizations' = [ordered]@{
                'titleBar.activeBackground' = $model.Color
                'titleBar.activeForeground' = '#FFFFFF'
                'statusBar.background' = $model.Color
                'statusBar.foreground' = '#FFFFFF'
            }
            'powershell.powerShellDefaultVersion' = 'PowerShell 7'
            'files.encoding' = 'utf8'
        }
        extensions = [ordered]@{
            recommendations = @('ms-vscode.powershell', 'github.copilot', 'github.copilot-chat')
        }
    }
    $workspacePath = Join-Path $target "$safeName.code-workspace"
    Write-Utf8Json -Value $workspace -Path $workspacePath

    $instructions = @"
# Copilot instructions for $safeName

Project context: $selectedModel
Repository identity: $($model.RepositoryIdentity) / $($repositoryIdentity.git.githubAccount)
Intended GitHub Copilot identity: $($model.CopilotIdentity) / $($copilotIdentity.copilot.account)
Microsoft 365 Copilot context allowed: $([bool]$model.Microsoft365)
Extra isolation required: $($selectedModel -eq 'Extra-Extra')

Rules:
- Use PowerShell 7 or newer.
- Never store passwords, PATs, OAuth tokens, cookies, private keys, or VS Code authentication databases.
- Keep machine-specific configuration outside Git.
- Use `$PSScriptRoot instead of fixed C:, D:, or E: project paths.
- Do not copy enterprise information into a personal or Extra repository unless it was explicitly reviewed and approved.
- The declared Copilot account is an intended context. VS Code authentication must still be confirmed by the user.
"@
    Set-Content -LiteralPath (Join-Path $target '.github\copilot-instructions.md') -Value $instructions -Encoding utf8

    $readme = @"
# $safeName

Created by DevContext $script:AppVersion.

- Context: $selectedModel
- Repository mode: $mode
- Repository identity: $($model.RepositoryIdentity)
- GitHub: $($repositoryIdentity.git.githubAccount)
- Intended Copilot: $($model.CopilotIdentity) / $($copilotIdentity.copilot.account)

Run `Start-Dev.ps1` to validate and open the workspace.
"@
    Set-Content -LiteralPath (Join-Path $target 'README.md') -Value $readme -Encoding utf8

    $gitignore = @'
.vscode/*.log
*.log
Temp/
.local/
.env
.env.*
'@
    Set-Content -LiteralPath (Join-Path $target '.gitignore') -Value $gitignore -Encoding utf8

    $startDev = @"
#requires -Version 7.0
`$ErrorActionPreference = 'Stop'
`$root = `$PSScriptRoot
`$context = Get-Content (Join-Path `$root '.project-context.json') -Raw | ConvertFrom-Json
Write-Host "Project....... `$(`$context.projectName)" -ForegroundColor Cyan
Write-Host "Context....... `$(`$context.contextModel)"
Write-Host "GitHub........ `$(`$context.repository.gitHubAccount)"
Write-Host "Copilot....... `$(`$context.copilot.account)"
Write-Host "M365 Copilot.. `$(`$context.microsoft365Copilot.enabled)"
Write-Host "IMPORTANT: Confirm the active GitHub Copilot account in VS Code before sending project content." -ForegroundColor Yellow
`$workspace = Join-Path `$root '$safeName.code-workspace'
& code `$workspace
"@
    Set-Content -LiteralPath (Join-Path $target 'Start-Dev.ps1') -Value $startDev -Encoding utf8

    if ($mode -eq 'Standalone') {
        Push-Location $target
        try {
            & git init | Out-Null
            & git config --local user.name $repositoryIdentity.git.userName
            & git config --local user.email $repositoryIdentity.git.userEmail
            & git add .
        }
        finally {
            Pop-Location
        }
    }
    else {
        $repoRoot = $roots.SelectedProjectRoot
        $repoGitName = Get-NativeText { git -C $repoRoot config --get user.name }
        $repoGitEmail = Get-NativeText { git -C $repoRoot config --get user.email }
        if ($repoGitName -and $repoGitName -ne $repositoryIdentity.git.userName) {
            Write-Warning "O monorepo usa user.name '$repoGitName', diferente de '$($repositoryIdentity.git.userName)'. Nenhuma configuracao Git foi alterada."
        }
        if ($repoGitEmail -and $repoGitEmail -ne $repositoryIdentity.git.userEmail) {
            Write-Warning "O monorepo usa user.email '$repoGitEmail', diferente de '$($repositoryIdentity.git.userEmail)'. Nenhuma configuracao Git foi alterada."
        }
    }

    Write-Host ''
    Write-Host 'Projeto criado com sucesso.' -ForegroundColor Green
    Write-Host "Path........... $target"
    Write-Host "Context........ $selectedModel"
    Write-Host "Repository..... $($repositoryIdentity.git.githubAccount)"
    Write-Host "Copilot........ $($copilotIdentity.copilot.account)"
    Write-Host "Workspace...... $workspacePath"
    Write-Host 'Nenhum repositorio remoto foi criado e nenhuma conta Copilot foi trocada automaticamente.' -ForegroundColor Yellow
}

Initialize-DevContextStorage
switch($Command){doctor{Invoke-DevDoctor}status{Invoke-DevDoctor}identities{Show-Identities }config{Get-Content $script:ConfigFile -Raw}identity-setup{Invoke-IdentitySetup}identity-test{Invoke-IdentityTest}identity-verify{Invoke-IdentityVerify}new{New-DevProject}}
