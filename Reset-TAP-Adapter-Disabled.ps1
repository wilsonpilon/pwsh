function Invoke-TapAdapterRepair {
	Write-Host ''
	Write-Host '--- Reparar adaptadores TAP / OpenVPN ---' -ForegroundColor Cyan
	Write-Host 'Use quando o OpenVPN indicar que o adaptador TAP esta desabilitado ou indisponivel.'
	Write-Host 'Esta opcao nao repara adaptadores Wintun ou OpenVPN DCO.'

	try {
		$adapters = @(Get-NetAdapter -ErrorAction Stop |
			Where-Object { $_.InterfaceDescription -match 'TAP' })
	}
	catch {
		Write-Host "Nao foi possivel consultar os adaptadores: $($_.Exception.Message)" -ForegroundColor Red
		return
	}

	if ($adapters.Count -eq 0) {
		Write-Host 'Nenhum adaptador TAP encontrado. Verifique a instalacao do driver do OpenVPN.' -ForegroundColor Yellow
		return
	}

	$adapters | Select-Object Name, InterfaceDescription, Status | Format-Table -AutoSize | Out-Host
	Write-Host '[1] Habilitar TAP (sem desabilitar antes)'
	Write-Host '[2] Resetar TAP (desabilitar e habilitar novamente)'
	Write-Host '[0] Cancelar e voltar'

	$operation = (Read-Host 'Escolha uma opcao [0]').Trim()
	if ($operation -notin @('1', '2')) {
		Write-Host 'Operacao cancelada. Nenhuma alteracao realizada.' -ForegroundColor Yellow
		return
	}

	Write-Host ''
	Write-Host 'Desconecte o OpenVPN antes de continuar.' -ForegroundColor Yellow
	Write-Host 'A operacao afetara TODOS os adaptadores TAP listados e pode interromper conexoes VPN.' -ForegroundColor Yellow
	$action = if ($operation -eq '1') { 'HABILITAR' } else { 'RESETAR' }
	Write-Host "Confirmar: $action os adaptadores acima?"
	$confirmation = (Read-Host '[C] Confirmar / [Enter ou outra tecla] Cancelar').Trim()
	if ($confirmation -ine 'C') {
		Write-Host 'Operacao cancelada. Nenhuma alteracao realizada.' -ForegroundColor Yellow
		return
	}

	$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
	try {
		$principal = [Security.Principal.WindowsPrincipal]::new($identity)
		$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	}
	finally {
		$identity.Dispose()
	}

	if (-not $isAdministrator) {
		Write-Host 'Permissao insuficiente. Abra o PowerShell como Administrador e execute o utilitario novamente.' -ForegroundColor Red
		Write-Host 'Nenhuma alteracao realizada.'
		return
	}

	$successCount = 0
	foreach ($adapter in $adapters) {
		Write-Host ''
		Write-Host "Processando: $($adapter.Name)" -ForegroundColor Cyan
		if ($operation -eq '2') {
			try {
				$adapter | Disable-NetAdapter -Confirm:$false -ErrorAction Stop
			}
			catch {
				Write-Host "Falha ao desabilitar: $($_.Exception.Message)" -ForegroundColor Red
				Write-Host 'Ainda sera feita uma tentativa de habilitar este adaptador.' -ForegroundColor Yellow
			}
		}

		try {
			$adapter | Enable-NetAdapter -Confirm:$false -ErrorAction Stop
			$successCount++
			Write-Host 'Comando de habilitacao concluido.' -ForegroundColor Green
		}
		catch {
			Write-Host "Falha ao habilitar: $($_.Exception.Message)" -ForegroundColor Red
			Write-Host 'O adaptador pode continuar desabilitado. Habilite-o manualmente nas conexoes de rede.' -ForegroundColor Yellow
		}
	}

	Write-Host ''
	Write-Host "Habilitacao concluida em $successCount de $($adapters.Count) adaptador(es)."
	Write-Host 'Se a habilitacao foi concluida, tente conectar o OpenVPN novamente.'
}

function Start-VpnTroubleshooter {
	Write-Host ''
	Write-Host '============================================' -ForegroundColor Cyan
	Write-Host '       UTILITARIO DE SUPORTE A VPN' -ForegroundColor Cyan
	Write-Host '============================================' -ForegroundColor Cyan
	Write-Host 'Diagnostico e reparos de conexoes VPN no Windows.'
	Write-Host 'As alteracoes de rede exigem confirmacao e permissao de Administrador.'

	while ($true) {
		Write-Host ''
		Write-Host '--- Menu principal ---' -ForegroundColor Cyan
		Write-Host '[1] OpenVPN: habilitar ou resetar adaptadores TAP'
		Write-Host '[0] Sair'
		$option = (Read-Host 'Escolha uma opcao [0]').Trim()

		switch ($option) {
			'1' { Invoke-TapAdapterRepair }
			'0' { return }
			'' { return }
			default { Write-Host 'Opcao invalida. Escolha uma das opcoes do menu.' -ForegroundColor Yellow }
		}
	}
}

if ($MyInvocation.InvocationName -ne '.') {
	Start-VpnTroubleshooter
}