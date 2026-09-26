#Requires -Version 5.1
<#
.SYNOPSIS
    SysInternals Frontend - navegador visual para a suite SysInternals da Microsoft.

.DESCRIPTION
    Interface em modo texto (TUI) que lista as ferramentas SysInternals separadas por
    categorias, mostra um resumo do que cada uma faz e os parametros de linha de comando,
    permite executar a ferramenta, abrir os arquivos de ajuda locais (.chm/.txt) ou a
    documentacao online, instalar/atualizar a suite e configurar o diretorio de instalacao.

    O catalogo de descricoes e atualizado periodicamente a partir da documentacao oficial
    (MicrosoftDocs/sysinternals) e fica em cache local.

.EXAMPLE
    .\SysInternals-Frontend.ps1
    Abre o menu interativo.

.EXAMPLE
    .\SysInternals-Frontend.ps1 --Help procexp
    Mostra o resumo e os parametros do Process Explorer.

.EXAMPLE
    .\SysInternals-Frontend.ps1 --Run handle -a notepad.exe
    Executa o handle.exe com os argumentos informados.
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CmdArgs
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ==============================================================================
#  Constantes / Caminhos
# ==============================================================================
$script:AppName   = 'SysInternals Frontend'
$script:Version   = '1.0'
$script:CacheDir  = Join-Path $env:APPDATA 'SysInternalsFrontend'
$script:CfgPath   = Join-Path $script:CacheDir 'config.json'
$script:CatPath   = Join-Path $script:CacheDir 'catalog.json'
$script:UsageDir  = Join-Path $script:CacheDir 'usage'

$script:Defaults = @{
    InstallDirectory  = 'C:\dos\SysInternals'
    DownloadUrl       = 'https://download.sysinternals.com/files/SysinternalsSuite.zip'
    DocsIndexUrl      = 'https://raw.githubusercontent.com/MicrosoftDocs/sysinternals/live/sysinternals/downloads/index.md'
    DocsBaseUrl       = 'https://learn.microsoft.com/en-us/sysinternals/downloads/'
    CatalogMaxAgeDays = 7
}

# Box drawing (sem acentos no codigo; caracteres via codigo Unicode)
$B = @{
    TL = [string][char]0x2554; TR = [string][char]0x2557
    BL = [string][char]0x255A; BR = [string][char]0x255D
    HZ = [string][char]0x2550; VT = [string][char]0x2551
    ML = [string][char]0x2560; MR = [string][char]0x2563
    TT = [string][char]0x2566; BT = [string][char]0x2569
    XX = [string][char]0x256C
    LV = [string][char]0x2502; LH = [string][char]0x2500
    AR = [string][char]0x25BA; UP = [string][char]0x25B2; DN = [string][char]0x25BC
    FULL = [string][char]0x2588; LIGHT = [string][char]0x2591
}

# Paleta estilo Turbo Vision / Norton Commander (MS-DOS)
# Atencao: PowerShell nao diferencia maiusculas, entao nunca use $t como variavel local.
$T = @{
    DeskBg    = 'DarkBlue'; DeskFg   = 'Blue'
    MenuBg    = 'Gray';     MenuFg   = 'Black'
    WinBg     = 'DarkBlue'; WinFg    = 'White';  WinBorder = 'Cyan'
    TitleBg   = 'Cyan';     TitleFg  = 'Black'
    SelBg     = 'Cyan';     SelFg    = 'Black'
    DimFg     = 'Gray';     AccentFg = 'Yellow'
    OkFg      = 'Green';    WarnFg   = 'DarkYellow'; ErrFg = 'Red'
    DlgBg     = 'Gray';     DlgFg    = 'Black';  DlgBorder = 'White'
    BtnBg     = 'DarkGreen';BtnFg    = 'White'
    KeyNumBg  = 'Black';    KeyNumFg = 'Gray'
    KeyLblBg  = 'DarkCyan'; KeyLblFg = 'Black'
}
$script:CurBg = 'DarkBlue'
$script:CurFg = 'White'
$script:ShellX = 0
$script:ShellY = 0

# ==============================================================================
#  Catalogo base (categorias + descricoes em portugues + nome do executavel)
# ==============================================================================
$script:Categories = @(
    'Processos', 'Arquivos e Disco', 'Rede', 'Seguranca',
    'Informacoes do Sistema', 'PsTools', 'Active Directory', 'Diversos'
)

$script:BaseCatalog = @(
    # ---- Processos ----
    @{S='process-explorer'; N='Process Explorer'; E='procexp64.exe,procexp.exe'; C='Processos'; G=$true;  D='Gerenciador de tarefas avancado: mostra arquivos, chaves de registro, DLLs e handles abertos por cada processo.'}
    @{S='procmon';        N='Process Monitor';  E='Procmon64.exe,Procmon.exe'; C='Processos'; G=$true;  D='Monitora em tempo real atividade de sistema de arquivos, registro, processos, threads e DLLs.'}
    @{S='procdump';       N='ProcDump';         E='procdump64.exe,procdump.exe'; C='Processos'; G=$false; D='Captura dumps de processos por pico de CPU, excecao, travamento de janela ou sob demanda.'}
    @{S='handle';         N='Handle';           E='handle64.exe,handle.exe';  C='Processos'; G=$false; D='Lista quais arquivos e objetos estao abertos por quais processos (versao console do Process Explorer).'}
    @{S='listdlls';       N='ListDLLs';         E='Listdlls64.exe,Listdlls.exe'; C='Processos'; G=$false; D='Lista todas as DLLs carregadas, onde foram carregadas e suas versoes.'}
    @{S='vmmap';          N='VMMap';            E='vmmap64.exe,vmmap.exe';    C='Processos'; G=$true;  D='Analisa a memoria virtual e fisica usada por um processo, detalhando cada tipo de alocacao.'}
    @{S='pssuspend';      N='PsSuspend';        E='pssuspend64.exe,pssuspend.exe'; C='Processos'; G=$false; D='Suspende e retoma processos locais ou remotos sem encerra-los.'}
    @{S='autoruns';       N='Autoruns';         E='Autoruns64.exe,Autoruns.exe'; C='Processos'; G=$true;  D='Mostra tudo que e configurado para iniciar automaticamente com o Windows ou o logon.'}
    @{S='autoruns';       N='AutorunsC';        E='autorunsc64.exe,autorunsc.exe'; C='Processos'; G=$false; D='Versao de linha de comando do Autoruns, ideal para relatorios em CSV/XML.'}
    @{S='shellrunas';     N='ShellRunas';       E='ShellRunas.exe';           C='Processos'; G=$false; D='Adiciona item de menu de contexto para executar programas como outro usuario.'}
    @{S='sysmon';         N='Sysmon';           E='Sysmon64.exe,Sysmon.exe';  C='Processos'; G=$false; D='Servico que registra criacao de processos, conexoes de rede e alteracoes de arquivos no log de eventos.'}

    # ---- Arquivos e Disco ----
    @{S='contig';         N='Contig';           E='Contig64.exe,Contig.exe';  C='Arquivos e Disco'; G=$false; D='Desfragmenta arquivos individuais ou cria arquivos contiguos.'}
    @{S='disk2vhd';       N='Disk2vhd';         E='disk2vhd64.exe,disk2vhd.exe'; C='Arquivos e Disco'; G=$true;  D='Converte discos fisicos em arquivos VHD/VHDX para virtualizacao (P2V).'}
    @{S='diskext';        N='DiskExt';          E='diskext64.exe,diskext.exe';C='Arquivos e Disco'; G=$false; D='Exibe o mapeamento de volumes para discos fisicos.'}
    @{S='diskmon';        N='DiskMon';          E='Diskmon64.exe,Diskmon.exe';C='Arquivos e Disco'; G=$true;  D='Captura toda a atividade de disco rigido ou funciona como um LED de atividade na bandeja.'}
    @{S='diskview';       N='DiskView';         E='DiskView64.exe,DiskView.exe'; C='Arquivos e Disco'; G=$true;  D='Mapa grafico dos setores do disco mostrando onde cada arquivo esta alocado.'}
    @{S='du';             N='Disk Usage (DU)';  E='du64.exe,du.exe';          C='Arquivos e Disco'; G=$false; D='Mostra o uso de disco por diretorio, com saida em texto ou CSV.'}
    @{S='efsdump';        N='EFSDump';          E='efsdump.exe';              C='Arquivos e Disco'; G=$false; D='Exibe informacoes sobre arquivos criptografados com EFS.'}
    @{S='findlinks';      N='FindLinks';        E='FindLinks64.exe,FindLinks.exe'; C='Arquivos e Disco'; G=$false; D='Lista o indice do arquivo e todos os hard links existentes para ele.'}
    @{S='junction';       N='Junction';         E='junction64.exe,junction.exe'; C='Arquivos e Disco'; G=$false; D='Cria, lista e remove junctions (links simbolicos de diretorio) NTFS.'}
    @{S='ldmdump';        N='LDMDump';          E='ldmdump.exe';              C='Arquivos e Disco'; G=$false; D='Despeja o banco de dados do Logical Disk Manager (discos dinamicos).'}
    @{S='ntfsinfo';       N='NTFSInfo';         E='ntfsinfo64.exe,ntfsinfo.exe'; C='Arquivos e Disco'; G=$false; D='Mostra detalhes de volumes NTFS, incluindo tamanho e posicao da MFT.'}
    @{S='pendmoves';      N='PendMoves';        E='pendmoves64.exe,pendmoves.exe'; C='Arquivos e Disco'; G=$false; D='Lista operacoes de renomear/excluir arquivos agendadas para o proximo boot.'}
    @{S='pendmoves';      N='MoveFile';         E='movefile64.exe,movefile.exe'; C='Arquivos e Disco'; G=$false; D='Agenda mover ou excluir arquivos na proxima reinicializacao.'}
    @{S='sdelete';        N='SDelete';          E='sdelete64.exe,sdelete.exe';C='Arquivos e Disco'; G=$false; D='Apaga arquivos com sobrescrita segura (padrao DoD) e limpa o espaco livre.'}
    @{S='streams';        N='Streams';          E='streams64.exe,streams.exe';C='Arquivos e Disco'; G=$false; D='Revela e remove fluxos de dados alternativos (ADS) do NTFS.'}
    @{S='sync';           N='Sync';             E='sync64.exe,sync.exe';      C='Arquivos e Disco'; G=$false; D='Descarrega os dados em cache para o disco antes de remover a midia.'}
    @{S='volumeid';       N='VolumeId';         E='Volumeid64.exe,Volumeid.exe'; C='Arquivos e Disco'; G=$false; D='Altera o numero de serie (Volume ID) de unidades FAT ou NTFS.'}
    @{S='cacheset';       N='CacheSet';         E='Cacheset.exe';             C='Arquivos e Disco'; G=$true;  D='Permite controlar o tamanho do working set do Cache Manager do Windows.'}

    # ---- Rede ----
    @{S='tcpview';        N='TCPView';          E='tcpview64.exe,tcpview.exe';C='Rede'; G=$true;  D='Mostra em tempo real todas as conexoes TCP/UDP e quais processos as mantem.'}
    @{S='tcpview';        N='TCPVCon';          E='tcpvcon64.exe,tcpvcon.exe';C='Rede'; G=$false; D='Versao console do TCPView, util para scripts e relatorios.'}
    @{S='psping';         N='PsPing';           E='psping64.exe,psping.exe';  C='Rede'; G=$false; D='Mede latencia e largura de banda com ping ICMP, TCP, UDP e testes de banda.'}
    @{S='whois';          N='Whois';            E='whois64.exe,whois.exe';    C='Rede'; G=$false; D='Consulta o registro whois de dominios e enderecos IP.'}
    @{S='shareenum';      N='ShareEnum';        E='ShareEnum.exe';            C='Rede'; G=$true;  D='Varre compartilhamentos de rede e exibe suas permissoes de seguranca.'}
    @{S='pipelist';       N='PipeList';         E='pipelist64.exe,pipelist.exe'; C='Rede'; G=$false; D='Lista os named pipes do sistema e suas instancias maximas e ativas.'}
    @{S='portmon';        N='PortMon';          E='portmon.exe';              C='Rede'; G=$true;  D='Monitora atividade de portas seriais e paralelas.'}
    @{S='psfile';         N='PsFile';           E='psfile64.exe,psfile.exe';  C='Rede'; G=$false; D='Mostra quais arquivos estao abertos remotamente em um sistema.'}

    # ---- Seguranca ----
    @{S='accesschk';      N='AccessChk';        E='accesschk64.exe,accesschk.exe'; C='Seguranca'; G=$false; D='Exibe as permissoes efetivas de arquivos, registro, servicos, processos e objetos do kernel.'}
    @{S='accessenum';     N='AccessEnum';       E='AccessEnum.exe';           C='Seguranca'; G=$true;  D='Mostra quem tem acesso a diretorios, arquivos e chaves de registro, revelando brechas.'}
    @{S='autologon';      N='Autologon';        E='Autologon64.exe,Autologon.exe'; C='Seguranca'; G=$true;  D='Configura logon automatico do Windows armazenando a senha de forma criptografada.'}
    @{S='logonsessions';  N='LogonSessions';    E='logonsessions64.exe,logonsessions.exe'; C='Seguranca'; G=$false; D='Lista as sessoes de logon ativas no sistema e os processos de cada uma.'}
    @{S='sigcheck';       N='Sigcheck';         E='sigcheck64.exe,sigcheck.exe'; C='Seguranca'; G=$false; D='Verifica assinaturas digitais, versao de arquivos e consulta o VirusTotal.'}
    @{S='psloggedon';     N='PsLoggedOn';       E='PsLoggedon64.exe,PsLoggedon.exe'; C='Seguranca'; G=$false; D='Mostra os usuarios conectados localmente e por compartilhamento de rede.'}
    @{S='regdelnull';     N='RegDelNull';       E='regdelnull64.exe,regdelnull.exe'; C='Seguranca'; G=$false; D='Localiza e remove chaves de registro com caracteres nulos, invisiveis ao regedit.'}

    # ---- Informacoes do Sistema ----
    @{S='clockres';       N='ClockRes';         E='clockres64.exe,clockres.exe'; C='Informacoes do Sistema'; G=$false; D='Mostra a resolucao do relogio do sistema (resolucao maxima do timer).'}
    @{S='coreinfo';       N='Coreinfo';         E='Coreinfo64.exe,Coreinfo.exe'; C='Informacoes do Sistema'; G=$false; D='Exibe o mapeamento entre processadores logicos, fisicos, nos NUMA, sockets e caches.'}
    @{S='livekd';         N='LiveKd';           E='livekd64.exe,livekd.exe';  C='Informacoes do Sistema'; G=$false; D='Permite usar os depuradores de kernel da Microsoft em um sistema em execucao.'}
    @{S='loadorder';      N='LoadOrder';        E='LoadOrd64.exe,LoadOrd.exe';C='Informacoes do Sistema'; G=$true;  D='Mostra a ordem em que os drivers de dispositivo sao carregados no boot.'}
    @{S='rammap';         N='RAMMap';           E='RAMMap64.exe,RAMMap.exe';  C='Informacoes do Sistema'; G=$true;  D='Analise avancada do uso de memoria fisica, com varias visoes por tipo de pagina.'}
    @{S='winobj';         N='WinObj';           E='Winobj64.exe,Winobj.exe';  C='Informacoes do Sistema'; G=$true;  D='Navegador do namespace do Object Manager do Windows.'}
    @{S='ru';             N='Registry Usage';   E='ru64.exe,ru.exe';          C='Informacoes do Sistema'; G=$false; D='Mostra o espaco ocupado por uma chave de registro e suas subchaves.'}
    @{S='hex2dec';        N='Hex2Dec';          E='hex2dec64.exe,hex2dec.exe';C='Informacoes do Sistema'; G=$false; D='Converte numeros hexadecimais para decimal e vice-versa.'}

    # ---- PsTools ----
    @{S='psexec';         N='PsExec';           E='PsExec64.exe,PsExec.exe';  C='PsTools'; G=$false; D='Executa processos em sistemas remotos com redirecionamento interativo de console.'}
    @{S='psinfo';         N='PsInfo';           E='PsInfo64.exe,PsInfo.exe';  C='PsTools'; G=$false; D='Coleta informacoes de sistema local ou remoto (versao, uptime, discos, hotfixes).'}
    @{S='pslist';         N='PsList';           E='pslist64.exe,pslist.exe';  C='PsTools'; G=$false; D='Lista processos e threads com estatisticas de CPU e memoria.'}
    @{S='pskill';         N='PsKill';           E='pskill64.exe,pskill.exe';  C='PsTools'; G=$false; D='Encerra processos locais ou remotos por nome ou PID.'}
    @{S='psservice';      N='PsService';        E='PsService64.exe,PsService.exe'; C='PsTools'; G=$false; D='Consulta, configura, inicia e para servicos locais ou remotos.'}
    @{S='psloglist';      N='PsLogList';        E='psloglist64.exe,psloglist.exe'; C='PsTools'; G=$false; D='Despeja registros de log de eventos locais ou remotos.'}
    @{S='pspasswd';       N='PsPasswd';         E='pspasswd64.exe,pspasswd.exe'; C='PsTools'; G=$false; D='Altera senhas de contas locais ou de dominio em varios sistemas.'}
    @{S='psgetsid';       N='PsGetSid';         E='PsGetsid64.exe,PsGetsid.exe'; C='PsTools'; G=$false; D='Exibe o SID de um computador ou usuario, ou traduz um SID em nome.'}
    @{S='psshutdown';     N='PsShutdown';       E='psshutdown64.exe,psshutdown.exe'; C='PsTools'; G=$false; D='Desliga, reinicia, hiberna ou faz logoff em maquinas locais e remotas.'}

    # ---- Active Directory ----
    @{S='adexplorer';     N='AdExplorer';       E='ADExplorer64.exe,ADExplorer.exe'; C='Active Directory'; G=$true;  D='Visualizador e editor avancado do Active Directory, com snapshots comparaveis.'}
    @{S='adinsight';      N='AdInsight';        E='ADInsight64.exe,ADInsight.exe'; C='Active Directory'; G=$true;  D='Monitor LDAP em tempo real para diagnosticar aplicacoes cliente do Active Directory.'}
    @{S='adrestore';      N='AdRestore';        E='adrestore64.exe,adrestore.exe'; C='Active Directory'; G=$false; D='Lista e restaura objetos excluidos (tombstoned) do Active Directory.'}

    # ---- Diversos ----
    @{S='bginfo';         N='BgInfo';           E='Bginfo64.exe,Bginfo.exe';  C='Diversos'; G=$true;  D='Gera papel de parede com informacoes do sistema (IP, nome, memoria, etc.).'}
    @{S='bluescreen';     N='BlueScreen';       E='sysinternalsbluescreen64.scr,Bluescreen.scr'; C='Diversos'; G=$true; D='Protetor de tela que simula telas azuis e reinicializacoes.'}
    @{S='ctrl2cap';       N='Ctrl2Cap';         E='ctrl2cap.exe';             C='Diversos'; G=$false; D='Driver que remapeia a tecla Caps Lock para Ctrl.'}
    @{S='debugview';      N='DebugView';        E='Dbgview64.exe,Dbgview.exe';C='Diversos'; G=$true;  D='Captura saidas de DbgPrint e OutputDebugString locais ou remotas.'}
    @{S='desktops';       N='Desktops';         E='Desktops64.exe,Desktops.exe'; C='Diversos'; G=$true;  D='Cria ate quatro desktops virtuais com troca por atalho ou bandeja.'}
    @{S='notmyfault';     N='NotMyFault';       E='notmyfault64.exe,notmyfault.exe'; C='Diversos'; G=$true;  D='Provoca travamentos, hangs e vazamentos de memoria de kernel para testes.'}
    @{S='rdcman';         N='RDCMan';           E='RDCMan.exe';               C='Diversos'; G=$true;  D='Gerencia multiplas conexoes de area de trabalho remota em um unico painel.'}
    @{S='regjump';        N='RegJump';          E='regjump.exe';              C='Diversos'; G=$false; D='Abre o Regedit diretamente no caminho de registro informado.'}
    @{S='strings';        N='Strings';          E='strings64.exe,strings.exe';C='Diversos'; G=$false; D='Procura cadeias ANSI e Unicode dentro de arquivos binarios.'}
    @{S='zoomit';         N='ZoomIt';           E='ZoomIt64.exe,ZoomIt.exe';  C='Diversos'; G=$true;  D='Utilitario de apresentacao para zoom, desenho na tela e temporizador.'}
)

# ==============================================================================
#  Configuracao
# ==============================================================================
function Get-AppConfig {
    $cfg = @{}
    foreach ($k in $script:Defaults.Keys) { $cfg[$k] = $script:Defaults[$k] }
    if (Test-Path $script:CfgPath) {
        try {
            $j = Get-Content $script:CfgPath -Raw | ConvertFrom-Json
            foreach ($k in @($cfg.Keys)) {
                if ($null -ne $j.$k -and "$($j.$k)" -ne '') { $cfg[$k] = $j.$k }
            }
        } catch { }
    }
    return $cfg
}

function Save-AppConfig ($Cfg) {
    if (-not (Test-Path $script:CacheDir)) { New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null }
    [PSCustomObject]$Cfg | ConvertTo-Json | Set-Content $script:CfgPath -Encoding UTF8
}

# ==============================================================================
#  Catalogo: base + atualizacao pela documentacao oficial
# ==============================================================================
function Get-DocsCache {
    if (Test-Path $script:CatPath) {
        try { return (Get-Content $script:CatPath -Raw | ConvertFrom-Json) } catch { }
    }
    return $null
}

function Update-DocsCache ($Cfg, [switch]$Quiet) {
    try {
        $old = [Net.ServicePointManager]::SecurityProtocol
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $md = (Invoke-WebRequest -Uri $Cfg.DocsIndexUrl -UseBasicParsing -TimeoutSec 25).Content
        [Net.ServicePointManager]::SecurityProtocol = $old
    } catch {
        if (-not $Quiet) { Write-Host "Falha ao atualizar o catalogo: $($_.Exception.Message)" -ForegroundColor Red }
        return $null
    }

    $items = @{}
    $rx = [regex]'(?m)^\[(?<name>[^\]]+)\]\((?<slug>[a-z0-9\-]+)\.md\)\s*\r?\n\*(?<ver>[^*]*)\*\s*\r?\n(?<desc>(?:.+\r?\n)+?)\s*\r?\n'
    foreach ($m in $rx.Matches($md + "`n`n")) {
        $slug = $m.Groups['slug'].Value
        $desc = ($m.Groups['desc'].Value -replace '\s+', ' ').Trim()
        if (-not $items.ContainsKey($slug)) {
            $items[$slug] = [PSCustomObject]@{
                Slug    = $slug
                Name    = $m.Groups['name'].Value.Trim()
                Version = $m.Groups['ver'].Value.Trim()
                Desc    = $desc
            }
        }
    }
    if ($items.Count -eq 0) { return $null }

    $cache = [PSCustomObject]@{
        Updated = (Get-Date).ToString('o')
        Source  = $Cfg.DocsIndexUrl
        Items   = @($items.Values | Sort-Object Slug)
    }
    if (-not (Test-Path $script:CacheDir)) { New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null }
    $cache | ConvertTo-Json -Depth 5 | Set-Content $script:CatPath -Encoding UTF8
    return $cache
}

function Test-CatalogStale ($Cache, $Cfg) {
    if ($null -eq $Cache -or -not $Cache.Updated) { return $true }
    try { $u = [datetime]::Parse($Cache.Updated) } catch { return $true }
    return ((Get-Date) - $u).TotalDays -gt [double]$Cfg.CatalogMaxAgeDays
}

function Get-Catalog ($Cfg, [switch]$ForceUpdate) {
    $cache = Get-DocsCache
    if ($ForceUpdate -or (Test-CatalogStale $cache $Cfg)) {
        $new = Update-DocsCache $Cfg -Quiet
        if ($new) { $cache = $new }
    }
    $docs = @{}
    if ($cache) { foreach ($i in $cache.Items) { $docs[$i.Slug] = $i } }

    $tools = foreach ($bt in $script:BaseCatalog) {
        $d = $null
        if ($docs.ContainsKey($bt.S)) { $d = $docs[$bt.S] }
        [PSCustomObject]@{
            Name     = $bt.N
            Slug     = $bt.S
            Exes     = $bt.E -split ','
            Category = $bt.C
            IsGui    = [bool]$bt.G
            Desc     = $bt.D
            DocDesc  = if ($d) { $d.Desc } else { '' }
            Version  = if ($d) { $d.Version } else { '' }
            DocUrl   = $Cfg.DocsBaseUrl + $bt.S
        }
    }
    return @($tools)
}

# ==============================================================================
#  Resolucao de executaveis / ajuda
# ==============================================================================
$script:PathCache = @{}

function Resolve-ToolPath ($Tool, [string]$InstallDir) {
    $key = "$InstallDir|$($Tool.Name)"
    if ($script:PathCache.ContainsKey($key)) { return $script:PathCache[$key] }
    $found = $null
    if (Test-Path -LiteralPath $InstallDir) {
        foreach ($e in $Tool.Exes) {
            $p = Join-Path $InstallDir $e.Trim()
            if (Test-Path -LiteralPath $p) { $found = $p; break }
        }
    }
    $script:PathCache[$key] = $found
    return $found
}

function Get-ToolHelpFiles ($Tool, [string]$InstallDir) {
    if (-not (Test-Path -LiteralPath $InstallDir)) { return @() }
    $bases = foreach ($e in $Tool.Exes) { [IO.Path]::GetFileNameWithoutExtension($e.Trim()) -replace '64$', '' }
    $res = @()
    foreach ($b in ($bases | Select-Object -Unique)) {
        $res += Get-ChildItem -LiteralPath $InstallDir -File -Filter "$b*.chm" -ErrorAction SilentlyContinue
        $res += Get-ChildItem -LiteralPath $InstallDir -File -Filter "$b*.txt" -ErrorAction SilentlyContinue
    }
    return @($res | Sort-Object FullName -Unique)
}

function Set-EulaAccepted ($Tool) {
    # Evita o dialogo de licenca na primeira execucao ao capturar a ajuda.
    try {
        $names = @('') + @(foreach ($e in $Tool.Exes) { [IO.Path]::GetFileNameWithoutExtension($e.Trim()) })
        foreach ($n in ($names | Select-Object -Unique)) {
            $key = if ($n) { "HKCU:\Software\Sysinternals\$n" } else { 'HKCU:\Software\Sysinternals' }
            if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
            New-ItemProperty -Path $key -Name 'EulaAccepted' -Value 1 -PropertyType DWord -Force | Out-Null
        }
    } catch { }
}

$script:UsageMem = @{}

function Get-ToolUsage ($Tool, [string]$InstallDir, [int]$TimeoutSec = 6) {
    $key = $Tool.Name
    if ($script:UsageMem.ContainsKey($key)) { return $script:UsageMem[$key] }

    if (-not (Test-Path $script:UsageDir)) { New-Item -ItemType Directory -Path $script:UsageDir -Force | Out-Null }
    $file = Join-Path $script:UsageDir (($key -replace '[^\w\.-]', '_') + '.txt')
    if (Test-Path $file) {
        $txt = Get-Content $file -Raw
        $script:UsageMem[$key] = $txt
        return $txt
    }

    $exe = Resolve-ToolPath $Tool $InstallDir
    if (-not $exe) { return $null }
    if ($Tool.IsGui) { return $null }

    Set-EulaAccepted $Tool
    $out = Join-Path $env:TEMP ('sif_out_' + [guid]::NewGuid().ToString('N') + '.txt')
    $err = Join-Path $env:TEMP ('sif_err_' + [guid]::NewGuid().ToString('N') + '.txt')
    $text = $null
    try {
        $p = Start-Process -FilePath $exe -ArgumentList '-?', '-nobanner', '-accepteula' `
             -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch { }
        }
        $text = ''
        foreach ($f in @($out, $err)) {
            if (Test-Path $f) {
                $c = Get-Content $f -Raw -ErrorAction SilentlyContinue
                if ($c) { $text += $c }
            }
        }
    } catch {
        $text = $null
    } finally {
        Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    }

    if ($text) {
        $text = ($text -replace "`r`n", "`n").Trim()
        Set-Content -LiteralPath $file -Value $text -Encoding UTF8
    }
    $script:UsageMem[$key] = $text
    return $text
}

# ==============================================================================
#  Primitivas de UI
# ==============================================================================
function Get-UiSize {
    $w = 100; $h = 30
    try { $w = [Math]::Min([Console]::WindowWidth - 1, 160) } catch { }
    try { $h = [Math]::Min([Console]::WindowHeight, 60) } catch { }
    if ($w -lt 60) { $w = 60 }
    if ($h -lt 20) { $h = 20 }
    return @{ W = $w; H = $h }
}

function W ([int]$X, [int]$Y, [string]$Text, [string]$Fg = '', [string]$Bg = '') {
    if ($null -eq $Text) { return }
    if (-not $Fg -or -not [enum]::IsDefined([ConsoleColor], $Fg)) { $Fg = $script:CurFg }
    if (-not $Bg -or -not [enum]::IsDefined([ConsoleColor], $Bg)) { $Bg = $script:CurBg }
    try {
        $max = [Console]::WindowWidth - $X - 1
        if ($max -le 0) { return }
        if ($Text.Length -gt $max) { $Text = $Text.Substring(0, $max) }
        [Console]::SetCursorPosition($X, $Y)
        [Console]::ForegroundColor = $Fg
        [Console]::BackgroundColor = $Bg
        [Console]::Write($Text)
    } catch { }
}

function Clear-Row ([int]$Y, [int]$X, [int]$Len) { W $X $Y (' ' * $Len) }

# Escrita relativa a janela criada por Draw-Shell
function WW ([int]$X, [int]$Y, [string]$Text, [string]$Fg = '', [string]$Bg = '') {
    W ($script:ShellX + $X) ($script:ShellY + $Y) $Text $Fg $Bg
}

function Clear-WRow ([int]$Y, [int]$X, [int]$Len) { WW $X $Y (' ' * $Len) }

function Split-Wrap ([string]$Text, [int]$Width) {
    if (-not $Text) { return @() }
    $lines = @()
    foreach ($para in ($Text -split "`n")) {
        $cur = ''
        foreach ($word in ($para -split ' ')) {
            if ($word -eq '') { continue }
            if (($cur.Length + $word.Length + 1) -gt $Width) {
                if ($cur) { $lines += $cur }
                while ($word.Length -gt $Width) {
                    $lines += $word.Substring(0, $Width); $word = $word.Substring($Width)
                }
                $cur = $word
            } else {
                $cur = if ($cur) { "$cur $word" } else { $word }
            }
        }
        $lines += $cur
    }
    return @($lines)
}

function Format-Bytes ([long]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Draw-Bar ([int]$X, [int]$Y, [int]$Width, [int]$Pct, [string]$Color = 'Cyan') {
    $p = [Math]::Max(0, [Math]::Min(100, $Pct))
    $f = [int]($Width * $p / 100)
    W $X $Y ($B.FULL * $f) $Color
    if ($Width - $f -gt 0) { W ($X + $f) $Y ($B.LIGHT * ($Width - $f)) 'DarkGray' }
}

# --- Desktop / janelas no estilo Turbo Vision (MS-DOS) -------------------------
function Draw-Desktop ([string]$MenuText = '', [string]$RightText = '') {
    $cw = [Console]::WindowWidth - 1
    $ch = [Console]::WindowHeight
    [Console]::CursorVisible = $false
    $row = $B.LIGHT * $cw
    for ($y = 0; $y -lt $ch; $y++) { W 0 $y $row $T.DeskFg $T.DeskBg }
    if ($MenuText -ne $null) {
        W 0 0 (' ' * $cw) $T.MenuFg $T.MenuBg
        if ($MenuText) { W 1 0 $MenuText $T.MenuFg $T.MenuBg }
        if ($RightText) { W ([Math]::Max(1, $cw - $RightText.Length - 1)) 0 $RightText $T.MenuFg $T.MenuBg }
    }
}

function Draw-Shadow ([int]$X, [int]$Y, [int]$Wd, [int]$Ht) {
    for ($r = 1; $r -lt $Ht; $r++) { W ($X + $Wd) ($Y + $r) '  ' 'DarkGray' 'Black' }
    W ($X + 2) ($Y + $Ht) (' ' * $Wd) 'DarkGray' 'Black'
}

function Draw-Window ([int]$X, [int]$Y, [int]$Wd, [int]$Ht, [string]$Title, [string]$Bg = '', [string]$Border = '', [string]$Fg = '') {
    if (-not $Bg) { $Bg = $T.WinBg }
    if (-not $Border) { $Border = $T.WinBorder }
    if (-not $Fg) { $Fg = $T.WinFg }
    $script:CurBg = $Bg
    $script:CurFg = $Fg
    $iw = $Wd - 2
    W $X $Y ($B.TL + ($B.HZ * $iw) + $B.TR) $Border $Bg
    for ($r = 1; $r -lt ($Ht - 1); $r++) {
        W $X ($Y + $r) ($B.VT + (' ' * $iw) + $B.VT) $Border $Bg
    }
    W $X ($Y + $Ht - 1) ($B.BL + ($B.HZ * $iw) + $B.BR) $Border $Bg
    if ($Title) {
        $tt = " $Title "
        W ($X + [int](($Wd - $tt.Length) / 2)) $Y $tt $T.TitleFg $T.TitleBg
    }
    Draw-Shadow $X $Y $Wd $Ht
}

function Draw-Frame ([int]$X, [int]$Y, [int]$Wd, [int]$Ht, [string]$Title, [string]$Border = '') {
    if (-not $Border) { $Border = 'DarkCyan' }
    $iw = $Wd - 2
    W $X $Y ([string][char]0x250C + ([string][char]0x2500 * $iw) + [string][char]0x2510) $Border
    for ($r = 1; $r -lt ($Ht - 1); $r++) {
        W $X ($Y + $r) $B.LV $Border
        W ($X + $Wd - 1) ($Y + $r) $B.LV $Border
    }
    W $X ($Y + $Ht - 1) ([string][char]0x2514 + ([string][char]0x2500 * $iw) + [string][char]0x2518) $Border
    if ($Title) { W ($X + 2) $Y (" $Title ") $T.AccentFg }
}

function Draw-FKeys ($Keys) {
    $cw = [Console]::WindowWidth - 1
    $y = [Console]::WindowHeight - 1
    W 0 $y (' ' * $cw) $T.KeyLblFg $T.KeyLblBg
    $x = 0
    foreach ($k in $Keys) {
        $num = $k.K
        $lbl = $k.L
        if (($x + $num.Length + $lbl.Length + 1) -ge $cw) { break }
        W $x $y $num $T.KeyNumFg $T.KeyNumBg
        W ($x + $num.Length) $y $lbl $T.KeyLblFg $T.KeyLblBg
        $x += $num.Length + $lbl.Length + 1
    }
}

function Show-MessageBox ([string]$Title, [string[]]$Lines, [string]$Accent = '', [switch]$NoWait) {
    if (-not $Accent) { $Accent = $T.DlgFg }
    $cw = [Console]::WindowWidth - 1
    $ch = [Console]::WindowHeight
    $wide = 4
    foreach ($l in $Lines) { if ($l.Length -gt $wide) { $wide = $l.Length } }
    $wd = [Math]::Min($cw - 6, [Math]::Max($wide + 6, $Title.Length + 8))
    $ht = $Lines.Count + 6
    $x = [int](($cw - $wd) / 2)
    $y = [int](($ch - $ht) / 2)
    $obg = $script:CurBg; $ofg = $script:CurFg
    Draw-Window $x $y $wd $ht $Title $T.DlgBg $T.DlgBorder $T.DlgFg
    $r = $y + 2
    foreach ($l in $Lines) { W ($x + 3) $r $l $Accent $T.DlgBg; $r++ }
    if (-not $NoWait) {
        $btn = '[ OK ]'
        W ($x + [int](($wd - $btn.Length) / 2)) ($y + $ht - 2) $btn $T.BtnFg $T.BtnBg
        [Console]::ReadKey($true) | Out-Null
    }
    $script:CurBg = $obg; $script:CurFg = $ofg
}

function Show-InputBox ([string]$Title, [string]$Prompt, [string]$Default) {
    $cw = [Console]::WindowWidth - 1
    $ch = [Console]::WindowHeight
    $wd = [Math]::Min($cw - 6, 74)
    $ht = 9
    $x = [int](($cw - $wd) / 2)
    $y = [int](($ch - $ht) / 2)
    $obg = $script:CurBg; $ofg = $script:CurFg
    Draw-Window $x $y $wd $ht $Title $T.DlgBg $T.DlgBorder $T.DlgFg
    W ($x + 3) ($y + 2) $Prompt $T.DlgFg $T.DlgBg
    $cur = $Default
    if ($cur.Length -gt ($wd - 8)) { $cur = '...' + $cur.Substring($cur.Length - ($wd - 11)) }
    W ($x + 3) ($y + 3) ("Atual: $cur") 'DarkBlue' $T.DlgBg
    W ($x + 3) ($y + 5) ((' ' * ($wd - 6))) 'White' 'DarkBlue'
    W ($x + 3) ($y + 6) 'ENTER mantem o valor atual' 'DarkBlue' $T.DlgBg

    [Console]::SetCursorPosition($x + 4, $y + 5)
    $pf = [Console]::ForegroundColor; $pb = [Console]::BackgroundColor
    [Console]::ForegroundColor = 'White'; [Console]::BackgroundColor = 'DarkBlue'
    [Console]::CursorVisible = $true
    $val = Read-Host
    [Console]::CursorVisible = $false
    [Console]::ForegroundColor = $pf; [Console]::BackgroundColor = $pb
    $script:CurBg = $obg; $script:CurFg = $ofg
    if ($val -and $val.Trim()) { return $val.Trim() }
    return $Default
}

function Draw-Shell ([int]$Wd, [int]$Ht, [string]$Title, [string]$Sub) {
    Draw-Desktop "  $script:AppName v$script:Version" (Get-Date -Format 'dd/MM/yyyy HH:mm')
    $x = [Math]::Max(0, [int](([Console]::WindowWidth - 1 - $Wd) / 2))
    $y = 1
    if (($y + $Ht) -ge [Console]::WindowHeight) { $Ht = [Console]::WindowHeight - $y - 1 }
    Draw-Window $x $y $Wd $Ht $Title
    $script:ShellX = $x
    $script:ShellY = $y
    if ($Sub) { W ($x + 3) ($y + 1) $Sub $T.DimFg }
}

function Draw-Rule ([int]$Y, [int]$Wd, [string]$Color = '') {
    if (-not $Color) { $Color = $T.WinBorder }
    W $script:ShellX ($script:ShellY + $Y) ($B.ML + ($B.HZ * ($Wd - 2)) + $B.MR) $Color
}

function Wait-AnyKey ([int]$Y, [int]$X = 3, [string]$Msg = 'Pressione qualquer tecla para voltar...') {
    W ($script:ShellX + $X) ($script:ShellY + $Y) $Msg $T.AccentFg
    [Console]::ReadKey($true) | Out-Null
}

# ==============================================================================
#  Download / Instalacao
# ==============================================================================
function Invoke-Install ($Cfg) {
    $ui = Get-UiSize
    $wd = [Math]::Min($ui.W, 76)
    $ht = 21
    Draw-Shell $wd $ht 'DOWNLOAD / INSTALACAO DA SUITE' 'Baixando SysinternalsSuite.zip e extraindo no diretorio configurado'
    Draw-FKeys @(@{K='   '; L=' Aguarde... '})
    Draw-Rule 2 $wd
    WW 3 3 "Origem  : $($Cfg.DownloadUrl)" $T.DimFg
    WW 3 4 "Destino : $($Cfg.InstallDirectory)" 'White'
    Draw-Rule 5 $wd

    $rowStatus = 6; $rowBar = 8; $rowDetail = 10; $rowLog = 12
    WW 3 $rowLog       '  1/3  Download   ' $T.DimFg
    WW 3 ($rowLog + 1) '  2/3  Diretorio  ' $T.DimFg
    WW 3 ($rowLog + 2) '  3/3  Extracao   ' $T.DimFg
    for ($n = 0; $n -lt 3; $n++) { WW 24 ($rowLog + $n) '[ aguardando ]' $T.DimFg }

    function Set-Status ([string]$m) { Clear-WRow $rowStatus 3 ($wd - 6); WW 3 $rowStatus $m $T.AccentFg }
    function Set-Detail ([string]$m) { Clear-WRow $rowDetail 3 ($wd - 6); WW 4 $rowDetail $m $T.DimFg }
    function Set-Bar ([int]$p) {
        Draw-Bar ($script:ShellX + 3) ($script:ShellY + $rowBar) ($wd - 16) $p
        WW ($wd - 11) $rowBar ("{0,4}%" -f $p) 'Cyan'
    }
    function Set-Log ([int]$n, [string]$s, [string]$c) {
        WW 24 ($rowLog + $n - 1) ("[ $s ]".PadRight(16)) $c
    }

    $zip = Join-Path $env:TEMP 'SysinternalsSuite.zip'

    Set-Status 'Etapa 1/3 - Baixando a suite...'
    Set-Bar 0
    $wc = $null
    $dlError = $null
    try {
        $script:_pct = 0; $script:_recv = [long]0; $script:_tot = [long]0; $script:_done = $false; $script:_err = $null
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'SysInternalsFrontend/1.0')
        Register-ObjectEvent -InputObject $wc -EventName DownloadProgressChanged -SourceIdentifier 'SIF_P' -Action {
            $script:_pct = $event.SourceEventArgs.ProgressPercentage
            $script:_recv = $event.SourceEventArgs.BytesReceived
            $script:_tot = $event.SourceEventArgs.TotalBytesToReceive
        } | Out-Null
        Register-ObjectEvent -InputObject $wc -EventName DownloadFileCompleted -SourceIdentifier 'SIF_C' -Action {
            $script:_done = $true
            if ($event.SourceEventArgs.Error) { $script:_err = $event.SourceEventArgs.Error.Message }
        } | Out-Null
        $wc.DownloadFileAsync([Uri]$Cfg.DownloadUrl, $zip)
        while (-not $script:_done) {
            Set-Bar $script:_pct
            if ($script:_tot -gt 0) {
                Set-Detail ("Recebido {0} de {1}" -f (Format-Bytes $script:_recv), (Format-Bytes $script:_tot))
            } else {
                Set-Detail ("Recebido {0}..." -f (Format-Bytes $script:_recv))
            }
            Start-Sleep -Milliseconds 150
        }
        $dlError = $script:_err
    } catch {
        $dlError = $_.Exception.Message
    } finally {
        Unregister-Event -SourceIdentifier 'SIF_P' -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier 'SIF_C' -ErrorAction SilentlyContinue
        Get-Job -Name 'SIF_*' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
        if ($wc) { $wc.Dispose() }
    }

    if ($dlError) {
        Set-Status 'Falha no download.'
        Set-Log 1 'ERRO' $T.ErrFg
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Show-MessageBox 'ERRO' @('Nao foi possivel baixar a suite:', $dlError) $T.ErrFg
        return $false
    }
    Set-Bar 100
    Set-Detail ("Arquivo baixado: {0}" -f (Format-Bytes (Get-Item $zip).Length))
    Set-Log 1 ' OK ' $T.OkFg

    Set-Status 'Etapa 2/3 - Preparando o diretorio de instalacao...'
    try {
        if (-not (Test-Path -LiteralPath $Cfg.InstallDirectory)) {
            New-Item -ItemType Directory -Path $Cfg.InstallDirectory -Force | Out-Null
        }
        Set-Log 2 ' OK ' $T.OkFg
    } catch {
        Set-Status 'Falha ao criar o diretorio.'
        Set-Log 2 'ERRO' $T.ErrFg
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Show-MessageBox 'ERRO' @('Nao foi possivel criar o diretorio:', $_.Exception.Message) $T.ErrFg
        return $false
    }

    Set-Status 'Etapa 3/3 - Extraindo arquivos...'
    Set-Bar 0
    $archive = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        $entries = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
        $total = $entries.Count; $i = 0
        $root = [IO.Path]::GetFullPath($Cfg.InstallDirectory)
        foreach ($e in $entries) {
            $i++
            $dest = [IO.Path]::GetFullPath((Join-Path $root $e.FullName))
            if (-not $dest.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { continue }  # zip slip
            $dir = Split-Path $dest -Parent
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
            Set-Bar ([int]($i * 100 / $total))
            Set-Detail "$i de $total : $($e.Name)"
        }
        $archive.Dispose(); $archive = $null
        Set-Log 3 ' OK ' $T.OkFg
    } catch {
        if ($archive) { try { $archive.Dispose() } catch { } }
        Set-Status 'Falha na extracao.'
        Set-Log 3 'ERRO' $T.ErrFg
        Show-MessageBox 'ERRO' @('Falha ao extrair o pacote:', $_.Exception.Message) $T.ErrFg
        return $false
    } finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    }

    $count = (Get-ChildItem -LiteralPath $Cfg.InstallDirectory -File -ErrorAction SilentlyContinue | Measure-Object).Count
    Set-Status 'Instalacao concluida com sucesso!'
    Show-MessageBox 'INSTALACAO CONCLUIDA' @(
        "Suite instalada em:",
        "  $($Cfg.InstallDirectory)",
        "$count arquivo(s) gravado(s)."
    ) 'DarkGreen'
    return $true
}

# ==============================================================================
#  Tela: Configuracao
# ==============================================================================
function Show-ConfigScreen ($Cfg) {
    $w = @{}
    foreach ($k in $Cfg.Keys) { $w[$k] = $Cfg[$k] }
    $ui = Get-UiSize
    $wd = [Math]::Min($ui.W, 76)
    $ht = 20

    while ($true) {
        Draw-Shell $wd $ht 'CONFIGURACAO' 'Onde a suite esta (ou sera) instalada e de onde vem o catalogo'
        Draw-FKeys @(
            @{K='F2'; L=' Salvar '}, @{K='F9'; L=' Atualizar catalogo '}, @{K='F10'; L=' Cancelar '}
        )
        Draw-Rule 2 $wd

        $rows = @(
            @{ K='1'; L='Diretorio de instalacao'; V=$w.InstallDirectory }
            @{ K='2'; L='URL do pacote (ZIP)';     V=$w.DownloadUrl }
            @{ K='3'; L='URL do indice de docs';   V=$w.DocsIndexUrl }
            @{ K='4'; L='Validade do catalogo';    V="$($w.CatalogMaxAgeDays) dia(s)" }
        )
        $fw = $wd - 12
        $y = 3
        foreach ($r in $rows) {
            WW 4 $y "[$($r.K)]" $T.AccentFg
            WW 8 $y $r.L 'White'
            $v = $r.V
            if ($v.Length -gt ($fw - 2)) { $v = $v.Substring(0, $fw - 5) + '...' }
            WW 8 ($y + 1) ((' ' + $v).PadRight($fw)) 'Black' 'Cyan'
            $y += 3
        }

        if (Test-Path -LiteralPath $w.InstallDirectory) {
            $n = (Get-ChildItem -LiteralPath $w.InstallDirectory -Filter *.exe -File -ErrorAction SilentlyContinue | Measure-Object).Count
            WW 4 $y "Diretorio existente - $n executavel(is) encontrado(s)." $T.OkFg
        } else {
            WW 4 $y 'Diretorio ainda nao existe - sera criado na instalacao.' $T.WarnFg
        }

        $cat = Get-DocsCache
        if ($cat) { WW 4 ($y + 1) ("Catalogo local: $($cat.Items.Count) ferramentas, atualizado em " + ([datetime]$cat.Updated).ToString('dd/MM/yyyy HH:mm')) $T.DimFg }
        else { WW 4 ($y + 1) 'Catalogo ainda nao baixado - pressione F9.' $T.WarnFg }

        Draw-Rule ($ht - 3) $wd
        WW 4 ($ht - 2) '[1-4] editar campo    [F2] salvar    [F9] atualizar catalogo    [F10/ESC] cancelar' $T.DimFg

        $key = [Console]::ReadKey($true)
        $ch = $key.KeyChar.ToString().ToUpper()
        if ($key.Key -eq 'F2' -or $ch -eq 'S') { Save-AppConfig $w; Show-MessageBox 'CONFIGURACAO' @('Configuracoes salvas.') 'DarkGreen'; return $w }
        if ($key.Key -eq 'F10' -or $key.Key -eq 'Escape' -or $ch -eq 'C') { return $Cfg }
        if ($key.Key -eq 'F9' -or $ch -eq 'A') {
            Show-MessageBox 'CATALOGO' @('Baixando a documentacao oficial...') 'DarkBlue' -NoWait
            $r = Update-DocsCache $w -Quiet
            if ($r) { Show-MessageBox 'CATALOGO' @("Catalogo atualizado: $($r.Items.Count) ferramentas.") 'DarkGreen' }
            else    { Show-MessageBox 'CATALOGO' @('Nao foi possivel atualizar (sem rede?).') 'DarkRed' }
            continue
        }
        switch ($ch) {
            '1' { $w.InstallDirectory = Show-InputBox 'DIRETORIO DE INSTALACAO' 'Caminho onde a suite fica instalada:' $w.InstallDirectory }
            '2' { $w.DownloadUrl      = Show-InputBox 'URL DO PACOTE ZIP'       'Endereco do SysinternalsSuite.zip:'  $w.DownloadUrl }
            '3' { $w.DocsIndexUrl     = Show-InputBox 'URL DO INDICE DE DOCS'   'Markdown com o indice das ferramentas:' $w.DocsIndexUrl }
            '4' {
                $v = Show-InputBox 'VALIDADE DO CATALOGO' 'Dias antes de buscar a documentacao novamente:' "$($w.CatalogMaxAgeDays)"
                if ($v -match '^\d+$') { $w.CatalogMaxAgeDays = [int]$v }
            }
        }
    }
}

# ==============================================================================
#  Tela: Ajuda completa de uma ferramenta
# ==============================================================================
function Show-ToolHelpScreen ($Tool, $Cfg) {
    $ui = Get-UiSize
    $exe = Resolve-ToolPath $Tool $Cfg.InstallDirectory
    $usage = if ($exe) { Get-ToolUsage $Tool $Cfg.InstallDirectory } else { $null }

    $lines = @()
    $lines += @{ T = $Tool.Desc; C = 'White' }
    if ($Tool.DocDesc) { $lines += @{ T = ''; C = $T.DimFg }; $lines += @{ T = $Tool.DocDesc; C = $T.DimFg } }
    $lines += @{ T = ''; C = $T.DimFg }
    $lines += @{ T = "Executavel  : $(if ($exe) { $exe } else { 'nao encontrado em ' + $Cfg.InstallDirectory })"; C = if ($exe) { $T.OkFg } else { $T.ErrFg } }
    $lines += @{ T = "Documentacao: $($Tool.DocUrl)"; C = 'Cyan' }
    $lines += @{ T = ''; C = $T.DimFg }
    $lines += @{ T = ('-' * 30 + ' PARAMETROS DE LINHA DE COMANDO ' + '-' * 30); C = $T.AccentFg }
    if ($usage) {
        foreach ($l in ($usage -split "`n")) { $lines += @{ T = $l.TrimEnd(); C = $T.DimFg } }
    } elseif ($Tool.IsGui) {
        $lines += @{ T = 'Ferramenta grafica: consulte a documentacao online ou o arquivo de ajuda (.chm).'; C = $T.WarnFg }
    } else {
        $lines += @{ T = 'Nao foi possivel obter a ajuda. Instale a suite ou verifique o executavel.'; C = $T.WarnFg }
    }

    $wd = $ui.W
    $ht = $ui.H - 1
    $wrapped = @()
    foreach ($l in $lines) {
        if ($l.T.Length -le ($wd - 6)) { $wrapped += $l }
        else { foreach ($s in (Split-Wrap $l.T ($wd - 6))) { $wrapped += @{ T = $s; C = $l.C } } }
    }

    $top = 0
    $view = $ht - 6
    while ($true) {
        Draw-Shell $wd $ht "AJUDA: $($Tool.Name)" ("Categoria: $($Tool.Category)" + $(if ($Tool.Version) { "   |   $($Tool.Version)" } else { '' }))
        Draw-FKeys @(
            @{K='F2'; L=' Docs '}, @{K='F3'; L=' Ajuda .chm '}, @{K='F4'; L=' Executar '}, @{K='F10'; L=' Voltar '}
        )
        Draw-Rule 2 $wd
        for ($i = 0; $i -lt $view; $i++) {
            $idx = $top + $i
            Clear-WRow (3 + $i) 2 ($wd - 4)
            if ($idx -lt $wrapped.Count) { WW 3 (3 + $i) $wrapped[$idx].T $wrapped[$idx].C }
        }
        Draw-Rule ($ht - 3) $wd
        $pos = if ($wrapped.Count -gt $view) { "linha $($top + 1)-$([Math]::Min($top + $view, $wrapped.Count)) de $($wrapped.Count)" } else { '' }
        WW 3 ($ht - 2) "$($B.UP)$($B.DN) PgUp/PgDn rolar   $pos" $T.DimFg

        $k = [Console]::ReadKey($true)
        switch ($k.Key) {
            'UpArrow'   { if ($top -gt 0) { $top-- } }
            'DownArrow' { if ($top -lt ($wrapped.Count - $view)) { $top++ } }
            'PageUp'    { $top = [Math]::Max(0, $top - $view) }
            'PageDown'  { $top = [Math]::Min([Math]::Max(0, $wrapped.Count - $view), $top + $view) }
            'Home'      { $top = 0 }
            'End'       { $top = [Math]::Max(0, $wrapped.Count - $view) }
            'Escape'    { return }
            'F2'        { Start-Process $Tool.DocUrl | Out-Null }
            'F3'        { Open-HelpFile $Tool $Cfg }
            'F4'        { Invoke-Tool $Tool $Cfg @() }
            'F10'       { return }
            default {
                switch ($k.KeyChar.ToString().ToUpper()) {
                    'D' { Start-Process $Tool.DocUrl | Out-Null }
                    'F' { Open-HelpFile $Tool $Cfg }
                    'X' { Invoke-Tool $Tool $Cfg @() }
                    'Q' { return }
                }
            }
        }
    }
}

function Open-HelpFile ($Tool, $Cfg) {
    $files = Get-ToolHelpFiles $Tool $Cfg.InstallDirectory
    if ($files.Count -eq 0) {
        Show-MessageBox 'AJUDA LOCAL' @('Nenhum arquivo .chm ou .txt encontrado', "para $($Tool.Name) em $($Cfg.InstallDirectory).") 'DarkRed'
        return
    }
    if ($files.Count -eq 1) { Start-Process $files[0].FullName | Out-Null; return }

    $cw = [Console]::WindowWidth - 1
    $ch = [Console]::WindowHeight
    $wd = [Math]::Min($cw - 6, 60)
    $ht = $files.Count + 6
    $x = [int](($cw - $wd) / 2)
    $y = [int](($ch - $ht) / 2)
    Draw-Window $x $y $wd $ht 'ARQUIVOS DE AJUDA' $T.DlgBg $T.DlgBorder $T.DlgFg
    $i = 0
    foreach ($f in $files) {
        $i++
        W ($x + 4) ($y + 1 + $i) "[$i]" 'DarkRed' $T.DlgBg
        W ($x + 8) ($y + 1 + $i) $f.Name $T.DlgFg $T.DlgBg
    }
    W ($x + 4) ($y + $ht - 2) 'Escolha o numero (ESC cancela)' 'DarkBlue' $T.DlgBg
    $k = [Console]::ReadKey($true)
    if ($k.KeyChar -match '\d') {
        $n = [int]"$($k.KeyChar)"
        if ($n -ge 1 -and $n -le $files.Count) { Start-Process $files[$n - 1].FullName | Out-Null }
    }
}

function Invoke-Tool ($Tool, $Cfg, [string[]]$Arguments) {
    $exe = Resolve-ToolPath $Tool $Cfg.InstallDirectory
    if (-not $exe) {
        Show-MessageBox 'ERRO' @("Executavel de $($Tool.Name) nao encontrado em:", "  $($Cfg.InstallDirectory)", '', 'Use F7 para instalar a suite.') 'DarkRed'
        return
    }
    Set-EulaAccepted $Tool
    if ($Tool.IsGui) {
        Start-Process -FilePath $exe -ArgumentList $Arguments | Out-Null
        return
    }
    [Console]::ResetColor()
    [Console]::Clear()
    [Console]::CursorVisible = $true
    Write-Host (("$($B.HZ)" * 70)) -ForegroundColor DarkCyan
    Write-Host (" C:\> $([IO.Path]::GetFileName($exe)) " + ($Arguments -join ' ')) -ForegroundColor Yellow
    Write-Host (("$($B.HZ)" * 70)) -ForegroundColor DarkCyan
    try {
        if ($Arguments -and $Arguments.Count -gt 0) { & $exe @Arguments } else { & $exe }
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
    Write-Host (("$($B.HZ)" * 70)) -ForegroundColor DarkCyan
    Write-Host ' Pressione qualquer tecla para voltar ao menu...' -ForegroundColor Gray
    [Console]::ReadKey($true) | Out-Null
    [Console]::CursorVisible = $false
}

function Read-Arguments ($Tool) {
    $line = Show-InputBox "ARGUMENTOS - $($Tool.Name)" 'Parametros de linha de comando (vazio = nenhum):' ''
    if (-not $line -or -not $line.Trim()) { return @() }
    return @([regex]::Matches($line, '(?:[^\s"]+|"[^"]*")+') | ForEach-Object { $_.Value.Trim('"') })
}

function Show-AboutBox {
    Show-MessageBox 'SOBRE' @(
        "$script:AppName v$script:Version",
        '',
        'Frontend em PowerShell para a suite SysInternals,',
        'no melhor estilo dos utilitarios de MS-DOS.',
        '',
        'Catalogo sincronizado com a documentacao oficial',
        'da Microsoft (MicrosoftDocs/sysinternals).',
        '',
        "Cache e configuracao: $script:CacheDir"
    ) 'DarkBlue'
}

function Show-KeysBox {
    Show-MessageBox 'TECLAS DE ATALHO' @(
        'F1  ajuda completa da ferramenta      F6  buscar',
        'F2  documentacao online               F7  instalar/atualizar suite',
        'F3  arquivo de ajuda local (.chm)     F8  configurar',
        'F4  executar com argumentos           F9  atualizar catalogo',
        'F5  executar                          F10 barra de menus',
        '',
        'setas  navegar            TAB  proxima categoria',
        'ENTER  executar           Alt+X / ESC  sair',
        'Alt+F Ferramentas   Alt+S Suite   Alt+C Catalogo   Alt+A Ajuda'
    ) 'DarkBlue'
}

# ------------------------------------------------------------------------------
#  Barra de menus (F10 ou Alt+letra)
# ------------------------------------------------------------------------------
$script:Menus = @(
    @{ T = 'Ferramentas'; H = 'F'; I = @(
        @{ L = 'Executar';                  A = 'run'    }
        @{ L = 'Executar com argumentos...'; A = 'args'   }
        @{ L = '-';                         A = ''       }
        @{ L = 'Ajuda da ferramenta';       A = 'help'   }
        @{ L = 'Documentacao online';       A = 'docs'   }
        @{ L = 'Arquivo de ajuda (.chm)';   A = 'chm'    }
        @{ L = '-';                         A = ''       }
        @{ L = 'Buscar...';                 A = 'find'   }
        @{ L = 'Limpar busca';              A = 'clear'  }
    )}
    @{ T = 'Suite'; H = 'S'; I = @(
        @{ L = 'Instalar / Atualizar';      A = 'install' }
        @{ L = 'Configurar...';             A = 'config'  }
        @{ L = 'Abrir pasta da suite';      A = 'open'    }
    )}
    @{ T = 'Catalogo'; H = 'C'; I = @(
        @{ L = 'Atualizar agora';           A = 'update'  }
        @{ L = 'Informacoes do catalogo';   A = 'catinfo' }
    )}
    @{ T = 'Ajuda'; H = 'A'; I = @(
        @{ L = 'Teclas de atalho';          A = 'keys'    }
        @{ L = 'Sobre';                     A = 'about'   }
    )}
)

function Get-MenuPositions {
    $pos = @()
    $x = 2
    foreach ($m in $script:Menus) {
        $pos += @{ X = $x; W = $m.T.Length + 2 }
        $x += $m.T.Length + 3
    }
    return $pos
}

function Draw-MenuBar ([int]$Active = -1) {
    $cw = [Console]::WindowWidth - 1
    W 0 0 (' ' * $cw) $T.MenuFg $T.MenuBg
    $pos = Get-MenuPositions
    for ($i = 0; $i -lt $script:Menus.Count; $i++) {
        $lbl = " $($script:Menus[$i].T) "
        if ($i -eq $Active) { W $pos[$i].X 0 $lbl $T.SelFg $T.SelBg }
        else { W $pos[$i].X 0 $lbl $T.MenuFg $T.MenuBg }
    }
    $clock = Get-Date -Format 'dd/MM/yyyy  HH:mm'
    W ([Math]::Max(1, $cw - $clock.Length - 1)) 0 $clock $T.MenuFg $T.MenuBg
}

function Invoke-MenuBar ([int]$Start = 0) {
    $mi = [Math]::Max(0, [Math]::Min($Start, $script:Menus.Count - 1))
    $ii = 0
    $pos = Get-MenuPositions
    while ($true) {
        $menu = $script:Menus[$mi]
        Draw-MenuBar $mi

        $wd = 4
        foreach ($it in $menu.I) { if ($it.L.Length + 6 -gt $wd) { $wd = $it.L.Length + 6 } }
        $ht = $menu.I.Count + 2
        $x = [Math]::Min($pos[$mi].X, [Console]::WindowWidth - $wd - 4)
        $y = 1

        # guarda o que esta sob o menu para restaurar ao trocar/fechar
        $saved = $null
        $origin = $null
        try {
            $bw = [Console]::BufferWidth; $bh = [Console]::BufferHeight
            $r = New-Object System.Management.Automation.Host.Rectangle `
                 $x, $y, ([Math]::Min($x + $wd + 1, $bw - 1)), ([Math]::Min($y + $ht, $bh - 1))
            $saved = $Host.UI.RawUI.GetBufferContents($r)
            $origin = New-Object System.Management.Automation.Host.Coordinates $x, $y
        } catch { $saved = $null }

        Draw-Window $x $y $wd $ht '' $T.DlgBg $T.DlgBorder $T.DlgFg

        for ($i = 0; $i -lt $menu.I.Count; $i++) {
            $it = $menu.I[$i]
            if ($it.L -eq '-') {
                W ($x + 1) ($y + 1 + $i) ($B.LH * ($wd - 2)) 'DarkGray' $T.DlgBg
                continue
            }
            if ($i -eq $ii) { W ($x + 1) ($y + 1 + $i) (' ' + $it.L).PadRight($wd - 2) $T.SelFg $T.SelBg }
            else { W ($x + 1) ($y + 1 + $i) (' ' + $it.L).PadRight($wd - 2) $T.DlgFg $T.DlgBg }
        }

        $k = [Console]::ReadKey($true)

        if ($saved) { try { $Host.UI.RawUI.SetBufferContents($origin, $saved) } catch { } }

        switch ($k.Key) {
            'Escape'     { Draw-MenuBar; return $null }
            'F10'        { Draw-MenuBar; return $null }
            'LeftArrow'  { $mi = ($mi - 1 + $script:Menus.Count) % $script:Menus.Count; $ii = 0 }
            'RightArrow' { $mi = ($mi + 1) % $script:Menus.Count; $ii = 0 }
            'UpArrow' {
                do { $ii = ($ii - 1 + $menu.I.Count) % $menu.I.Count } while ($menu.I[$ii].L -eq '-')
            }
            'DownArrow' {
                do { $ii = ($ii + 1) % $menu.I.Count } while ($menu.I[$ii].L -eq '-')
            }
            'Enter' {
                if ($menu.I[$ii].A) { Draw-MenuBar; return $menu.I[$ii].A }
            }
        }
    }
}

# ==============================================================================
#  Tela principal: navegador de categorias/ferramentas
# ==============================================================================
function Show-Browser ($Cfg) {
    $tools = Get-Catalog $Cfg
    $cats = @('Todas') + $script:Categories
    $catIdx = 0
    $sel = 0
    $top = 0
    $filter = ''

    $fkeys = @(
        @{K='F1'; L='Ajuda '}, @{K='F2'; L='Docs  '}, @{K='F3'; L='Chm   '}, @{K='F4'; L='Args  '},
        @{K='F5'; L='Exec  '}, @{K='F6'; L='Buscar'}, @{K='F7'; L='Instal'}, @{K='F8'; L='Config'},
        @{K='F9'; L='Atuali'}, @{K='F10';L='Menu  '}
    )

    $needFull = $true
    $lastSize = ''
    $lastVisKey = ''
    $visible = @()

    while ($true) {
        $cw = [Console]::WindowWidth - 1
        $ch = [Console]::WindowHeight
        if ("$cw-$ch" -ne $lastSize) { $needFull = $true; $lastSize = "$cw-$ch" }
        $winX = 0
        $winY = 1
        $winW = $cw - 2
        $winH = $ch - 3

        $listW = [Math]::Max(18, [Math]::Min(32, [int]($winW * 0.32)))
        $listX = $winX + 2
        $detX = $listX + $listW + 3
        $detW = [Math]::Max(20, $winX + $winW - $detX - 2)
        $rowTop = $winY + 5
        $rowEnd = $winY + $winH - 3
        $rows = $rowEnd - $rowTop + 1

        $visKey = "$catIdx|$filter|$($tools.Count)"
        if ($visKey -ne $lastVisKey) {
            $visible = @($tools | Where-Object {
                ($cats[$catIdx] -eq 'Todas' -or $_.Category -eq $cats[$catIdx]) -and
                (-not $filter -or $_.Name -like "*$filter*" -or $_.Desc -like "*$filter*" -or $_.DocDesc -like "*$filter*")
            } | Sort-Object Name)
            $lastVisKey = $visKey
        }

        if ($sel -ge $visible.Count) { $sel = [Math]::Max(0, $visible.Count - 1) }
        if ($sel -lt $top) { $top = $sel }
        if ($sel -ge ($top + $rows)) { $top = $sel - $rows + 1 }

        # ---- desktop + janela principal ----
        if ($needFull) {
            Draw-Desktop $null
            Draw-MenuBar
            Draw-Window $winX $winY $winW $winH "$script:AppName v$script:Version"
            Draw-FKeys $fkeys
            W $winX ($winY + 2) ($B.ML + ($B.HZ * ($winW - 2)) + $B.MR) $T.WinBorder
            W $winX ($winY + 4) ($B.ML + ($B.HZ * ($winW - 2)) + $B.MR) $T.WinBorder
            W $winX ($winY + $winH - 2) ($B.ML + ($B.HZ * ($winW - 2)) + $B.MR) $T.WinBorder
            $needFull = $false
        }
        $script:CurBg = $T.WinBg
        $script:CurFg = $T.WinFg

        $installed = Test-Path -LiteralPath $Cfg.InstallDirectory
        W ($winX + 3) ($winY + 1) 'Suite:' $T.DimFg
        W ($winX + 10) ($winY + 1) $Cfg.InstallDirectory 'White'
        $st = if ($installed) { ' instalada ' } else { ' nao instalada ' }
        W ($winX + 11 + $Cfg.InstallDirectory.Length) ($winY + 1) $st 'Black' $(if ($installed) { 'Green' } else { 'DarkYellow' })

        # ---- abas de categorias ----
        $x = $winX + 2
        W ($winX + 1) ($winY + 3) (' ' * ($winW - 2))
        for ($i = 0; $i -lt $cats.Count; $i++) {
            $label = " $($cats[$i]) "
            if (($x + $label.Length) -ge ($winX + $winW - 2)) { break }
            if ($i -eq $catIdx) { W $x ($winY + 3) $label $T.SelFg $T.SelBg }
            else { W $x ($winY + 3) $label $T.DimFg }
            $x += $label.Length
        }

        # ---- cabecalhos dos paineis ----
        $hdr = if ($filter) { " Ferramentas ($($visible.Count)) - filtro: $filter " } else { " Ferramentas ($($visible.Count)) " }
        W $listX ($winY + 4) ($B.HZ * ($detX - $listX - 2)) $T.WinBorder
        W $listX ($winY + 4) $hdr $T.AccentFg $T.WinBg
        W $detX ($winY + 4) ' Detalhes ' $T.AccentFg $T.WinBg
        for ($r = $rowTop; $r -le $rowEnd; $r++) { W ($detX - 2) $r $B.LV 'DarkCyan' }

        # ---- lista ----
        for ($i = 0; $i -lt $rows; $i++) {
            $y = $rowTop + $i
            $idx = $top + $i
            if ($idx -ge $visible.Count) { W $listX $y (' ' * $listW); continue }
            $tl = $visible[$idx]
            $has = $null -ne (Resolve-ToolPath $tl $Cfg.InstallDirectory)
            $mark = if ($has) { [string][char]0x25A0 } else { [string][char]0x00B7 }
            $name = $tl.Name
            if ($name.Length -gt ($listW - 4)) { $name = $name.Substring(0, $listW - 7) + '...' }
            if ($idx -eq $sel) {
                W $listX $y ((' ' + $mark + ' ' + $name).PadRight($listW)) $T.SelFg $T.SelBg
            } else {
                W $listX $y (' ' + $mark + ' ') $(if ($has) { 'Green' } else { 'DarkCyan' })
                W ($listX + 3) $y $name.PadRight($listW - 3) 'White'
            }
        }
        # barra de rolagem estilo DOS
        if ($visible.Count -gt $rows) {
            $sbX = $detX - 3
            W $sbX $rowTop $B.UP 'Cyan'
            W $sbX $rowEnd $B.DN 'Cyan'
            for ($r = $rowTop + 1; $r -lt $rowEnd; $r++) { W $sbX $r $B.LIGHT 'DarkCyan' }
            $track = $rowEnd - $rowTop - 1
            $thumb = $rowTop + 1 + [int](($sel / [Math]::Max(1, $visible.Count - 1)) * ($track - 1))
            W $sbX $thumb $B.FULL 'Cyan'
        }

        # ---- painel de detalhes ----
        $needUsage = $false
        for ($r = $rowTop; $r -le $rowEnd; $r++) { W $detX $r (' ' * $detW) }
        if ($visible.Count -eq 0) {
            W $detX $rowTop 'Nenhuma ferramenta nesta categoria/filtro.' $T.WarnFg
        } else {
            $tl = $visible[$sel]
            $exe = Resolve-ToolPath $tl $Cfg.InstallDirectory
            $y = $rowTop
            W $detX $y $tl.Name.ToUpper() $T.AccentFg; $y++
            $meta = "$($tl.Category)" + $(if ($tl.Version) { "  |  $($tl.Version)" } else { '' }) + $(if ($tl.IsGui) { '  |  GUI' } else { '  |  console' })
            W $detX $y $meta 'Cyan'; $y++
            W $detX $y ($B.LH * $detW) 'DarkCyan'; $y++

            foreach ($l in (Split-Wrap $tl.Desc $detW)) { if ($y -le $rowEnd) { W $detX $y $l 'White'; $y++ } }
            if ($tl.DocDesc) {
                $y++
                if ($y -le $rowEnd) { W $detX $y 'Microsoft Docs:' 'Cyan'; $y++ }
                foreach ($l in (Split-Wrap $tl.DocDesc $detW)) { if ($y -le $rowEnd) { W $detX $y $l $T.DimFg; $y++ } }
            }
            $y++
            if ($y -le $rowEnd) {
                if ($exe) { W $detX $y "Executavel: $([IO.Path]::GetFileName($exe))" $T.OkFg }
                else { W $detX $y 'Executavel ausente - use F7 para instalar a suite' $T.WarnFg }
                $y++
            }
            if ($y -le $rowEnd) { W $detX $y ($B.LH * $detW) 'DarkCyan'; $y++ }
            if ($y -le $rowEnd) { W $detX $y 'PARAMETROS DE LINHA DE COMANDO' $T.AccentFg; $y++ }
            $needUsage = $false
            $usage = $null
            if ($exe -and -not $tl.IsGui) {
                if ($script:UsageMem.ContainsKey($tl.Name)) { $usage = $script:UsageMem[$tl.Name] }
                else { $needUsage = $true }
            }
            if ($usage) {
                foreach ($l in ($usage -split "`n")) {
                    if ($y -ge $rowEnd) { W $detX $y ('  ' + [string][char]0x25BC + ' F1 mostra a ajuda completa') 'Cyan'; break }
                    $txt = $l.TrimEnd()
                    if ($txt.Length -gt $detW) { $txt = $txt.Substring(0, $detW) }
                    W $detX $y $txt $T.DimFg; $y++
                }
            } elseif ($needUsage) {
                W $detX $y 'lendo a ajuda do executavel...' $T.WarnFg
            } elseif ($tl.IsGui) {
                W $detX $y 'Ferramenta grafica - use F3 (.chm) ou F2 (docs online).' $T.DimFg
            } else {
                W $detX $y 'Instale a suite para ler os parametros do executavel.' $T.DimFg
            }
        }

        # ---- linha de status dentro da janela ----
        $status = if ($visible.Count -gt 0) { "$($sel + 1)/$($visible.Count)  $($visible[$sel].Name)" } else { 'vazio' }
        W ($winX + 1) ($winY + $winH - 1) (' ' * ($winW - 2))
        W ($winX + 2) ($winY + $winH - 1) " $status " $T.SelFg $T.SelBg
        $hint = 'F10 menu   ENTER executa   setas/TAB navegam   Alt+X sai'
        W ($winX + $winW - $hint.Length - 3) ($winY + $winH - 1) $hint 'Cyan' $T.WinBg

        # so consulta o executavel quando o usuario para de navegar
        if ($needUsage -and -not [Console]::KeyAvailable) {
            Get-ToolUsage $visible[$sel] $Cfg.InstallDirectory | Out-Null
            continue
        }

        # ---- teclado ----
        $k = [Console]::ReadKey($true)
        $cur = if ($visible.Count -gt 0) { $visible[$sel] } else { $null }
        $menuAction = $null

        if ($k.Modifiers -band [ConsoleModifiers]::Alt) {
            $hot = $k.KeyChar.ToString().ToUpper()
            if ($k.Key -eq 'X') { return }
            $mi = -1
            for ($i = 0; $i -lt $script:Menus.Count; $i++) { if ($script:Menus[$i].H -eq $hot -or "$($k.Key)" -eq $script:Menus[$i].H) { $mi = $i; break } }
            if ($mi -ge 0) { $menuAction = Invoke-MenuBar $mi; $needFull = $true }
            else { continue }
        }
        elseif ($k.Key -eq 'F10') {
            $menuAction = Invoke-MenuBar 0
            $needFull = $true
        }

        if ($menuAction) {
            switch ($menuAction) {
                'run'     { if ($cur) { Invoke-Tool $cur $Cfg @() } }
                'args'    { if ($cur) { $a = Read-Arguments $cur; Invoke-Tool $cur $Cfg $a } }
                'help'    { if ($cur) { Show-ToolHelpScreen $cur $Cfg } }
                'docs'    { if ($cur) { Start-Process $cur.DocUrl | Out-Null } }
                'chm'     { if ($cur) { Open-HelpFile $cur $Cfg } }
                'find'    { $filter = (Show-InputBox 'BUSCAR' 'Texto a procurar no nome ou na descricao:' '').Trim(); $sel = 0; $top = 0 }
                'clear'   { $filter = ''; $sel = 0; $top = 0 }
                'install' { if (Invoke-Install $Cfg) { $script:UsageMem = @{}; $script:PathCache = @{} } }
                'config'  { $Cfg = Show-ConfigScreen $Cfg; $tools = Get-Catalog $Cfg; $script:PathCache = @{} }
                'open'    { if (Test-Path -LiteralPath $Cfg.InstallDirectory) { Start-Process explorer.exe $Cfg.InstallDirectory | Out-Null } else { Show-MessageBox 'SUITE' @('Diretorio nao existe ainda.') 'DarkRed' } }
                'update'  {
                    Show-MessageBox 'CATALOGO' @('Baixando a documentacao oficial...') 'DarkBlue' -NoWait
                    $r = Update-DocsCache $Cfg -Quiet
                    $tools = Get-Catalog $Cfg
                    if ($r) { Show-MessageBox 'CATALOGO' @("Catalogo atualizado: $($r.Items.Count) ferramentas.") 'DarkGreen' }
                    else { Show-MessageBox 'CATALOGO' @('Falha ao atualizar o catalogo.') 'DarkRed' }
                }
                'catinfo' {
                    $cat = Get-DocsCache
                    if ($cat) {
                        Show-MessageBox 'CATALOGO' @(
                            "Ferramentas documentadas: $($cat.Items.Count)",
                            "Atualizado em: $(([datetime]$cat.Updated).ToString('dd/MM/yyyy HH:mm'))",
                            "Validade: $($Cfg.CatalogMaxAgeDays) dia(s)",
                            '',
                            "Fonte: $($cat.Source)"
                        ) 'DarkBlue'
                    } else { Show-MessageBox 'CATALOGO' @('Catalogo ainda nao baixado (F9).') 'DarkRed' }
                }
                'keys'    { Show-KeysBox }
                'about'   { Show-AboutBox }
            }
            continue
        }

        switch ($k.Key) {
            'UpArrow'    { if ($sel -gt 0) { $sel-- } }
            'DownArrow'  { if ($sel -lt ($visible.Count - 1)) { $sel++ } }
            'PageUp'     { $sel = [Math]::Max(0, $sel - $rows) }
            'PageDown'   { $sel = [Math]::Min($visible.Count - 1, $sel + $rows) }
            'Home'       { $sel = 0 }
            'End'        { $sel = [Math]::Max(0, $visible.Count - 1) }
            'LeftArrow'  { $catIdx = ($catIdx - 1 + $cats.Count) % $cats.Count; $sel = 0; $top = 0 }
            'RightArrow' { $catIdx = ($catIdx + 1) % $cats.Count; $sel = 0; $top = 0 }
            'Tab'        { $catIdx = ($catIdx + 1) % $cats.Count; $sel = 0; $top = 0 }
            'Enter'      { if ($cur) { Invoke-Tool $cur $Cfg @(); $needFull = $true } }
            'F1'         { if ($cur) { Show-ToolHelpScreen $cur $Cfg; $needFull = $true } }
            'F2'         { if ($cur) { Start-Process $cur.DocUrl | Out-Null } }
            'F3'         { if ($cur) { Open-HelpFile $cur $Cfg; $needFull = $true } }
            'F4'         { if ($cur) { $a = Read-Arguments $cur; Invoke-Tool $cur $Cfg $a; $needFull = $true } }
            'F5'         { if ($cur) { Invoke-Tool $cur $Cfg @(); $needFull = $true } }
            'F6'         { $filter = (Show-InputBox 'BUSCAR' 'Texto a procurar no nome ou na descricao:' '').Trim(); $sel = 0; $top = 0; $needFull = $true }
            'F7'         { if (Invoke-Install $Cfg) { $script:UsageMem = @{}; $script:PathCache = @{} }; $needFull = $true }
            'F8'         { $Cfg = Show-ConfigScreen $Cfg; $tools = Get-Catalog $Cfg; $script:PathCache = @{}; $needFull = $true }
            'F9'         {
                Show-MessageBox 'CATALOGO' @('Baixando a documentacao oficial...') 'DarkBlue' -NoWait
                $r = Update-DocsCache $Cfg -Quiet
                $tools = Get-Catalog $Cfg
                if ($r) { Show-MessageBox 'CATALOGO' @("Catalogo atualizado: $($r.Items.Count) ferramentas.") 'DarkGreen' }
                else { Show-MessageBox 'CATALOGO' @('Falha ao atualizar o catalogo.') 'DarkRed' }
                $needFull = $true
            }
            'Escape'     { return }
            default {
                switch ($k.KeyChar.ToString().ToUpper()) {
                    'H' { if ($cur) { Show-ToolHelpScreen $cur $Cfg; $needFull = $true } }
                    'A' { if ($cur) { $a = Read-Arguments $cur; Invoke-Tool $cur $Cfg $a; $needFull = $true } }
                    'F' { if ($cur) { Open-HelpFile $cur $Cfg; $needFull = $true } }
                    'D' { if ($cur) { Start-Process $cur.DocUrl | Out-Null } }
                    'I' { if (Invoke-Install $Cfg) { $script:UsageMem = @{}; $script:PathCache = @{} }; $needFull = $true }
                    'C' { $Cfg = Show-ConfigScreen $Cfg; $tools = Get-Catalog $Cfg; $script:PathCache = @{}; $needFull = $true }
                    '?' { Show-KeysBox; $needFull = $true }
                    '/' { $filter = (Show-InputBox 'BUSCAR' 'Texto a procurar no nome ou na descricao:' '').Trim(); $sel = 0; $top = 0; $needFull = $true }
                    'L' { $filter = ''; $sel = 0; $top = 0 }
                    'Q' { return }
                }
            }
        }
    }
}

# ==============================================================================
#  Modo linha de comando
# ==============================================================================
function Find-Tool ($Tools, [string]$Name) {
    $n = $Name.Trim()
    $m = @($Tools | Where-Object { $_.Name -eq $n })
    if ($m.Count -eq 0) { $m = @($Tools | Where-Object { ($_.Name -replace '\s', '') -eq ($n -replace '\s', '') }) }
    if ($m.Count -eq 0) { $m = @($Tools | Where-Object { $_.Exes -contains "$n.exe" -or $_.Exes -contains $n }) }
    if ($m.Count -eq 0) { $m = @($Tools | Where-Object { $_.Slug -eq $n }) }
    if ($m.Count -eq 0) { $m = @($Tools | Where-Object { $_.Name -like "*$n*" -or ($_.Exes -join ',') -like "*$n*" }) }
    if ($m.Count -eq 0) { return $null }
    return $m[0]
}

function Show-CliHelp {
    $lines = @(
        @{ T = "$script:AppName v$script:Version - frontend para a suite SysInternals"; C = 'Cyan' }
        @{ T = ''; C = 'Gray' }
        @{ T = 'USO:'; C = 'Yellow' }
        @{ T = '  .\SysInternals-Frontend.ps1                      abre o menu interativo'; C = 'Gray' }
        @{ T = '  .\SysInternals-Frontend.ps1 --Help               mostra esta ajuda'; C = 'Gray' }
        @{ T = '  .\SysInternals-Frontend.ps1 --Help <ferramenta>  resumo + parametros da ferramenta'; C = 'Gray' }
        @{ T = '  .\SysInternals-Frontend.ps1 --Run <ferramenta> [args...]   executa a ferramenta'; C = 'Gray' }
        @{ T = '  .\SysInternals-Frontend.ps1 --Download           baixa e instala/atualiza a suite'; C = 'Gray' }
        @{ T = '  .\SysInternals-Frontend.ps1 --Configure          abre a tela de configuracao'; C = 'Gray' }
        @{ T = '  .\SysInternals-Frontend.ps1 --Update             atualiza o catalogo pela documentacao'; C = 'Gray' }
        @{ T = '  .\SysInternals-Frontend.ps1 --List [categoria]   lista as ferramentas do catalogo'; C = 'Gray' }
        @{ T = '  .\SysInternals-Frontend.ps1 --Path <diretorio>   usa/define outro diretorio da suite'; C = 'Gray' }
        @{ T = '  .\SysInternals-Frontend.ps1 --Docs <ferramenta>  abre a documentacao online'; C = 'Gray' }
        @{ T = ''; C = 'Gray' }
        @{ T = 'Os parametros aceitam - ou -- (ex.: -Run e --Run sao equivalentes).'; C = 'DarkGray' }
        @{ T = ''; C = 'Gray' }
        @{ T = 'TECLAS NO MENU INTERATIVO:'; C = 'Yellow' }
        @{ T = '  F1 ajuda   F2 docs online   F3 arquivo .chm   F4 argumentos   F5 executar'; C = 'Gray' }
        @{ T = '  F6 buscar  F7 instalar suite  F8 configurar    F9 atualizar catalogo'; C = 'Gray' }
        @{ T = '  F10 abre a barra de menus (ou Alt+F, Alt+S, Alt+C, Alt+A)   Alt+X / ESC sai'; C = 'Gray' }
        @{ T = '  setas/TAB navegam e trocam de categoria   ENTER executa   ? teclas'; C = 'Gray' }
        @{ T = ''; C = 'Gray' }
        @{ T = "Diretorio padrao: $($script:Defaults.InstallDirectory)"; C = 'DarkGray' }
        @{ T = "Cache/config    : $script:CacheDir"; C = 'DarkGray' }
    )
    foreach ($l in $lines) { Write-Host $l.T -ForegroundColor $l.C }
}

function Show-CliToolHelp ($Tool, $Cfg) {
    $exe = Resolve-ToolPath $Tool $Cfg.InstallDirectory
    Write-Host ''
    Write-Host " $($Tool.Name) " -ForegroundColor Black -BackgroundColor Cyan -NoNewline
    if ($Tool.Version) { Write-Host "  $($Tool.Version)" -ForegroundColor DarkGray } else { Write-Host '' }
    Write-Host "Categoria : $($Tool.Category)" -ForegroundColor DarkGray
    Write-Host "Tipo      : $(if ($Tool.IsGui) { 'grafica (GUI)' } else { 'linha de comando' })" -ForegroundColor DarkGray
    Write-Host "Executavel: $(if ($exe) { $exe } else { 'nao encontrado em ' + $Cfg.InstallDirectory })" -ForegroundColor $(if ($exe) { 'Green' } else { 'Red' })
    Write-Host "Docs      : $($Tool.DocUrl)" -ForegroundColor DarkCyan
    Write-Host ''
    foreach ($l in (Split-Wrap $Tool.Desc 100)) { Write-Host $l -ForegroundColor White }
    if ($Tool.DocDesc) {
        Write-Host ''
        foreach ($l in (Split-Wrap $Tool.DocDesc 100)) { Write-Host $l -ForegroundColor Gray }
    }
    Write-Host ''
    Write-Host 'PARAMETROS DE LINHA DE COMANDO' -ForegroundColor Yellow
    Write-Host ('-' * 60) -ForegroundColor DarkCyan
    $usage = if ($exe) { Get-ToolUsage $Tool $Cfg.InstallDirectory } else { $null }
    if ($usage) { Write-Host $usage }
    elseif ($Tool.IsGui) { Write-Host 'Ferramenta grafica: consulte a documentacao online ou o arquivo .chm.' -ForegroundColor DarkYellow }
    else { Write-Host 'Ajuda indisponivel (suite nao instalada?).' -ForegroundColor DarkYellow }

    $files = Get-ToolHelpFiles $Tool $Cfg.InstallDirectory
    if ($files.Count -gt 0) {
        Write-Host ''
        Write-Host 'Arquivos de ajuda locais:' -ForegroundColor Yellow
        foreach ($f in $files) { Write-Host "  $($f.FullName)" -ForegroundColor Gray }
    }
}

function Show-CliList ($Tools, [string]$Category) {
    $sel = $Tools
    if ($Category) { $sel = @($Tools | Where-Object { $_.Category -like "*$Category*" }) }
    foreach ($g in ($sel | Group-Object Category | Sort-Object Name)) {
        Write-Host ''
        Write-Host " $($g.Name) " -ForegroundColor Black -BackgroundColor Cyan
        foreach ($ct in ($g.Group | Sort-Object Name)) {
            Write-Host ('  {0,-22}' -f $ct.Name) -ForegroundColor White -NoNewline
            $d = $ct.Desc
            if ($d.Length -gt 78) { $d = $d.Substring(0, 75) + '...' }
            Write-Host $d -ForegroundColor DarkGray
        }
    }
    Write-Host ''
}

# ==============================================================================
#  Entrada
# ==============================================================================
function Start-App ([string[]]$Tokens) {
    $cfg = Get-AppConfig

    # normaliza "--opcao" -> "-opcao"
    $tk = @()
    foreach ($tok in @($Tokens)) { if ($null -ne $tok) { $tk += ($tok -replace '^--', '-') } }

    $action = ''
    $target = ''
    $rest = @()
    $i = 0
    while ($i -lt $tk.Count) {
        $a = $tk[$i]
        $next = if ($i + 1 -lt $tk.Count) { $tk[$i + 1] } else { $null }
        if ($a -match '^-(h|help|\?)$') {
            $action = 'help'
            if ($next -and $next -notmatch '^-') { $target = $next; $i++ }
        }
        elseif ($a -match '^-(run|exec|x)$') {
            $action = 'run'
            if ($next) { $target = $next; $i++ }
            if ($i + 1 -lt $tk.Count) { $rest = @($Tokens[($i + 1)..($tk.Count - 1)]) }
            $i = $tk.Count
        }
        elseif ($a -match '^-(download|install)$')  { $action = 'download' }
        elseif ($a -match '^-(configure|config)$')  { $action = 'configure' }
        elseif ($a -match '^-(update)$')            { $action = 'update' }
        elseif ($a -match '^-(list)$') {
            $action = 'list'
            if ($next -and $next -notmatch '^-') { $target = $next; $i++ }
        }
        elseif ($a -match '^-(docs|web)$') {
            $action = 'docs'
            if ($next) { $target = $next; $i++ }
        }
        elseif ($a -match '^-(path|dir)$') {
            if ($next) { $cfg.InstallDirectory = $next; $i++ }
        }
        elseif (-not $action -and $a -notmatch '^-') { $action = 'help'; $target = $a }
        $i++
    }

    if ($action -eq 'help' -and -not $target) { Show-CliHelp; return }

    switch ($action) {
        'download' {
            Invoke-Install $cfg | Out-Null
            [Console]::ResetColor(); [Console]::Clear(); [Console]::CursorVisible = $true
            return
        }
        'configure' {
            $cfg = Show-ConfigScreen $cfg
            [Console]::ResetColor(); [Console]::Clear(); [Console]::CursorVisible = $true
            Write-Host "Diretorio da suite: $($cfg.InstallDirectory)" -ForegroundColor Cyan
            return
        }
        'update' {
            Write-Host 'Atualizando catalogo a partir da documentacao oficial...' -ForegroundColor Yellow
            $r = Update-DocsCache $cfg
            if ($r) { Write-Host "Catalogo atualizado: $($r.Items.Count) ferramentas (fonte: $($r.Source))." -ForegroundColor Green }
            return
        }
        'list' {
            Show-CliList (Get-Catalog $cfg) $target
            return
        }
    }

    if ($action -in @('help', 'run', 'docs')) {
        $tools = Get-Catalog $cfg
        $tool = Find-Tool $tools $target
        if (-not $tool) {
            Write-Host "Ferramenta '$target' nao encontrada no catalogo. Use --List para ver os nomes." -ForegroundColor Red
            return
        }
        switch ($action) {
            'help' { Show-CliToolHelp $tool $cfg }
            'docs' { Start-Process $tool.DocUrl | Out-Null }
            'run'  {
                $exe = Resolve-ToolPath $tool $cfg.InstallDirectory
                if (-not $exe) {
                    Write-Host "Executavel de $($tool.Name) nao encontrado em $($cfg.InstallDirectory). Use --Download." -ForegroundColor Red
                    return
                }
                Set-EulaAccepted $tool
                if ($rest.Count -gt 0) { & $exe @rest } else { & $exe }
            }
        }
        return
    }

    # Modo interativo
    try { if ([Console]::WindowWidth -lt 100) { [Console]::WindowWidth = 100 } } catch { }
    try { if ([Console]::WindowHeight -lt 32) { [Console]::WindowHeight = 32 } } catch { }
    try {
        [Console]::Clear()
        Draw-Desktop "  $script:AppName v$script:Version" (Get-Date -Format 'dd/MM/yyyy  HH:mm')
        Show-MessageBox "$script:AppName v$script:Version" @(
            'Suite SysInternals da Microsoft',
            '',
            "Diretorio : $($cfg.InstallDirectory)",
            "Catalogo  : $(if (Get-DocsCache) { 'em cache' } else { 'sera baixado agora' })",
            '',
            'Carregando catalogo de ferramentas...'
        ) 'DarkBlue' -NoWait
        Show-Browser $cfg
    } finally {
        [Console]::ResetColor()
        [Console]::Clear()
        [Console]::CursorVisible = $true
        Write-Host "$script:AppName encerrado." -ForegroundColor Cyan
    }
}

Start-App $CmdArgs
