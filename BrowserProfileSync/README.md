# BrowserProfileSync 0.2.1

Versao de teste com `doctor`, `backup` e `verify`.

## Novo em 0.2.1
O comando `verify` reabre um backup concluido e valida cada item contra `manifest.json`.

A verificacao desta versao usa os metadados que a 0.2.0 ja gravou no manifesto:
- existencia de cada item;
- quantidade de arquivos;
- total de bytes.

Isto permite verificar inclusive o primeiro backup `XPS-20261123-132616` criado pela 0.2.0.

> SHA-256 por arquivo ainda nao pode ser retroativamente validado no backup 0.2.0 porque os hashes nao existem no manifesto original. Uma versao futura pode gravar hashes durante o backup e usa-los no `verify`.

## Testar o backup existente
```powershell
pwsh -File .\BrowserProfileSync.ps1 verify `
    -Backup D:\BrowserProfileSync\XPS-20261123-132616
```

Resultado esperado:
```text
Verify                                  [PASS]
Files verified                          [INFO]
Data verified                           [INFO]
Integrity method                        [INFO]
```

## Teste de deteccao de alteracao
Depois de validar o backup original, faca uma COPIA da pasta de backup para testes. Nao altere o primeiro backup real. Se um arquivo for removido da copia, `verify` deve retornar FAIL.
