# DevContext 0.2.0 - Identity Setup

Inclui o Doctor 0.1.2 e o cadastro local das identidades Personal, Enterprise e Extra.

## Comandos

```powershell
pwsh -File .\DevContext.ps1 doctor -Json
pwsh -File .\DevContext.ps1 identity-setup
pwsh -File .\DevContext.ps1 identity-setup -Identity Personal
pwsh -File .\DevContext.ps1 identities
pwsh -File .\DevContext.ps1 identity-test
pwsh -File .\DevContext.ps1 identity-test -Json
```

## O que e armazenado

- `user.name` e `user.email` pretendidos para cada contexto;
- alias SSH do GitHub;
- nome da conta GitHub;
- conta GitHub Copilot pretendida;
- disponibilidade planejada do Microsoft 365 Copilot;
- isolamento obrigatorio de Extra.

## O que nao e armazenado

- senhas;
- PATs;
- tokens OAuth;
- cookies;
- conteudo de chaves privadas;
- sessoes do VS Code ou GitHub CLI.

O arquivo fica em `%LOCALAPPDATA%\DevContext\identities.json`. Se existir o formato antigo da 0.1, ele e preservado com sufixo `.legacy-AAAAmmdd-HHmmss.json` antes da migracao.

A versao 0.2.0 cadastra a intencao das identidades, mas ainda nao altera Git, remotes, VS Code ou contas Copilot. Essas alteracoes pertencerao ao futuro comando `dev new`.
