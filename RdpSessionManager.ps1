#requires -version 5.1

#Crie um atalho para este script e execute como Administrador para gerenciar sessões RDP (logoff). Ele lista as sessões ativas e desconectadas, permitindo logoff manual ou em lote (exceto para usuários root1/root2). Use com cuidado para evitar perda de dados não salvos.
# Em localizacao
# C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "d:\backup\RdpSessionManager.ps1"
# Em nome
# KillUser

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- AUTO ELEVAÇÃO (sem WinForms aqui em cima) ---
if (-not (Test-IsAdmin)) {
    # Determina o caminho do script de forma mais tolerante
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }

    if (-not $scriptPath) {
        Write-Error "Não foi possível determinar o caminho do script para auto-elevação. Execute como Administrador."
        exit 1
    }

    try {
        Start-Process -FilePath "powershell.exe" `
            -Verb RunAs `
            -ArgumentList @(
                "-NoProfile"
                "-ExecutionPolicy", "Bypass"
                "-File", "`"$scriptPath`""
            ) | Out-Null
    }
    catch {
        # Normalmente cai aqui quando o usuário clica "Não" no UAC ou política bloqueia
        Write-Error "Elevação negada ou falhou: $($_.Exception.Message)"
    }
    exit
}

# A partir daqui já estamos em admin; agora pode carregar WinForms normalmente
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-QuserRaw {
    # quser pode escrever em stdout e/ou stderr dependendo de contexto; capturamos ambos
    $out = & quser 2>&1
    return ,$out
}

function Parse-Quser {
    param([string[]]$RawLines)

    if (-not $RawLines -or $RawLines.Count -lt 2) { return @() }

    $lines = $RawLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Skip 1

    $result = New-Object System.Collections.Generic.List[object]

    foreach ($line in $lines) {
        # Remove marcador de sessão atual ">"
        $l = $line.Trim()
        if ($l.StartsWith('>')) { $l = $l.TrimStart('>').Trim() }

        # Normaliza múltiplos espaços
        $norm = ($l -replace '\s{2,}', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($norm)) { continue }

        $parts = $norm.Split(' ')
        if ($parts.Count -lt 3) { continue }

        # Detecta onde está o ID (número). Procuramos o primeiro token numérico.
        $idIndex = -1
        for ($i=0; $i -lt $parts.Count; $i++) {
            if ($parts[$i] -match '^\d+$') { $idIndex = $i; break }
        }
        if ($idIndex -lt 1) { continue } # precisa ter username antes do ID

        $user = $parts[0]

        # SessionName: tokens entre username e id (pode ser 0 ou 1 token; em geral é 1)
        $sessionName = ''
        if ($idIndex -gt 1) {
            $sessionName = ($parts[1..($idIndex-1)] -join ' ')
        }

        $id = [int]$parts[$idIndex]

        # State: normalmente vem logo após o ID
        $state = ''
        if ($parts.Count -gt ($idIndex+1)) {
            $state = $parts[$idIndex+1]
        }

        # Restante: idle + logon (se existirem)
        $idle = ''
        $logon = ''
        if ($parts.Count -gt ($idIndex+2)) {
            $idle = $parts[$idIndex+2]
        }
        if ($parts.Count -gt ($idIndex+3)) {
            $logon = ($parts[($idIndex+3)..($parts.Count-1)] -join ' ')
        }

        $isConnected = $false
        if ($state -match 'Active|Ativ') { $isConnected = $true } # cobre inglês/pt

        $result.Add([pscustomobject]@{
            UserName    = $user
            SessionName = $sessionName
            Id          = $id
            State       = $state
            IdleTime    = $idle
            LogonTime   = $logon
            IsConnected = $isConnected
        })
    }

    return $result
}

function Get-RdpSessions {
    $raw = Get-QuserRaw
    return (Parse-Quser -RawLines $raw)
}

function Invoke-LogoffSession {
    param([Parameter(Mandatory)][int]$SessionId)
    & logoff $SessionId 2>&1 | Out-Null
}

# ---------------- GUI ----------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "Gerenciador de Sessões RDP (Logoff)"
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1040, 600)
$form.MinimumSize = New-Object System.Drawing.Size(1040, 600)

$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = 'Top'
$topPanel.Height = 60
$form.Controls.Add($topPanel)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Atualizar"
$btnRefresh.Width = 110
$btnRefresh.Height = 34
$btnRefresh.Left = 10
$btnRefresh.Top = 13
$topPanel.Controls.Add($btnRefresh)

$btnShowQuser = New-Object System.Windows.Forms.Button
$btnShowQuser.Text = "Ver saída do quser"
$btnShowQuser.Width = 150
$btnShowQuser.Height = 34
$btnShowQuser.Left = 130
$btnShowQuser.Top = 13
$topPanel.Controls.Add($btnShowQuser)

$btnLogoffDisc = New-Object System.Windows.Forms.Button
$btnLogoffDisc.Text = "Logoff desconectados (exceto root1/root2)"
$btnLogoffDisc.Width = 360
$btnLogoffDisc.Height = 34
$btnLogoffDisc.Left = 290
$btnLogoffDisc.Top = 13
$topPanel.Controls.Add($btnLogoffDisc)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Left = 670
$lblStatus.Top = 20
$topPanel.Controls.Add($lblStatus)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly = $true
$grid.RowHeadersVisible = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.AutoGenerateColumns = $false
$form.Controls.Add($grid)

# Colunas fixas (sem DataBinding)
$grid.Columns.Clear() | Out-Null

function Add-TextCol([string]$name,[string]$header,[int]$fill=100) {
    $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c.Name = $name
    $c.HeaderText = $header
    $c.FillWeight = $fill
    [void]$grid.Columns.Add($c)
}

Add-TextCol -name "UserName"    -header "Usuário"      -fill 140
Add-TextCol -name "SessionName" -header "Sessão"       -fill 140
Add-TextCol -name "Id"          -header "ID"           -fill 60
Add-TextCol -name "State"       -header "Estado"       -fill 90
Add-TextCol -name "IsConnected" -header "Conectado?"   -fill 80
Add-TextCol -name "IdleTime"    -header "Idle"         -fill 80
Add-TextCol -name "LogonTime"   -header "Logon"        -fill 190

$btnCol = New-Object System.Windows.Forms.DataGridViewButtonColumn
$btnCol.Name = "Action"
$btnCol.HeaderText = "Ação"
$btnCol.Text = "Logoff"
$btnCol.UseColumnTextForButtonValue = $true
$btnCol.FillWeight = 80
[void]$grid.Columns.Add($btnCol)

# Guardar sessões carregadas (para ações)
$sessionsCache = @()

function Refresh-Grid {
    try {
        $grid.Rows.Clear()

        $sessions = @(Get-RdpSessions | Sort-Object -Property @{Expression="IsConnected";Descending=$true}, UserName, Id)
        $script:sessionsCache = $sessions

        foreach ($s in $sessions) {
            $idx = $grid.Rows.Add(
                $s.UserName,
                $s.SessionName,
                $s.Id,
                $s.State,
                ($s.IsConnected -as [bool]),
                $s.IdleTime,
                $s.LogonTime
            )

            # Opcional: pinta desconectados
            if ($s.State -match 'Disc|Descon') {
                $grid.Rows[$idx].DefaultCellStyle.ForeColor = [System.Drawing.Color]::DimGray
            }
        }

        $lblStatus.Text = "Sessões: $($sessions.Count) | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Falha ao listar sessões.`r`n$($_.Exception.Message)",
            "Erro",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

$btnRefresh.Add_Click({ Refresh-Grid })

$btnShowQuser.Add_Click({
    $raw = Get-QuserRaw
    $text = ($raw -join "`r`n")

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Saída do quser (diagnóstico)"
    $dlg.Size = New-Object System.Drawing.Size(900, 500)
    $dlg.StartPosition = 'CenterParent'

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true
    $tb.ScrollBars = 'Both'
    $tb.ReadOnly = $true
    $tb.Dock = 'Fill'
    $tb.Font = New-Object System.Drawing.Font("Consolas", 10)
    $tb.Text = $text
    $dlg.Controls.Add($tb)

    [void]$dlg.ShowDialog($form)
})

$grid.Add_CellContentClick({
    param($sender, $e)
    if ($e.RowIndex -lt 0) { return }
    if ($grid.Columns[$e.ColumnIndex].Name -ne "Action") { return }

    # Pega ID da linha
    $idCell = $grid.Rows[$e.RowIndex].Cells["Id"].Value
    if (-not $idCell) { return }
    $sessionId = [int]$idCell

    $user = [string]$grid.Rows[$e.RowIndex].Cells["UserName"].Value

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Confirmar LOGOFF do usuário '$user' (Sessão ID $sessionId)?`r`nIsso encerra a sessão e pode causar perda de trabalho não salvo.",
        "Confirmar logoff",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        Invoke-LogoffSession -SessionId $sessionId
        Start-Sleep -Milliseconds 400
        Refresh-Grid
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Falha ao efetuar logoff.`r`n$($_.Exception.Message)",
            "Erro",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

$btnLogoffDisc.Add_Click({
    $excluded = @('root1','root2')

    $sessions = @($script:sessionsCache)
    if (-not $sessions -or $sessions.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Não há sessões na lista.", "Info") | Out-Null
        return
    }

    $targets = $sessions | Where-Object {
        ($_.State -match 'Disc|Descon') -and
        ($excluded -notcontains $_.UserName)
    }

    if (-not $targets -or $targets.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Não há usuários desconectados elegíveis para logoff (excluindo root1/root2).",
            "Info"
        ) | Out-Null
        return
    }

    $list = ($targets | ForEach-Object { "$($_.UserName) (ID $($_.Id))" }) -join "`r`n"
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Confirmar LOGOFF das sessões desconectadas abaixo (exceto root1/root2)?`r`n`r`n$list",
        "Confirmar logoff em lote",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    foreach ($t in $targets) {
        try { Invoke-LogoffSession -SessionId ([int]$t.Id) } catch { }
    }

    Start-Sleep -Milliseconds 500
    Refresh-Grid
})

if (-not (Test-IsAdmin)) {
    $lblStatus.Text = "Atenção: rode como Administrador para efetuar logoff de outros usuários."
}

Refresh-Grid
[void]$form.ShowDialog()