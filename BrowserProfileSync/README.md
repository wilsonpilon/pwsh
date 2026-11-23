# BrowserProfileSync 0.2.0

Primeira versao de teste com backup real para Edge, Chrome e Vivaldi.

## Seguranca
- `doctor` continua somente leitura.
- `backup` bloqueia se algum navegador suportado estiver em execucao.
- O diretorio-base de destino deve existir.
- Cada execucao cria uma nova pasta `<COMPUTADOR>-yyyyMMdd-HHmmss`.
- Backups anteriores nunca sao sobrescritos ou apagados.
- Falhas preservam a pasta parcial e geram `manifest.incomplete.json`.
- Restore ainda nao existe.

## Teste
```powershell
New-Item -ItemType Directory -Path D:\BrowserProfileSync -Force
pwsh -File .\BrowserProfileSync.ps1 backup -Destination D:\BrowserProfileSync
```

Primeiro teste com Edge/Vivaldi abertos: deve bloquear sem copiar. Depois feche-os, confirme com `Get-Process msedge,chrome,vivaldi -ErrorAction SilentlyContinue` e execute novamente.

A verificacao 0.2.0 compara quantidade de arquivos e total de bytes de cada item. Hash criptografico fica para o futuro comando `verify`.
