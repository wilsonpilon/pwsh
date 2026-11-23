# BrowserProfileSync 0.2.6

Adiciona retencao real, habilitada somente quando `-Apply` for informado explicitamente.

## Simulacao padrao
Mantem 3 backups completos e nao apaga nada:
```powershell
pwsh -File .\BrowserProfileSync.ps1 retention
```

## Simulacao mantendo apenas 1
```powershell
pwsh -File .\BrowserProfileSync.ps1 retention -Keep 1
```

## Aplicar a retencao
O comando abaixo mantem o backup completo mais recente e exclui os completos mais antigos:
```powershell
pwsh -File .\BrowserProfileSync.ps1 retention -Keep 1 -Apply
```

## Travas de seguranca
- Sem `-Apply`, nunca exclui nada.
- `Keep` aceita somente valores de 1 a 999.
- Nunca seleciona o backup completo mais recente.
- Somente backups com `manifest.json` legivel e `Status=Complete` entram na retencao.
- Backups incompletos ou invalidos sao ignorados.
- Cada candidato deve ser filho direto do BackupRoot configurado.
- O nome do diretorio deve terminar em `-yyyyMMdd-HHmmss`.
- O BackupRoot nunca pode ser candidato.
- Apos `Remove-Item`, o script confirma que o diretorio deixou de existir.
- O inventario e executado novamente para informar quantos backups completos restaram.

Teste primeiro sem `-Apply`. Use `-Apply` somente depois de conferir as secoes `Will keep` e `Will remove`.
