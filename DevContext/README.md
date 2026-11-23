# DevContext 0.3.2 Final

Versao final da sessao, reescrita sem minificacao intencional. Preserva `%LOCALAPPDATA%\DevContext\config.json` e `identities.json`.

## Validacao inicial

```powershell
.\dev.ps1 identity-test
.\dev.ps1 identity-verify
```

## Ajuste da conta Enterprise

```powershell
.\dev.ps1 identity-setup -Identity Enterprise
```

Use GitHub e GitHub Copilot `barneycindumel`.

## Corrigir o projeto existente sem recria-lo

```powershell
.\Update-BrowserProfileSync.ps1
```

O atualizador corrige `.project-context.json` e recria `Start-Dev.ps1`.
