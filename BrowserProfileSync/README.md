# BrowserProfileSync 0.2.1 - pacote corrigido

Este pacote corrige o erro de sintaxe em tempo de execucao:

`O termo "return[pscustomobject]@" nao e reconhecido...`

## Verificar o backup criado pela 0.2.0

```powershell
pwsh -File .\BrowserProfileSync.ps1 verify `
    -Backup D:\BrowserProfileSync\XPS-20261123-132616
```

O comando `verify` valida cada entrada do `manifest.json` por existencia, quantidade de arquivos e total de bytes.
