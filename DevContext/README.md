# DevContext 0.3.0

Inclui os comandos das versoes anteriores e o novo `dev new`.

## Uso

```powershell
.\dev.ps1 new
```

Ou diretamente:

```powershell
pwsh -File .\DevContext.ps1 new
```

## Modelos

- Personal-Personal
- Personal-Enterprise
- Enterprise-Enterprise
- Enterprise-Personal
- Extra-Extra

## Modos de repositorio

- `Monorepo`: cria uma subpasta no ProjectRoot existente e nao executa `git init` dentro dela.
- `Standalone`: cria um repositorio independente, executa `git init` e configura `user.name` e `user.email` localmente.
- Extra-Extra exige `Standalone` e permanece fora do monorepo compartilhado.

## Arquivos gerados

- `.project-context.json`
- `.github/copilot-instructions.md`
- `.vscode/`
- `docs/`, `src/`, `tests/`, `tools/`
- `<Projeto>.code-workspace`
- `Start-Dev.ps1`
- `README.md`
- `.gitignore`

## Limite intencional da 0.3.0

A versao cria o projeto local e o workspace. Ela nao cria repositorio remoto, nao faz push e nao troca silenciosamente a conta autenticada do GitHub Copilot. O workspace declara a conta pretendida e o `Start-Dev.ps1` exige confirmacao visual no VS Code.

## 0.3.1 - compatibilidade de config
Corrige `Get-Roots` sob `Set-StrictMode`: a rotina nao acessa mais propriedades inexistentes diretamente. Ela detecta primeiro o schema do `%LOCALAPPDATA%\DevContext\config.json`, aceita tanto o formato legado 0.1/0.1.1 (`projectRoots`) quanto o formato atual (`projectRootCandidates` / `extraRootCandidates`) e usa defaults seguros quando necessario.
