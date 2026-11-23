# BrowserProfileSync 0.2.3

Novos backups gravam SHA-256 por arquivo no manifest.json. Backups antigos continuam verificaveis pelo metodo legado de contagem de arquivos e bytes.

## Novo backup
Feche Edge/Vivaldi e execute:
```powershell
pwsh -File .\BrowserProfileSync.ps1 backup
```

## Verify
```powershell
pwsh -File .\BrowserProfileSync.ps1 verify -Backup D:\BrowserProfileSync\XPS-YYYYMMDD-HHMMSS
```

Para backup 0.2.3, o resultado deve informar `SHA-256 + count + bytes` e aproximadamente 8.939 hashes no ambiente XPS atual.
