# BrowserProfileSync 0.2.2

Adiciona configuracao persistente do destino de backup.

## Configurar uma vez
```powershell
pwsh -File .\BrowserProfileSync.ps1 config -Destination D:\BrowserProfileSync
```

O arquivo e salvo em `%APPDATA%\BrowserProfileSync\config.json`. O diretorio de destino deve existir. A configuracao nunca pode apontar para dentro de `User Data` de Edge, Chrome ou Vivaldi.

## Consultar a configuracao
```powershell
pwsh -File .\BrowserProfileSync.ps1 config
```

## Backup usando a configuracao
```powershell
pwsh -File .\BrowserProfileSync.ps1 backup
```

`backup -Destination <pasta>` continua disponivel e tem prioridade sobre a configuracao persistente.

## Verify
```powershell
pwsh -File .\BrowserProfileSync.ps1 verify -Backup D:\BrowserProfileSync\XPS-20261123-132616
```
