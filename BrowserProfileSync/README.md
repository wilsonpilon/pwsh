# BrowserProfileSync 0.2.4

Adiciona os comandos de administracao `list` e `status`, mantendo Doctor, configuracao persistente, backup SHA-256 e verify.

## Listar backups
```powershell
pwsh -File .\BrowserProfileSync.ps1 list
```
Le o destino configurado e os `manifest.json`, mostrando versao que criou o backup, metodo de integridade, arquivos, tamanho e status. Pastas com `manifest.incomplete.json` sao marcadas como incompletas.

## Ver status rapido
```powershell
pwsh -File .\BrowserProfileSync.ps1 status
```
Mostra raiz configurada, quantidade de backups encontrados, backup mais recente, metodo de integridade, tamanho e estado dos processos Edge/Chrome/Vivaldi. `Next backup` fica READY somente se houver destino configurado e nenhum navegador suportado estiver rodando.

## Comandos
```text
doctor
config [-Destination caminho]
backup [-Destination caminho]
verify -Backup caminho
list
status
help
```
