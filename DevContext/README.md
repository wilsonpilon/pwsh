# DevContext 0.1

Primeira versao do diagnostico nao destrutivo para o ambiente de desenvolvimento.

## Objetivos desta versao
- Exigir PowerShell 7+.
- Detectar Git, GitHub CLI (`gh`), VS Code (`code`), OpenSSH, Git Credential Manager e Copilot CLI quando disponiveis.
- Exibir `gh auth status` sem copiar tokens para arquivos do projeto.
- Descobrir os roots previstos: `C:\dos\pwsh`, `D:\dos\pwsh`, `E:\pwsh` e equivalentes `extra`.
- Criar apenas configuracao local em `%LOCALAPPDATA%\DevContext`.
- Reservar identidades `Personal`, `Enterprise` e `Extra`, deixando `Extra` marcado como isolado.

## Execucao
```powershell
pwsh -File .\DevContext.ps1 doctor
```

Saida JSON para diagnostico/testes:
```powershell
pwsh -File .\DevContext.ps1 doctor -Json
```

Outros comandos iniciais:
```powershell
pwsh -File .\DevContext.ps1 config
pwsh -File .\DevContext.ps1 identities
```

## Importante
A versao 0.1 nao altera configuracoes de Git, VS Code, SSH ou Copilot. Ela somente diagnostica o ambiente e cria os arquivos locais basicos do DevContext.
