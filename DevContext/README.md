# DevContext 0.2.1

Versao completa contendo: doctor, status, config, identities, identity-setup, identity-test e identity-verify.

## Identity verify

```powershell
pwsh -File .\DevContext.ps1 identity-verify
pwsh -File .\DevContext.ps1 identity-verify -Identity Enterprise
pwsh -File .\DevContext.ps1 identity-verify -Json
```

`identity-verify` executa SSH em `BatchMode=yes`, compara o cumprimento `Hi <account>!` do GitHub com `githubAccount` e tambem exige `isolated=true` para Extra. Nao faz push e nao altera Git, SSH, GitHub ou VS Code.

Estados: PASS, SSH_FAILED, IDENTITY_MISMATCH, ISOLATION_FAILED, NOT_CONFIGURED. O global so sera VERIFIED se todos os testes solicitados retornarem PASS.

Importante: o GitHub normalmente retorna exit code 1 em `ssh -T` mesmo apos autenticar, pois nao oferece shell. A verificacao usa a mensagem autenticada.

## Correcao de parser
Corrigido `return$v.Trim()` para `return $v.Trim()` e normalizadas chamadas de funcoes que haviam sido excessivamente compactadas.

## Segunda correcao do parser
Corrigido `foreach($name in$names)` para `foreach ($name in $names)` e normalizadas expressoes booleanas proximas ao comando `identity-verify`.

## Correcao de execucao do identity-verify
A expressao compactada `? Result-ne'PASS'` foi substituida por `Where-Object { $_.Result -ne 'PASS' }`. Tambem foram normalizados operadores de comparacao no fluxo de verificacao.
