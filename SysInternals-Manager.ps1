#Requires -Version 5.1
<#
.SYNOPSIS
    SysInternals Manager — Gerenciador da Suite SysInternals da Microsoft
.DESCRIPTION
    Interface em modo texto (TUI) para gerenciar, instalar e executar
    ferramentas da suite SysInternals da Microsoft.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ── Box-drawing characters (double-line) ──────────────────────────────────────
$BOX = @{
    TL = [string][char]0x2554   # ╔
    TR = [string][char]0x2557   # ╗
    BL = [string][char]0x255A   # ╚
    BR = [string][char]0x255D   # ╝
    HZ = [string][char]0x2550   # ═
    VT = [string][char]0x2551   # ║
    ML = [string][char]0x2560   # ╠
    MR = [string][char]0x2563   # ╣
}

# ── Paths & defaults ───────────────────────────────────────────────────────────
$ConfigPath    = Join-Path $env:APPDATA 'SysInternalsManager\config.json'
$DefaultConfig = @{
    InstallDirectory = 'C:\SysInternals'
    DownloadUrl      = 'https://download.sysinternals.com/files/SysinternalsSuite.zip'
}

# ── Config I/O ─────────────────────────────────────────────────────────────────
function Get-AppConfig {
    if (Test-Path $ConfigPath) {
        try {
            $j = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            return @{
                InstallDirectory = if ($j.InstallDirectory) { $j.InstallDirectory } else { $DefaultConfig.InstallDirectory }
                DownloadUrl      = if ($j.DownloadUrl)      { $j.DownloadUrl      } else { $DefaultConfig.DownloadUrl }
            }
        } catch { }
    }
    return @{
        InstallDirectory = $DefaultConfig.InstallDirectory
        DownloadUrl      = $DefaultConfig.DownloadUrl
    }
}

function Save-AppConfig ($Cfg) {
    $dir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Cfg | ConvertTo-Json | Set-Content $ConfigPath -Encoding UTF8
}

# ── UI Primitives ──────────────────────────────────────────────────────────────
function Write-At ([int]$X, [int]$Y, [string]$Text, [string]$Fg = 'White', [string]$Bg = 'Black') {
    [Console]::SetCursorPosition($X, $Y)
    Write-Host -NoNewline -ForegroundColor $Fg -BackgroundColor $Bg $Text
}

function Draw-Box ([int]$X, [int]$Y, [int]$W, [int]$H, [string]$Title = '', [string]$Bc = 'Cyan') {
    $iw = $W - 2
    Write-At $X $Y ($BOX.TL + ($BOX.HZ * $iw) + $BOX.TR) $Bc
    if ($Title) {
        $tx = $X + [int](($iw - $Title.Length) / 2)
        Write-At $tx $Y " $Title " 'Yellow' 'Black'
    }
    for ($r = 1; $r -lt ($H - 1); $r++) {
        Write-At $X            ($Y + $r) $BOX.VT $Bc
        Write-At ($X + 1)      ($Y + $r) (' ' * $iw)
        Write-At ($X + $W - 1) ($Y + $r) $BOX.VT $Bc
    }
    Write-At $X ($Y + $H - 1) ($BOX.BL + ($BOX.HZ * $iw) + $BOX.BR) $Bc
}

function Draw-HRule ([int]$X, [int]$Y, [int]$W, [string]$Bc = 'DarkCyan') {
    Write-At $X $Y ($BOX.ML + ($BOX.HZ * ($W - 2)) + $BOX.MR) $Bc
}

function Read-Key {
    [Console]::CursorVisible = $false
    return [Console]::ReadKey($true).KeyChar.ToString().ToUpper()
}

function Read-Field ([int]$X, [int]$Y, [string]$Current) {
    Write-At $X $Y (' ' * 70) 'White' 'DarkBlue'
    [Console]::SetCursorPosition($X, $Y)
    [Console]::CursorVisible = $true
    $val = Read-Host
    [Console]::CursorVisible = $false
    if ($val -and $val.Trim()) { return $val.Trim() }
    return $Current
}

# ── Screen: Main Menu ──────────────────────────────────────────────────────────
function Show-MainMenu ($Cfg) {
    [Console]::Clear()
    [Console]::CursorVisible = $false

    Draw-Box 0 0 78 24 '' 'Cyan'

    $t1 = 'SysInternals Manager'
    $t2 = 'Gerenciador da Suite SysInternals da Microsoft'
    Write-At (2 + [int]((74 - $t1.Length) / 2)) 1 $t1 'Cyan'
    Write-At (2 + [int]((74 - $t2.Length) / 2)) 2 $t2 'DarkGray'
    Draw-HRule 0 3 78

    $installed = Test-Path $Cfg.InstallDirectory
    Write-At  3 4 'Diretorio : ' 'DarkGray'
    Write-At 15 4 $Cfg.InstallDirectory 'White'
    Write-At  3 5 'Status    : ' 'DarkGray'
    if ($installed) {
        Write-At 15 5 '[ Instalado ]' 'Green'
    } else {
        Write-At 15 5 '[ Nao instalado ]' 'DarkYellow'
    }
    Draw-HRule 0 6 78

    $items = @(
        @{ K='1'; L='Configuracoes';                    D='Alterar diretorio de instalacao e URL de download' }
        @{ K='2'; L='Download / Instalar SysInternals'; D='Baixar e instalar/atualizar a suite SysInternals'  }
        @{ K='3'; L='Ferramentas';                      D='Navegar e executar as ferramentas instaladas'      }
    )
    $row = 8
    foreach ($it in $items) {
        Write-At  4 $row       " [$($it.K)] " 'Yellow'
        Write-At 11 $row       $it.L 'White'
        Write-At 11 ($row + 1) $it.D 'DarkGray'
        $row += 3
    }
    Write-At  4 $row ' [0] ' 'Red'
    Write-At 11 $row 'Sair' 'White'

    Draw-HRule 0 20 78
    Write-At 3 21 'Pressione a tecla correspondente a opcao desejada...' 'DarkGray'
    Write-At 3 22 'Aguardando: ' 'Cyan'

    return Read-Key
}

# ── Screen: Configuration ──────────────────────────────────────────────────────
function Show-ConfigScreen ($Cfg) {
    $w = @{
        InstallDirectory = $Cfg.InstallDirectory
        DownloadUrl      = $Cfg.DownloadUrl
    }

    while ($true) {
        [Console]::Clear()
        [Console]::CursorVisible = $false

        Draw-Box 0 0 78 24 ' CONFIGURACOES ' 'Cyan'
        Write-At 3 2 'Defina o diretorio de instalacao e a URL de download abaixo.' 'DarkGray'
        Draw-HRule 0 3 78

        # Field 1 — Diretório de Instalação
        Write-At 4 5 '[1]' 'Yellow'
        Write-At 8 5 'Diretorio de Instalacao' 'White'
        Write-At 5 6 'Caminho onde a suite sera instalada:' 'DarkGray'
        $dv = if ($w.InstallDirectory.Length -gt 68) { $w.InstallDirectory.Substring(0, 65) + '...' } else { $w.InstallDirectory }
        Write-At 5 7 " $dv " 'White' 'DarkBlue'
        if (Test-Path $w.InstallDirectory) {
            Write-At 5 8 '  [OK] Diretorio existe' 'Green'
        } else {
            Write-At 5 8 '  [--] Sera criado ao instalar' 'DarkYellow'
        }

        # Field 2 — URL de Download
        Write-At 4 11 '[2]' 'Yellow'
        Write-At 8 11 'URL de Download' 'White'
        Write-At 5 12 'Endereco para download do arquivo ZIP:' 'DarkGray'
        $uv = if ($w.DownloadUrl.Length -gt 68) { $w.DownloadUrl.Substring(0, 65) + '...' } else { $w.DownloadUrl }
        Write-At 5 13 " $uv " 'White' 'DarkBlue'

        Draw-HRule 0 16 78
        Write-At 4 18 '[1]' 'Yellow'; Write-At 8 18 'Editar Diretorio de Instalacao' 'White'
        Write-At 4 19 '[2]' 'Yellow'; Write-At 8 19 'Editar URL de Download'         'White'
        Write-At 4 20 '[S]' 'Green';  Write-At 8 20 'Salvar e Voltar'                'White'
        Write-At 4 21 '[C]' 'Red';    Write-At 8 21 'Cancelar sem Salvar'            'White'
        Write-At 3 22 'Aguardando: ' 'Cyan'

        $choice = Read-Key

        if ($choice -eq '1') {
            [Console]::Clear()
            Draw-Box 0 0 78 9 ' DIRETORIO DE INSTALACAO ' 'Cyan'
            Write-At 3 2 'Atual: ' 'DarkGray'
            Write-At 10 2 $w.InstallDirectory 'White'
            Write-At 3 4 'Novo diretorio (Enter para manter o atual):' 'Yellow'
            Write-At 3 5 '> ' 'Cyan'
            $w.InstallDirectory = Read-Field 5 5 $w.InstallDirectory
        }
        elseif ($choice -eq '2') {
            [Console]::Clear()
            Draw-Box 0 0 78 9 ' URL DE DOWNLOAD ' 'Cyan'
            Write-At 3 2 'Atual: ' 'DarkGray'
            Write-At 10 2 $w.DownloadUrl 'White'
            Write-At 3 4 'Nova URL (Enter para manter a atual):' 'Yellow'
            Write-At 3 5 '> ' 'Cyan'
            $w.DownloadUrl = Read-Field 5 5 $w.DownloadUrl
        }
        elseif ($choice -eq 'S') {
            Save-AppConfig $w
            Write-At 3 22 '  Configuracoes salvas com sucesso!  ' 'Black' 'Green'
            Start-Sleep -Milliseconds 1200
            return $w
        }
        elseif ($choice -eq 'C') {
            return $Cfg
        }
    }
}

# ── Helpers: Bytes & Progress Bar ─────────────────────────────────────────────
function Format-Bytes ([long]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Draw-ProgressBar ([int]$X, [int]$Y, [int]$W, [int]$Pct) {
    $fill  = [string][char]0x2588  # █
    $empty = [string][char]0x2591  # ░
    $f = [int]($W * [Math]::Max(0, [Math]::Min(100, $Pct)) / 100)
    $e = $W - $f
    Write-At $X $Y ($fill * $f) 'Cyan'
    if ($e -gt 0) { Write-At ($X + $f) $Y ($empty * $e) 'DarkGray' }
}

# ── Screen: Download / Install ─────────────────────────────────────────────────
function Show-DownloadScreen ($Cfg) {
    while ($true) {
        [Console]::Clear()
        [Console]::CursorVisible = $false

        Draw-Box 0 0 78 24 ' DOWNLOAD / INSTALAR SYSINTERNALS ' 'Cyan'
        Write-At 3 2 'Baixe e instale a suite SysInternals da Microsoft.' 'DarkGray'
        Draw-HRule 0 3 78

        Write-At 3 5 'Configuracao atual:' 'DarkGray'
        Write-At 3 6 'Diretorio : ' 'DarkGray'
        Write-At 15 6 $Cfg.InstallDirectory 'White'
        Write-At 3 7 'URL       : ' 'DarkGray'
        $u = $Cfg.DownloadUrl
        if ($u.Length -gt 60) { $u = $u.Substring(0, 57) + '...' }
        Write-At 15 7 $u 'White'

        $installed = Test-Path $Cfg.InstallDirectory
        if ($installed) {
            $count = (Get-ChildItem $Cfg.InstallDirectory -File -ErrorAction SilentlyContinue | Measure-Object).Count
            Write-At 3  9 "Instalacao detectada: $count arquivo(s) no diretorio." 'DarkYellow'
            Write-At 3 10 'Os arquivos existentes serao sobrescritos durante a atualizacao.' 'DarkGray'
        } else {
            Write-At 3  9 'Nenhuma instalacao detectada. O diretorio sera criado automaticamente.' 'DarkGray'
        }

        Draw-HRule 0 13 78
        Write-At 4 15 '[D]' 'Yellow'; Write-At 8 15 'Iniciar Download e Instalacao' 'White'
        Write-At 4 16 '[V]' 'Red';    Write-At 8 16 'Voltar ao Menu Principal'      'White'
        Write-At 3 22 'Aguardando: ' 'Cyan'

        switch (Read-Key) {
            'D' {
                Invoke-DownloadAndInstall $Cfg
                Write-At 3 22 ('Pressione qualquer tecla para voltar...'.PadRight(72)) 'DarkGray'
                [Console]::ReadKey($true) | Out-Null
                return
            }
            'V' { return }
        }
    }
}

function Invoke-DownloadAndInstall ($Cfg) {
    [Console]::Clear()
    [Console]::CursorVisible = $false
    Draw-Box 0 0 78 24 ' DOWNLOAD / INSTALACAO ' 'Cyan'
    Draw-HRule 0 3 78
    Draw-HRule 0 13 78
    Draw-HRule 0 20 78

    # Row constants used by nested helpers
    $RS = 5; $RB = 8; $RD = 10; $RL = 15

    Write-At 3 7 'Progresso:' 'DarkGray'
    Write-At 3 $RL       '  Etapa 1/3 — Download     [ Aguardando ]' 'DarkGray'
    Write-At 3 ($RL + 1) '  Etapa 2/3 — Diretorio    [ Aguardando ]' 'DarkGray'
    Write-At 3 ($RL + 2) '  Etapa 3/3 — Extracao     [ Aguardando ]' 'DarkGray'

    function Set-Step ([string]$Msg) {
        Write-At 3 $RS (' ' * 72)
        Write-At 3 $RS $Msg 'Yellow'
    }
    function Set-Bar ([int]$Pct) {
        Draw-ProgressBar 3 $RB 60 $Pct
        Write-At 64 $RB '        '
        Write-At 64 $RB " $Pct%" 'Cyan'
    }
    function Set-Detail ([string]$L1, [string]$L2 = '') {
        Write-At 3 $RD       (' ' * 72)
        Write-At 3 ($RD + 1) (' ' * 72)
        if ($L1) { Write-At 4 $RD       ($L1.Substring(0, [Math]::Min($L1.Length, 71))) 'DarkGray' }
        if ($L2) { Write-At 4 ($RD + 1) ($L2.Substring(0, [Math]::Min($L2.Length, 71))) 'DarkGray' }
    }
    function Set-Log ([int]$Step, [string]$Status, [string]$Color) {
        $labels = @('', 'Download    ', 'Diretorio   ', 'Extracao    ')
        Write-At 3  ($RL + $Step - 1) "  Etapa $Step/3 — $($labels[$Step])" 'DarkGray'
        Write-At 40 ($RL + $Step - 1) "[ $Status ]" $Color
    }

    $tempZip = Join-Path $env:TEMP 'SysinternalsSuite.zip'

    # ── Etapa 1: Download ──────────────────────────────────────────────────────
    Set-Step 'Etapa 1/3: Baixando SysinternalsSuite.zip...'
    Set-Bar 0
    Set-Detail "URL: $($Cfg.DownloadUrl)" "Destino temporario: $tempZip"

    $wc = $null
    try {
        $script:_dlPct  = 0
        $script:_dlRecv = [long]0
        $script:_dlTot  = [long]0
        $script:_dlDone = $false
        $script:_dlErr  = $null

        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (compatible; SysInternalsManager/1.0)')

        Register-ObjectEvent -InputObject $wc -EventName DownloadProgressChanged `
            -SourceIdentifier 'SIM_DLProgress' -Action {
                $script:_dlPct  = $event.SourceEventArgs.ProgressPercentage
                $script:_dlRecv = $event.SourceEventArgs.BytesReceived
                $script:_dlTot  = $event.SourceEventArgs.TotalBytesToReceive
            } | Out-Null

        Register-ObjectEvent -InputObject $wc -EventName DownloadFileCompleted `
            -SourceIdentifier 'SIM_DLComplete' -Action {
                $script:_dlDone = $true
                if ($event.SourceEventArgs.Error) {
                    $script:_dlErr = $event.SourceEventArgs.Error.Message
                }
            } | Out-Null

        $wc.DownloadFileAsync([Uri]$Cfg.DownloadUrl, $tempZip)

        while (-not $script:_dlDone) {
            Set-Bar $script:_dlPct
            if ($script:_dlTot -gt 0) {
                Set-Detail "Recebido: $(Format-Bytes $script:_dlRecv) de $(Format-Bytes $script:_dlTot)" `
                           "URL: $($Cfg.DownloadUrl)"
            } else {
                Set-Detail "Recebido: $(Format-Bytes $script:_dlRecv)..." "URL: $($Cfg.DownloadUrl)"
            }
            Start-Sleep -Milliseconds 150
        }
    } catch {
        $script:_dlErr  = $_.ToString()
        $script:_dlDone = $true
    } finally {
        Unregister-Event -SourceIdentifier 'SIM_DLProgress' -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier 'SIM_DLComplete' -ErrorAction SilentlyContinue
        Get-Job -Name 'SIM_DLProgress' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
        Get-Job -Name 'SIM_DLComplete' -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
        if ($null -ne $wc) { $wc.Dispose() }
    }

    if ($script:_dlErr) {
        Set-Step "ERRO no download: $($script:_dlErr)"
        Set-Log 1 'ERRO' 'Red'
        Write-At 3 21 ($script:_dlErr.Substring(0, [Math]::Min($script:_dlErr.Length, 72))) 'Red'
        Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        return
    }

    Set-Bar 100
    $zipSize = (Get-Item $tempZip -ErrorAction SilentlyContinue).Length
    Set-Detail "Download concluido: $(Format-Bytes $zipSize)" ''
    Set-Log 1 ' OK ' 'Green'

    # ── Etapa 2: Criar diretório ───────────────────────────────────────────────
    Set-Step 'Etapa 2/3: Preparando diretorio de instalacao...'
    try {
        if (-not (Test-Path $Cfg.InstallDirectory)) {
            New-Item -ItemType Directory -Path $Cfg.InstallDirectory -Force | Out-Null
        }
        Set-Log 2 ' OK ' 'Green'
    } catch {
        Set-Step "ERRO ao criar diretorio: $_"
        Set-Log 2 'ERRO' 'Red'
        Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        return
    }

    # ── Etapa 3: Extrair ───────────────────────────────────────────────────────
    Set-Step 'Etapa 3/3: Descompactando arquivos...'
    Set-Bar 0

    $zip = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip     = [System.IO.Compression.ZipFile]::OpenRead($tempZip)
        $entries = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
        $total   = $entries.Count
        $i       = 0

        foreach ($entry in $entries) {
            $i++
            $pct      = [int]($i * 100 / $total)
            $destPath = Join-Path $Cfg.InstallDirectory $entry.FullName
            $destDir  = Split-Path $destPath -Parent

            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destPath, $true)

            Set-Bar $pct
            Set-Detail "  $i de $total : $($entry.Name)" ''
        }

        $zip.Dispose()
        $zip = $null
        Set-Log 3 ' OK ' 'Green'

    } catch {
        if ($null -ne $zip) { try { $zip.Dispose() } catch {} }
        Set-Step "ERRO na extracao: $_"
        Set-Log 3 'ERRO' 'Red'
        return
    } finally {
        Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    }

    # ── Concluído ──────────────────────────────────────────────────────────────
    Set-Bar 100
    Set-Step 'Instalacao concluida com sucesso!'
    $fc = (Get-ChildItem $Cfg.InstallDirectory -File -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-At 3 21 "Suite SysInternals instalada: $fc ferramenta(s)" 'Green'
    Write-At 3 22 "  Diretorio: $($Cfg.InstallDirectory)" 'White'
}

# ── Screen: Coming Soon (placeholder) ─────────────────────────────────────────
function Show-ComingSoon ([string]$Title) {
    [Console]::Clear()
    [Console]::CursorVisible = $false
    Draw-Box 0 0 78 12 " $Title " 'Cyan'
    $msg = 'Esta funcionalidade sera implementada em breve.'
    Write-At (2 + [int]((74 - $msg.Length) / 2)) 5 $msg 'Yellow'
    Write-At 3 9 'Pressione qualquer tecla para voltar ao menu principal...' 'DarkGray'
    [Console]::ReadKey($true) | Out-Null
}

# ── Entry Point ────────────────────────────────────────────────────────────────
function Start-Manager {
    try { if ([Console]::WindowWidth  -lt 80) { [Console]::WindowWidth  = 80 } } catch { }
    try { if ([Console]::WindowHeight -lt 25) { [Console]::WindowHeight = 25 } } catch { }

    $config  = Get-AppConfig
    $running = $true

    try {
        while ($running) {
            $choice = Show-MainMenu $config
            if     ($choice -eq '1') { $config = Show-ConfigScreen $config }
            elseif ($choice -eq '2') { Show-DownloadScreen $config }
            elseif ($choice -eq '3') { Show-ComingSoon 'Ferramentas SysInternals' }
            elseif ($choice -eq '0') { $running = $false }
        }
    } finally {
        [Console]::Clear()
        [Console]::CursorVisible = $true
        Write-Host 'SysInternals Manager encerrado.' -ForegroundColor Cyan
    }
}

Start-Manager
