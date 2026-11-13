<#
.SYNOPSIS
    Sincroniza perfis do Chrome, Edge e Vivaldi com contas do OneDrive.
.DESCRIPTION
    Descobre os nomes dos perfis no Local State dos navegadores e permite
    associar cada perfil a uma conta identificada por nome ou e-mail.
    Requer Rclone; oferece instalacao via Winget quando necessario.
#>

$ScriptDir = $PSScriptRoot
$ConfigFile = Join-Path $ScriptDir 'config-navegadores.json'
$CaminhosBase = @{
    Chrome  = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    Edge    = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    Vivaldi = "$env:LOCALAPPDATA\Vivaldi\User Data"
}

function Salvar-Configuracao {
    param($Config)
    $Config | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $ConfigFile -Encoding UTF8 -ErrorAction Stop
}

function Ler-Configuracao {
    $Config = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
    if (-not $Config.PSObject.Properties['Mapeamentos']) {
        throw 'A configuracao precisa conter a lista Mapeamentos.'
    }
    if (-not $Config.PSObject.Properties['Contas']) {
        $Config | Add-Member -NotePropertyName Contas -NotePropertyValue @(
            [PSCustomObject]@{ Remote = 'onedrive_pessoal_1'; NomeExibicao = 'OneDrive pessoal 1'; Identificada = $false }
            [PSCustomObject]@{ Remote = 'onedrive_pessoal_2'; NomeExibicao = 'OneDrive pessoal 2'; Identificada = $false }
            [PSCustomObject]@{ Remote = 'onedrive_profissional'; NomeExibicao = 'OneDrive profissional'; Identificada = $false }
        )
    }
    $Remotos = @()
    foreach ($Conta in $Config.Contas) {
        if ($Conta.Remote -notmatch '^[A-Za-z0-9_-]+$' -or
            [string]::IsNullOrWhiteSpace($Conta.NomeExibicao) -or $Conta.Remote -in $Remotos) {
            throw 'Conta invalida ou repetida na configuracao.'
        }
        $Remotos += $Conta.Remote
        if (-not $Conta.PSObject.Properties['Identificada']) {
            $Conta | Add-Member -NotePropertyName Identificada -NotePropertyValue $false
        }
    }
    if ($Remotos.Count -eq 0) { throw 'Cadastre pelo menos uma conta do OneDrive.' }
    $Perfis = @()
    $Destinos = @()
    foreach ($Item in $Config.Mapeamentos) {
        $Chave = "$($Item.Navegador)|$($Item.PerfilPasta)"
        if (-not $CaminhosBase.ContainsKey([string]$Item.Navegador) -or
            $Item.PerfilPasta -notmatch '^(Default|Profile \d+)$' -or
            $Chave -in $Perfis -or $Item.DestinoNuvem -in $Destinos) {
            throw 'Mapeamento invalido, perfil repetido ou destino compartilhado entre perfis.'
        }
        $Partes = ([string]$Item.DestinoNuvem) -split ':', 2
        if ($Partes.Count -ne 2 -or $Partes[0] -notin $Remotos -or
            [string]::IsNullOrWhiteSpace($Partes[1]) -or
            $Partes[1] -match '(^[/\\]|(^|[/\\])\.\.([/\\]|$))') {
            throw "Destino de nuvem invalido para $($Item.NomeExibicao)."
        }
        $Perfis += $Chave
        $Destinos += $Item.DestinoNuvem
    }
    return $Config
}

function Selecionar-Itens {
    param([array]$Itens, [string]$Titulo, [switch]$Multiplo)
    if ($Itens.Count -eq 0) {
        Write-Host 'Nenhum item disponivel.' -ForegroundColor Yellow
        return
    }
    while ($true) {
        Write-Host "`n$Titulo" -ForegroundColor Cyan
        for ($i = 0; $i -lt $Itens.Count; $i++) {
            Write-Host " [$($i + 1)] $($Itens[$i].Rotulo)"
        }
        if ($Multiplo) { Write-Host ' [T] Todos (ou numeros separados por virgula)' }
        Write-Host ' [S] Voltar'
        $Resposta = (Read-Host 'Escolha').Trim()
        if ($Resposta -eq 'S') { return }
        if ($Multiplo -and $Resposta -eq 'T') { return $Itens }
        $Numeros = @($Resposta -split ',' | ForEach-Object { $_.Trim() })
        $Indices = @()
        $Valido = $Multiplo -or $Numeros.Count -eq 1
        foreach ($Numero in $Numeros) {
            $Indice = 0
            if (-not [int]::TryParse($Numero, [ref]$Indice) -or $Indice -lt 1 -or $Indice -gt $Itens.Count) {
                $Valido = $false
                break
            }
            $Indices += $Indice - 1
        }
        if ($Valido) {
            foreach ($Indice in ($Indices | Select-Object -Unique)) { $Itens[$Indice] }
            return
        }
        Write-Host 'Opcao invalida. Escolha um numero da lista.' -ForegroundColor Yellow
    }
}

function Identificar-Conta {
    param($Conta, $Config)
    Write-Host "`nIdentifique $($Conta.NomeExibicao). Use o nome ou e-mail da conta Microsoft."
    do {
        $Nome = (Read-Host 'Nome da conta (S para cancelar)').Trim()
        if ($Nome -eq 'S') { return $false }
        $Repetido = @($Config.Contas | Where-Object {
            $_.Remote -ne $Conta.Remote -and $_.NomeExibicao -eq $Nome
        }).Count -gt 0
        if ([string]::IsNullOrWhiteSpace($Nome) -or $Repetido) {
            Write-Host 'Informe um nome nao vazio e diferente das outras contas.' -ForegroundColor Yellow
        }
    } while ([string]::IsNullOrWhiteSpace($Nome) -or $Repetido)
    $Conta.NomeExibicao = $Nome
    $Conta.Identificada = $true
    Salvar-Configuracao $Config
    return $true
}

function Selecionar-Conta {
    param($Config)
    $Opcoes = @($Config.Contas | ForEach-Object {
        [PSCustomObject]@{ Rotulo = $_.NomeExibicao; Conta = $_ }
    })
    $Escolhida = Selecionar-Itens -Itens $Opcoes -Titulo 'Escolha a conta do OneDrive:'
    if ($null -eq $Escolhida) { return }
    if (-not $Escolhida.Conta.Identificada) {
        if (-not (Identificar-Conta $Escolhida.Conta $Config)) { return }
    }
    return $Escolhida.Conta
}

function Obter-Perfis {
    param($Config)
    foreach ($Navegador in ($CaminhosBase.Keys | Sort-Object)) {
        $Base = $CaminhosBase[$Navegador]
        $StatePath = Join-Path $Base 'Local State'
        $Cache = $null
        if (Test-Path -LiteralPath $StatePath) {
            try {
                $State = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 -ErrorAction Stop |
                    ConvertFrom-Json -ErrorAction Stop
                $Cache = $State.profile.info_cache
            } catch {
                throw "Nao foi possivel ler os nomes dos perfis do ${Navegador}: $($_.Exception.Message)"
            }
        }
        $Mapeados = @($Config.Mapeamentos | Where-Object { $_.Navegador -eq $Navegador })
        $Pastas = @($Mapeados.PerfilPasta)
        if ($Cache) { $Pastas += @($Cache.PSObject.Properties.Name) }
        if (Test-Path -LiteralPath $Base) {
            $Pastas += @(Get-ChildItem -LiteralPath $Base -Directory -ErrorAction Stop |
                Where-Object { $_.Name -match '^(Default|Profile \d+)$' } |
                Select-Object -ExpandProperty Name)
        }
        foreach ($Pasta in ($Pastas | Where-Object { $_ -match '^(Default|Profile \d+)$' } | Sort-Object -Unique)) {
            $Mapeamento = $Mapeados | Where-Object { $_.PerfilPasta -eq $Pasta }
            $Info = if ($Cache) { $Cache.PSObject.Properties[$Pasta] }
            $Nome = if ($Info -and -not [string]::IsNullOrWhiteSpace($Info.Value.name)) {
                $Info.Value.name
            } elseif ($Mapeamento -and -not [string]::IsNullOrWhiteSpace($Mapeamento.NomeExibicao)) {
                $Mapeamento.NomeExibicao
            } else {
                "Perfil sem nome ($Pasta)"
            }
            $Email = if ($Info) { $Info.Value.user_name }
            $NomeCompleto = if ($Email) { "$Nome - $Email" } else { $Nome }
            $Local = Join-Path $Base $Pasta
            $Existe = Test-Path -LiteralPath $Local -PathType Container
            $Conta = if ($Mapeamento) {
                $Remote = ($Mapeamento.DestinoNuvem -split ':', 2)[0]
                $Config.Contas | Where-Object { $_.Remote -eq $Remote }
            }
            $Destino = if ($Conta) { $Conta.NomeExibicao } else { 'Escolher conta' }
            $Status = if ($Existe) { '' } else { ' [somente configurado; ausente neste PC]' }
            [PSCustomObject]@{
                Navegador = $Navegador
                PerfilPasta = $Pasta
                NomeExibicao = $Nome
                CaminhoLocal = $Local
                Existe = $Existe
                Mapeamento = $Mapeamento
                Rotulo = "$Navegador - $NomeCompleto -> $Destino$Status"
            }
        }
    }
}

function Vincular-Perfil {
    param($Perfil, $Conta, $Config)
    # Mantem a subpasta existente ao trocar de conta, inclusive em configuracoes antigas.
    $Subpasta = if ($Perfil.Mapeamento) {
        ($Perfil.Mapeamento.DestinoNuvem -split ':', 2)[1]
    } else {
        "Backups_Navegadores/$($Perfil.Navegador)/$($Perfil.PerfilPasta)"
    }
    $Destino = "$($Conta.Remote):$Subpasta"
    $Conflito = @($Config.Mapeamentos | Where-Object {
        $_.DestinoNuvem -eq $Destino -and
        ($_.Navegador -ne $Perfil.Navegador -or $_.PerfilPasta -ne $Perfil.PerfilPasta)
    })
    if ($Conflito.Count -gt 0) { throw 'Este destino ja pertence a outro perfil. Vinculo nao alterado.' }
    if ($Perfil.Mapeamento) {
        $Perfil.Mapeamento.NomeExibicao = $Perfil.NomeExibicao
        $Perfil.Mapeamento.DestinoNuvem = $Destino
    } else {
        $Perfil.Mapeamento = [PSCustomObject]@{
            Navegador = $Perfil.Navegador
            PerfilPasta = $Perfil.PerfilPasta
            NomeExibicao = $Perfil.NomeExibicao
            DestinoNuvem = $Destino
        }
        $Config.Mapeamentos = @($Config.Mapeamentos) + $Perfil.Mapeamento
    }
    Salvar-Configuracao $Config
}

function Garantir-Rclone {
    if (Get-Command rclone -ErrorAction SilentlyContinue) { return }
    if ((Read-Host 'Rclone nao encontrado. Instalar via Winget? (S/N)') -ne 'S') {
        throw 'Rclone necessario. Instale com: winget install --id Rclone.Rclone -e'
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'Winget nao encontrado.' }
    & winget install --id Rclone.Rclone -e --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "Falha na instalacao do Rclone (codigo $LASTEXITCODE)." }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
        throw 'Rclone ainda nao esta no PATH. Reabra o PowerShell.'
    }
}

function Obter-Remotos {
    $Remotos = @(& rclone listremotes)
    if ($LASTEXITCODE -ne 0) { throw "Falha ao consultar as contas do Rclone (codigo $LASTEXITCODE)." }
    return $Remotos
}

function Fazer-LoginOneDrive {
    param($Conta)
    Garantir-Rclone
    Write-Host "`nEntre na conta: $($Conta.NomeExibicao)" -ForegroundColor Cyan
    Write-Host 'Confira a conta Microsoft no navegador. Se necessario, saia da conta anterior antes de autorizar.'
    if (@(Obter-Remotos) -contains "$($Conta.Remote):") {
        & rclone config reconnect "$($Conta.Remote):"
    } else {
        & rclone config create $Conta.Remote onedrive --all --no-output
    }
    if ($LASTEXITCODE -ne 0) { throw "Login nao concluido para $($Conta.NomeExibicao) (codigo $LASTEXITCODE)." }
    if (@(Obter-Remotos) -notcontains "$($Conta.Remote):") {
        throw "A conta $($Conta.NomeExibicao) nao foi configurada."
    }
    Write-Host "Login concluido: $($Conta.NomeExibicao)." -ForegroundColor Green
}

function Sincronizar-Perfis {
    param([array]$Perfis, $Config, [ValidateSet('1', '2')][string]$Direcao)
    Garantir-Rclone
    foreach ($Perfil in $Perfis) {
        if ($Direcao -eq '1' -and -not $Perfil.Existe) {
            throw "O perfil $($Perfil.NomeExibicao) nao existe neste PC."
        }
        if (-not $Perfil.Mapeamento) {
            Write-Host "`nEscolha o destino de $($Perfil.Navegador) - $($Perfil.NomeExibicao)."
            $Conta = Selecionar-Conta $Config
            if (-not $Conta) { return }
            Vincular-Perfil $Perfil $Conta $Config
        }
    }
    $ContasUsadas = @($Perfis | ForEach-Object { ($_.Mapeamento.DestinoNuvem -split ':', 2)[0] } |
        Select-Object -Unique)
    $Remotos = @(Obter-Remotos)
    foreach ($Remote in $ContasUsadas) {
        $Conta = $Config.Contas | Where-Object { $_.Remote -eq $Remote }
        if (-not $Conta.Identificada -and -not (Identificar-Conta $Conta $Config)) { return }
        if ($Remotos -notcontains "${Remote}:") { Fazer-LoginOneDrive $Conta }
    }
    Write-Host "`nConfira a operacao:" -ForegroundColor Cyan
    $Acao = if ($Direcao -eq '1') { 'ENVIAR para' } else { 'BAIXAR de' }
    foreach ($Perfil in $Perfis) {
        $Remote = ($Perfil.Mapeamento.DestinoNuvem -split ':', 2)[0]
        $Conta = $Config.Contas | Where-Object { $_.Remote -eq $Remote }
        Write-Host " $($Perfil.Navegador) - $($Perfil.NomeExibicao): $Acao $($Conta.NomeExibicao)"
    }
    Write-Host 'ATENCAO: sincronizacao em uma direcao. Arquivos extras no destino serao APAGADOS.' -ForegroundColor Yellow
    Write-Host 'Os navegadores selecionados serao fechados. Salve seu trabalho antes de continuar.'
    if ((Read-Host 'Digite CONFIRMAR para continuar') -cne 'CONFIRMAR') {
        Write-Host 'Operacao cancelada. Nenhum navegador foi fechado ou arquivo sincronizado.'
        return
    }
    # Valida todas as origens remotas antes de fechar navegadores ou alterar dados locais.
    if ($Direcao -eq '2') {
        foreach ($Perfil in $Perfis) {
            & rclone lsf $Perfil.Mapeamento.DestinoNuvem --max-depth 1
            if ($LASTEXITCODE -ne 0) { throw "Backup indisponivel para $($Perfil.NomeExibicao). Restauracao cancelada." }
        }
    }
    foreach ($Navegador in ($Perfis.Navegador | Select-Object -Unique)) {
        $ProcessName = @{ Chrome = 'chrome'; Edge = 'msedge'; Vivaldi = 'vivaldi' }[$Navegador]
        $Processos = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
        foreach ($Processo in $Processos) {
            Stop-Process -Id $Processo.Id -Force -ErrorAction Stop
            if (-not $Processo.WaitForExit(15000)) {
                throw "O $Navegador nao foi encerrado. Sincronizacao cancelada."
            }
        }
    }
    $Exclusoes = @(
        '--exclude', 'Cache/**', '--exclude', 'Code Cache/**',
        '--exclude', 'GPUCache/**', '--exclude', 'DawnCache/**',
        '--exclude', 'GrShaderCache/**', '--exclude', 'ShaderCache/**',
        '--exclude', 'Service Worker/CacheStorage/**', '--exclude', 'Service Worker/ScriptCache/**'
    )
    foreach ($Perfil in $Perfis) {
        $Nuvem = $Perfil.Mapeamento.DestinoNuvem
        Write-Host "`n$Acao - $($Perfil.Navegador): $($Perfil.NomeExibicao)" -ForegroundColor Cyan
        $Argumentos = if ($Direcao -eq '1') {
            @('sync', $Perfil.CaminhoLocal, $Nuvem, '--progress')
        } else {
            @('sync', $Nuvem, $Perfil.CaminhoLocal, '--progress')
        }
        & rclone @Argumentos @Exclusoes
        if ($LASTEXITCODE -ne 0) {
            throw "Falha ao sincronizar $($Perfil.NomeExibicao) (codigo $LASTEXITCODE). Operacao interrompida; verifique os arquivos ja transferidos."
        }
    }
    Write-Host "`nSincronizacao concluida: $($Perfis.Count) perfil(is)." -ForegroundColor Green
}

function Iniciar-Sincronizador {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $Config = Ler-Configuracao
    while ($true) {
        Write-Host "`n=== SINCRONIZADOR DE NAVEGADORES / ONEDRIVE ===" -ForegroundColor Cyan
        Write-Host ' [1] Enviar perfis para o OneDrive'
        Write-Host ' [2] Restaurar perfis do OneDrive'
        Write-Host ' [V] Escolher ou trocar a conta de cada perfil'
        Write-Host ' [C] Dar nome as contas do OneDrive'
        Write-Host ' [L] Login em uma conta do OneDrive'
        Write-Host ' [S] Sair'
        $Acao = (Read-Host 'Escolha').Trim().ToUpperInvariant()
        if ($Acao -eq 'S') { return }
        if ($Acao -eq 'C') {
            $Opcoes = @($Config.Contas | ForEach-Object {
                [PSCustomObject]@{ Rotulo = $_.NomeExibicao; Conta = $_ }
            })
            $Escolhida = Selecionar-Itens $Opcoes 'Qual conta deseja identificar?'
            if ($Escolhida) { $null = Identificar-Conta $Escolhida.Conta $Config }
        } elseif ($Acao -eq 'L') {
            $Conta = Selecionar-Conta $Config
            if ($Conta) { Fazer-LoginOneDrive $Conta }
        } elseif ($Acao -in @('1', '2', 'V')) {
            $Perfis = @(Obter-Perfis $Config)
            if ($Acao -eq '1') { $Perfis = @($Perfis | Where-Object { $_.Existe }) }
            $Selecionados = @(Selecionar-Itens $Perfis 'Selecione os perfis pelo nome:' -Multiplo)
            if ($Selecionados.Count -eq 0) { continue }
            if ($Acao -eq 'V') {
                foreach ($Perfil in $Selecionados) {
                    Write-Host "`nConta para $($Perfil.Navegador) - $($Perfil.NomeExibicao)"
                    $Conta = Selecionar-Conta $Config
                    if (-not $Conta) { break }
                    Vincular-Perfil $Perfil $Conta $Config
                }
            } else {
                Sincronizar-Perfis $Selecionados $Config $Acao
            }
        } else {
            Write-Host 'Opcao invalida.' -ForegroundColor Yellow
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Iniciar-Sincronizador
    } catch {
        Write-Error "Sincronizador: $($_.Exception.Message)"
        exit 1
    }
}
