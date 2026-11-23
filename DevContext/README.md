# DevContext 0.1.2

Doctor nao destrutivo para PowerShell 7 / Windows.

Melhorias da 0.1.2:
- `E:\pwsh` passa a ser ProjectRoot, sem duplicacao Personal/Enterprise.
- ExtraRoot permanece separado.
- Leitura estrutural de `~/.ssh/config`: Host, HostName, User e IdentityFile. O conteudo das chaves privadas nunca e lido.
- `gh auth status` passa a ser convertido em contas estruturadas e tokens nao sao registrados.
- Git Credential Manager e reconhecido pela configuracao `credential.helper=manager`.
- VS Code cruza `code --list-extensions` com `~/.vscode/extensions` e lista profiles fisicos.
- Copilot CLI identifica origem VSCodeShim.
- Readiness fornece `READY_FOR_IDENTITY_SETUP` quando o ambiente basico esta pronto.

Uso:

    pwsh -File .\DevContext.ps1 doctor
    pwsh -File .\DevContext.ps1 doctor -Json

A 0.1.2 continua em modo somente leitura para Git, GitHub, SSH, VS Code e Copilot. Somente `%LOCALAPPDATA%\DevContext` pode ser criado/atualizado para configuracao do proprio DevContext.
