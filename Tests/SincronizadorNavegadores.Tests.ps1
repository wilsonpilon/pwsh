# Testes offline: executar com pwsh -NoProfile -File .\Tests\SincronizadorNavegadores.Tests.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'SincronizadorNavegadores.ps1')
$Modelo = [PSCustomObject]@{
    Contas = @(
        [PSCustomObject]@{ Remote = 'onedrive_pessoal_1'; NomeExibicao = 'OneDrive pessoal 1'; Identificada = $true }
        [PSCustomObject]@{ Remote = 'onedrive_pessoal_2'; NomeExibicao = 'OneDrive pessoal 2'; Identificada = $true }
        [PSCustomObject]@{ Remote = 'onedrive_profissional'; NomeExibicao = 'OneDrive profissional'; Identificada = $true }
    )
    Mapeamentos = @(foreach ($Navegador in @('Chrome', 'Edge', 'Vivaldi')) {
        foreach ($Item in @(
            @('Default', 'Principal', 'onedrive_pessoal_1', 'Default'),
            @('Profile 1', 'Profissional', 'onedrive_profissional', 'Profissional'),
            @('Profile 2', 'Projeto', 'onedrive_pessoal_2', 'Projeto')
        )) {
            [PSCustomObject]@{
                Navegador = $Navegador
                PerfilPasta = $Item[0]
                NomeExibicao = $Item[1]
                DestinoNuvem = "$($Item[2]):Backups_Navegadores/$Navegador/$($Item[3])"
            }
        }
    })
}
$Temporario = Join-Path ([IO.Path]::GetTempPath()) "Sincronizador-Testes-$([guid]::NewGuid())"
$null = New-Item -ItemType Directory -Path $Temporario
$ConfigFile = Join-Path $Temporario 'config.json'
$CaminhosBase = @{
    Chrome = Join-Path $Temporario 'Chrome'
    Edge = Join-Path $Temporario 'Edge'
    Vivaldi = Join-Path $Temporario 'Vivaldi'
}
$script:Falhas = 0
$script:Total = 0
$script:Respostas = [Collections.Generic.Queue[string]]::new()
$script:Chamadas = [Collections.Generic.List[object]]::new()
$script:CodigoSync = 0
$script:CodigoLista = 0
$script:CodigoOrigem = 0
$script:Fechamentos = 0
$script:Processos = @()
$script:Encerrado = $true
$script:Remotos = @()

function Read-Host {
    param($Prompt)
    if ($script:Respostas.Count -eq 0) { throw "Entrada de teste ausente: $Prompt" }
    return $script:Respostas.Dequeue()
}

function rclone {
    $script:Chamadas.Add(@($args))
    $script:LASTEXITCODE = 0
    switch ($args[0]) {
        'listremotes' {
            $script:LASTEXITCODE = $script:CodigoLista
            $script:Remotos
        }
        'config' {
            if ($args[1] -eq 'create') { $script:Remotos += "$($args[2]):" }
        }
        'sync' { $script:LASTEXITCODE = $script:CodigoSync }
        'lsf' { $script:LASTEXITCODE = $script:CodigoOrigem }
    }
}

function Get-Process { param($Name, $ErrorAction); $script:Processos }
function Stop-Process { param($Id, [switch]$Force, $ErrorAction); $script:Fechamentos++ }

function Verificar {
    param([bool]$Condicao, [string]$Mensagem)
    if (-not $Condicao) { throw $Mensagem }
}

function Esperar-Erro {
    param([scriptblock]$Acao, [string]$Trecho)
    $Mensagem = $null
    try { $null = & $Acao } catch { $Mensagem = $_.Exception.Message }
    Verificar ($null -ne $Mensagem -and $Mensagem -like "*$Trecho*") "Erro esperado: $Trecho; recebido: $Mensagem"
}

function Testar {
    param([string]$Nome, [scriptblock]$Acao)
    $script:Total++
    $script:Respostas.Clear()
    $script:Chamadas.Clear()
    $script:CodigoSync = 0
    $script:CodigoLista = 0
    $script:CodigoOrigem = 0
    $script:Processos = @()
    $script:Encerrado = $true
    $script:Remotos = @('onedrive_pessoal_1:', 'onedrive_pessoal_2:', 'onedrive_profissional:')
    try {
        & $Acao
        Write-Host "PASSOU: $Nome" -ForegroundColor Green
    } catch {
        $script:Falhas++
        Write-Host "FALHOU: $Nome - $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Nova-Configuracao {
    $Config = $Modelo | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    foreach ($Conta in $Config.Contas) { $Conta.Identificada = $true }
    return $Config
}

try {
    $Pasta = Join-Path $CaminhosBase.Chrome 'Profile 7'
    $null = New-Item -ItemType Directory -Path $Pasta -Force
    @{
        profile = @{
            info_cache = @{
                'Profile 7' = @{ name = 'Projeto de teste'; user_name = 'perfil@example.invalid' }
                'Default' = @{ name = 'Principal real' }
            }
        }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $CaminhosBase.Chrome 'Local State') -Encoding UTF8

    Testar 'Descobre perfil novo, nome real, email e conta amigavel' {
        $Config = Nova-Configuracao
        $Config.Contas[0].NomeExibicao = 'Conta de backup'
        $Perfis = @(Obter-Perfis $Config)
        $Novo = $Perfis | Where-Object { $_.PerfilPasta -eq 'Profile 7' }
        Verificar ($Novo.NomeExibicao -eq 'Projeto de teste' -and $Novo.Existe) 'Perfil novo nao descoberto.'
        Verificar ($Novo.Rotulo -like '*perfil@example.invalid*') 'Email ausente.'
        $Principal = $Perfis | Where-Object { $_.Navegador -eq 'Chrome' -and $_.PerfilPasta -eq 'Default' }
        Verificar ($Principal.Rotulo -like '*Principal real*Conta de backup*') 'Nome real ou conta ausente.'
        Verificar (-not $Principal.Existe) 'Perfil ausente marcado como existente.'
        Verificar ($Principal.Rotulo -notlike '*onedrive_pessoal_1*') 'Codigo interno exibido.'
    }

    Testar 'Preserva perfis configurados ausentes para restauracao' {
        $Perfis = @(Obter-Perfis (Nova-Configuracao))
        Verificar (@($Perfis | Where-Object { -not $_.Existe -and $_.Mapeamento }).Count -eq 9) 'Mapeamentos antigos perdidos.'
    }

    Testar 'Migra configuracao antiga sem perder destinos' {
        $Antiga = Nova-Configuracao
        $Destino = $Antiga.Mapeamentos[0].DestinoNuvem
        $Antiga.PSObject.Properties.Remove('Contas')
        Salvar-Configuracao $Antiga
        $Migrada = Ler-Configuracao
        Verificar (@($Migrada.Contas).Count -eq 3) 'Contas nao migradas.'
        Verificar ($Migrada.Mapeamentos[0].DestinoNuvem -eq $Destino) 'Destino antigo alterado.'
    }

    Testar 'Selecao multipla rejeita texto, zero e estouro sem encerrar' {
        foreach ($Resposta in @('abc', '0', '9999999999999999999999', '1,2,1')) {
            $script:Respostas.Enqueue($Resposta)
        }
        $Escolhidos = @(Selecionar-Itens @(
            [PSCustomObject]@{ Rotulo = 'Um' }, [PSCustomObject]@{ Rotulo = 'Dois' }
        ) 'Perfis' -Multiplo)
        Verificar ($Escolhidos.Count -eq 2) 'Selecao invalida ou duplicada.'
    }

    Testar 'Identificacao da conta e vinculo novo persistem sem mudar outros perfis' {
        $Config = Nova-Configuracao
        $Conta = $Config.Contas[1]
        $script:Respostas.Enqueue('Backup pessoal secundario')
        $null = Identificar-Conta $Conta $Config
        $Novo = Obter-Perfis $Config | Where-Object { $_.PerfilPasta -eq 'Profile 7' }
        Vincular-Perfil $Novo $Conta $Config
        $Lida = Ler-Configuracao
        Verificar ($Lida.Contas[1].NomeExibicao -eq 'Backup pessoal secundario') 'Nome nao salvo.'
        Verificar ($Lida.Mapeamentos.Count -eq 10) 'Mapeamentos perdidos.'
        Verificar ($Novo.Mapeamento.DestinoNuvem -eq 'onedrive_pessoal_2:Backups_Navegadores/Chrome/Profile 7') 'Destino incorreto.'
    }

    Testar 'Troca de conta preserva subpasta antiga' {
        $Config = Nova-Configuracao
        $Perfil = Obter-Perfis $Config | Where-Object { $_.Navegador -eq 'Chrome' -and $_.PerfilPasta -eq 'Profile 1' }
        Vincular-Perfil $Perfil $Config.Contas[1] $Config
        Verificar ($Perfil.Mapeamento.DestinoNuvem -eq 'onedrive_pessoal_2:Backups_Navegadores/Chrome/Profissional') 'Subpasta antiga alterada.'
    }

    Testar 'Primeira escolha exige identificacao da conta pelo nome' {
        $Config = Nova-Configuracao
        $Config.Contas[1].Identificada = $false
        $script:Respostas.Enqueue('2')
        $script:Respostas.Enqueue('Conta secundaria de teste')
        $Conta = Selecionar-Conta $Config
        Verificar ($Conta.Remote -eq 'onedrive_pessoal_2' -and $Conta.Identificada) 'Conta selecionada incorreta.'
        Verificar ((Ler-Configuracao).Contas[1].NomeExibicao -eq 'Conta secundaria de teste') 'Identificacao nao persistiu.'
    }

    Testar 'Login cria somente a conta escolhida e depois permite reconectar' {
        $Config = Nova-Configuracao
        $script:Remotos = @()
        Fazer-LoginOneDrive $Config.Contas[2]
        $Criacao = @($script:Chamadas | Where-Object { $_[0] -eq 'config' })[0]
        Verificar ($Criacao[1] -eq 'create' -and $Criacao[2] -eq 'onedrive_profissional') 'Conta incorreta na criacao.'
        Verificar ($Criacao -contains '--all' -and $Criacao -contains '--no-output') 'Assistente de criacao incorreto.'
        $script:Chamadas.Clear()
        Fazer-LoginOneDrive $Config.Contas[2]
        $Reconexao = @($script:Chamadas | Where-Object { $_[0] -eq 'config' })[0]
        Verificar ($Reconexao[1] -eq 'reconnect' -and $Reconexao[2] -eq 'onedrive_profissional:') 'Reconexao incorreta.'
    }

    Testar 'Rejeita destinos compartilhados e pastas fora da raiz' {
        $Config = Nova-Configuracao
        $Config.Mapeamentos[1].DestinoNuvem = $Config.Mapeamentos[0].DestinoNuvem
        Salvar-Configuracao $Config
        Esperar-Erro { Ler-Configuracao } 'destino compartilhado'
        $Config = Nova-Configuracao
        $Config.Mapeamentos[0].PerfilPasta = '..\Outro'
        Salvar-Configuracao $Config
        Esperar-Erro { Ler-Configuracao } 'Mapeamento invalido'
    }

    Testar 'Cancelamento nao sincroniza nem fecha navegadores' {
        $Config = Nova-Configuracao
        $Perfil = Obter-Perfis $Config | Where-Object { $_.Navegador -eq 'Chrome' -and $_.PerfilPasta -eq 'Default' }
        $script:Respostas.Enqueue('N')
        Sincronizar-Perfis @($Perfil) $Config '2'
        Verificar (@($script:Chamadas | Where-Object { $_[0] -eq 'sync' }).Count -eq 0) 'Sync executado sem confirmacao.'
        Verificar ($script:Fechamentos -eq 0) 'Navegador fechado sem confirmacao.'
    }

    Testar 'Upload preserva espacos nos argumentos e filtros de cache' {
        $Config = Nova-Configuracao
        $Perfil = Obter-Perfis $Config | Where-Object { $_.PerfilPasta -eq 'Profile 7' }
        Vincular-Perfil $Perfil $Config.Contas[0] $Config
        $script:Respostas.Enqueue('CONFIRMAR')
        Sincronizar-Perfis @($Perfil) $Config '1'
        $Chamada = @($script:Chamadas | Where-Object { $_[0] -eq 'sync' })[0]
        Verificar ($Chamada[1] -eq $Perfil.CaminhoLocal) 'Origem dividida ou com aspas extras.'
        Verificar ($Chamada[2] -eq $Perfil.Mapeamento.DestinoNuvem) 'Destino incorreto.'
        Verificar ($Chamada -contains 'Code Cache/**') 'Filtro removido.'
    }

    Testar 'Download inverte origem e destino e verifica backup antes' {
        $Config = Nova-Configuracao
        $Perfil = Obter-Perfis $Config | Where-Object { $_.Navegador -eq 'Chrome' -and $_.PerfilPasta -eq 'Default' }
        $script:Respostas.Enqueue('CONFIRMAR')
        Sincronizar-Perfis @($Perfil) $Config '2'
        $Sync = @($script:Chamadas | Where-Object { $_[0] -eq 'sync' })[0]
        Verificar ($Sync[1] -eq $Perfil.Mapeamento.DestinoNuvem -and $Sync[2] -eq $Perfil.CaminhoLocal) 'Direcao incorreta.'
        Verificar ($script:Chamadas[1][0] -eq 'lsf') 'Origem nao verificada antes do sync.'
    }

    Testar 'Falha ao consultar conta e backup ausente bloqueiam sync' {
        $script:CodigoLista = 9
        Esperar-Erro { Obter-Remotos } 'codigo 9'
        $script:CodigoLista = 0
        $script:CodigoOrigem = 3
        $Config = Nova-Configuracao
        $Perfil = Obter-Perfis $Config | Where-Object { $_.Navegador -eq 'Chrome' -and $_.PerfilPasta -eq 'Default' }
        $script:Respostas.Enqueue('CONFIRMAR')
        Esperar-Erro { Sincronizar-Perfis @($Perfil) $Config '2' } 'Backup indisponivel'
        Verificar (@($script:Chamadas | Where-Object { $_[0] -eq 'sync' }).Count -eq 0) 'Sync executado sem origem valida.'
    }

    Testar 'Falha do rclone interrompe operacao com erro' {
        $Config = Nova-Configuracao
        $Perfil = Obter-Perfis $Config | Where-Object { $_.Navegador -eq 'Chrome' -and $_.PerfilPasta -eq 'Default' }
        $script:CodigoSync = 5
        $script:Respostas.Enqueue('CONFIRMAR')
        Esperar-Erro { Sincronizar-Perfis @($Perfil) $Config '2' } 'codigo 5'
    }

    Testar 'So sincroniza depois de encerrar o navegador pelo ID' {
        $Config = Nova-Configuracao
        $Perfil = Obter-Perfis $Config | Where-Object { $_.Navegador -eq 'Chrome' -and $_.PerfilPasta -eq 'Default' }
        $Processo = [PSCustomObject]@{ Id = 987654321 }
        $Processo | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
            param($Timeout)
            return $script:Encerrado
        }
        $script:Processos = @($Processo)
        $script:Encerrado = $false
        $script:Respostas.Enqueue('CONFIRMAR')
        Esperar-Erro { Sincronizar-Perfis @($Perfil) $Config '2' } 'nao foi encerrado'
        Verificar (@($script:Chamadas | Where-Object { $_[0] -eq 'sync' }).Count -eq 0) 'Sync executado com navegador aberto.'
        $script:Encerrado = $true
        $script:Respostas.Enqueue('CONFIRMAR')
        Sincronizar-Perfis @($Perfil) $Config '2'
        Verificar (@($script:Chamadas | Where-Object { $_[0] -eq 'sync' }).Count -eq 1) 'Sync nao executado apos encerramento.'
    }

    Testar 'Local State invalido apresenta erro explicito' {
        $null = New-Item -ItemType Directory -Path $CaminhosBase.Edge -Force
        'JSON invalido' | Set-Content -LiteralPath (Join-Path $CaminhosBase.Edge 'Local State') -Force
        Esperar-Erro { Obter-Perfis (Nova-Configuracao) } 'Nao foi possivel ler'
    }
} finally {
    Remove-Item -LiteralPath $Temporario -Recurse -Force
}

Write-Host "`n$($script:Total - $script:Falhas)/$script:Total testes passaram."
if ($script:Falhas -gt 0) { exit 1 }
