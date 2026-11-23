# DevContext 0.3.2 Final - Manual de Uso

## 1. Objetivo

O DevContext organiza projetos de desenvolvimento no Windows com PowerShell 7, separando explicitamente:

- identidade Git/GitHub usada pelo repositorio;
- identidade pretendida do GitHub Copilot no VS Code;
- disponibilidade do Microsoft 365 Copilot;
- contexto Personal, Enterprise ou Extra;
- projetos dentro do monorepo `pwsh` ou em repositorios Standalone.

O DevContext nao armazena senhas, PATs, tokens OAuth, cookies, chaves privadas ou bancos de autenticacao do VS Code.

---

## 2. Ambiente adotado

Requisitos:

- Windows 10/11;
- PowerShell 7 ou superior;
- Git;
- GitHub CLI (`gh`);
- OpenSSH;
- Visual Studio Code;
- GitHub Copilot, quando aplicavel.

O diretorio principal de projetos pode existir em:

```text
C:\dos\pwsh
D:\dos\pwsh
E:\pwsh
```

O contexto Extra usa, quando configurado:

```text
C:\dos\extra
D:\dos\extra
E:\extra
```

A configuracao local do DevContext fica em:

```text
%LOCALAPPDATA%\DevContext\
    config.json
    identities.json
    logs\
```

Esses arquivos sao especificos da maquina e nao devem ser tratados como parte do repositorio compartilhado.

---

## 3. Identidades configuradas no ambiente de referencia

### Personal

```text
Git user.name....... Wilson Pilon
Git user.email...... wilsonpilon@outlook.com
GitHub.............. wilsonpilon
SSH alias........... github.com-pessoal
GitHub Copilot...... wilsonpilon
Microsoft 365....... False
Isolado............. False
```

### Enterprise

```text
Git user.name....... Wilson Barney Pilon
Git user.email...... wilsonpilon@cindumel.com
GitHub.............. barneycindumel
SSH alias........... github.com-cindumel
GitHub Copilot...... barneycindumel
Microsoft 365....... True
Isolado............. False
```

O GitHub Copilot da identidade Enterprise corresponde ao Copilot Business administrado pela organizacao. A disponibilidade de uso continua sujeita aos limites/orcamento configurados pela organizacao.

### Extra

```text
GitHub.............. larissacristinadrummond
SSH alias........... github.com-larissa
GitHub Copilot...... larissacristinadrummond
Microsoft 365....... False
Isolado............. True
```

Extra deve permanecer isolado dos contextos Personal e Enterprise.

---

## 4. Aliases SSH

O DevContext espera aliases definidos em:

```text
%USERPROFILE%\.ssh\config
```

No ambiente de referencia:

```text
github.com-pessoal  -> GitHub Personal
github.com-cindumel -> GitHub Enterprise
github.com-larissa  -> GitHub Extra
```

O DevContext le somente a configuracao necessaria para identificar os aliases e `IdentityFile`. O conteudo das chaves privadas nao e lido.

Teste manual, quando necessario:

```powershell
ssh -T git@github.com-pessoal
ssh -T git@github.com-cindumel
ssh -T git@github.com-larissa
```

O GitHub responde com `Hi <conta>! You've successfully authenticated...` quando a chave corresponde a uma conta valida. O GitHub nao fornece shell, portanto o codigo de saida do `ssh -T` nao deve ser usado isoladamente para determinar sucesso.

---

## 5. Arquivos do DevContext

```text
DevContext\
    DevContext.ps1
    dev.ps1
    README.md
    MANUAL.md
    Update-BrowserProfileSync.ps1
```

### DevContext.ps1

Implementacao principal.

### dev.ps1

Wrapper para comandos mais curtos:

```powershell
.\dev.ps1 <comando>
```

### Update-BrowserProfileSync.ps1

Utilitario da versao 0.3.2 para ajustar o projeto BrowserProfileSync existente para a conta Copilot Enterprise correta (`barneycindumel`) e recriar `Start-Dev.ps1`.

---

## 6. Comandos

### Doctor

```powershell
.\dev.ps1 doctor
```

JSON:

```powershell
pwsh -File .\DevContext.ps1 doctor -Json
```

Usado para diagnosticar ambiente, Git, GitHub CLI, SSH e roots de projeto.

### Ver identidades

```powershell
.\dev.ps1 identities
```

### Configurar identidade

Exemplo Enterprise:

```powershell
.\dev.ps1 identity-setup -Identity Enterprise
```

Valores do ambiente de referencia:

```text
Git user.name................ Wilson Barney Pilon
Git user.email............... wilsonpilon@cindumel.com
SSH.......................... github.com-cindumel
GitHub....................... barneycindumel
GitHub Copilot............... barneycindumel
```

Tambem existem:

```powershell
.\dev.ps1 identity-setup -Identity Personal
.\dev.ps1 identity-setup -Identity Extra
```

### Testar consistencia local

```powershell
.\dev.ps1 identity-test
```

Verifica configuracao, alias SSH, campos obrigatorios e isolamento de Extra.

### Verificar identidade real no GitHub

```powershell
.\dev.ps1 identity-verify
```

Resultado esperado:

```text
Personal     PASS
Enterprise   PASS
Extra        PASS

Overall: VERIFIED
```

`identity-verify` executa autenticacao SSH nao interativa e compara a conta retornada pelo GitHub com a conta esperada.

---

## 7. Modelos de projeto

O comando `new` oferece cinco combinacoes:

| Modelo | Repositorio/Git | GitHub Copilot | M365 Copilot |
|---|---|---|---|
| Personal-Personal | Personal | Personal | Nao |
| Personal-Enterprise | Personal | Enterprise | Sim |
| Enterprise-Enterprise | Enterprise | Enterprise | Sim |
| Enterprise-Personal | Enterprise | Personal | Nao |
| Extra-Extra | Extra | Extra | Nao |

Extra-Extra nao pode usar o monorepo compartilhado e deve ser Standalone.

---

## 8. Criando um projeto

Execute:

```powershell
.\dev.ps1 new
```

Exemplo usado para BrowserProfileSync:

```text
Contexto........ Personal-Enterprise
Nome............ BrowserProfileSync
Repositorio..... Monorepo
```

Resultado esperado:

```text
E:\pwsh\BrowserProfileSync
```

Com:

```text
Git/GitHub...... Personal / wilsonpilon
Copilot......... Enterprise / barneycindumel
M365 Copilot.... habilitado
```

### Monorepo

O projeto e criado abaixo do ProjectRoot existente e nao recebe outro `.git`.

Exemplo:

```text
E:\pwsh\BrowserProfileSync
```

### Standalone

O DevContext executa `git init`, configura `user.name` e `user.email` localmente e adiciona os arquivos ao indice. Nao cria remoto, nao executa commit e nao faz push.

---

## 9. Estrutura de projeto gerada

```text
Projeto\
    .github\
        copilot-instructions.md
    .vscode\
    docs\
    src\
    tests\
    tools\
    .gitignore
    .project-context.json
    Projeto.code-workspace
    README.md
    Start-Dev.ps1
```

### .project-context.json

Registra a intencao do projeto:

- modelo de contexto;
- identidade do repositorio;
- conta GitHub;
- alias SSH;
- identidade/conta Copilot pretendida;
- disponibilidade do Microsoft 365 Copilot;
- isolamento de Extra.

Nao contem credenciais.

---

## 10. Start-Dev.ps1

Dentro de um projeto:

```powershell
.\Start-Dev.ps1
```

O script mostra, antes de abrir o VS Code:

```text
Project....... BrowserProfileSync
Context....... Personal-Enterprise
GitHub........ wilsonpilon
Copilot....... barneycindumel
M365 Copilot.. True
```

Depois abre o arquivo `.code-workspace`.

O `Start-Dev.ps1` nao troca silenciosamente a conta autenticada do Copilot. A conta deve ser validada no VS Code.

---

## 11. Confirmando a conta do GitHub Copilot no VS Code

Para um projeto Personal-Enterprise como BrowserProfileSync:

1. Abra o workspace pelo `Start-Dev.ps1`.
2. Pressione `Ctrl+Shift+P`.
3. Execute `Manage Extension Account Preferences`.
4. Selecione `GitHub Copilot`.
5. Confirme `barneycindumel` como `Current account` para esse workspace.

No ambiente validado:

```text
wilsonpilon      -> Copilot pessoal / Pro+
barneycindumel   -> Copilot Business / organizacao
```

A preferencia de conta do Copilot e por workspace e pode ser diferente da identidade Git utilizada pelo repositorio.

Isto permite:

```text
BrowserProfileSync
    Git........ wilsonpilon
    Copilot.... barneycindumel
```

---

## 12. Microsoft 365 Copilot x GitHub Copilot

Sao contextos complementares.

### GitHub Copilot Enterprise/Business

Usar principalmente para:

- programacao;
- refatoracao;
- testes;
- documentacao tecnica;
- contexto de repositorios de software.

### Microsoft 365 Copilot empresarial

Usar quando for necessario contexto autorizado do ambiente corporativo, como documentos, SharePoint, reunioes e informacoes organizacionais.

Um projeto Personal-Enterprise pode utilizar repositorio pessoal e Copilot empresarial sem transferir automaticamente conteudo corporativo para o repositorio pessoal. Qualquer informacao corporativa deve ser revisada antes de ser incorporada ao codigo/documentacao versionados.

---

## 13. Atualizando o BrowserProfileSync existente

Na 0.3.2 Final existe:

```powershell
.\Update-BrowserProfileSync.ps1
```

Esse script:

1. abre `E:\pwsh\BrowserProfileSync\.project-context.json`;
2. define `barneycindumel` como conta Copilot pretendida;
3. preserva `wilsonpilon` como identidade do repositorio;
4. recria `Start-Dev.ps1`.

Nao e necessario apagar ou recriar BrowserProfileSync apenas para corrigir sua conta Copilot.

---

## 14. Seguranca

O DevContext nunca deve colocar no Git:

```text
senhas
PATs
tokens OAuth
cookies
chaves SSH privadas
bancos internos de autenticacao do VS Code
credenciais Microsoft
```

O arquivo `.project-context.json` descreve contexto e identidade pretendida, e nao credenciais.

Antes de trabalhar em projeto sensivel:

```powershell
.\dev.ps1 identity-verify
```

E confirme a preferencia da conta GitHub Copilot no workspace.

---

## 15. Troubleshooting

### Overall diferente de VERIFIED

Execute:

```powershell
.\dev.ps1 identity-test
.\dev.ps1 identity-verify
```

Se houver `IDENTITY_MISMATCH`, compare o `githubAccount` cadastrado com:

```powershell
ssh -T git@ALIAS
```

### Copilot mostra quota pessoal

Abra `Manage Extension Account Preferences` e verifique qual conta esta selecionada para `GitHub Copilot` naquele workspace.

### Copilot Business mostra Usage Blocked

A identidade pode estar correta. `Usage Blocked` ou uso pausado por limite organizacional deve ser tratado na administracao/licenciamento/orcamento do GitHub Copilot da organizacao.

### Start-Dev.ps1 ausente no BrowserProfileSync

Na 0.3.2 Final:

```powershell
.\Update-BrowserProfileSync.ps1
```

### O root muda entre PCs

O DevContext procura:

```text
C:\dos\pwsh
D:\dos\pwsh
E:\pwsh
```

Por isso scripts de projeto devem preferir `$PSScriptRoot` e nao caminhos absolutos.

---

## 16. Fluxo recomendado em um novo PC

1. Instalar PowerShell 7, Git, GitHub CLI, OpenSSH e VS Code.
2. Clonar/sincronizar o repositorio `pwsh`.
3. Garantir os aliases SSH adequados em `%USERPROFILE%\.ssh\config`.
4. Executar:

```powershell
.\dev.ps1 doctor
```

5. Configurar as identidades necessarias:

```powershell
.\dev.ps1 identity-setup -Identity Personal
.\dev.ps1 identity-setup -Identity Enterprise
.\dev.ps1 identity-setup -Identity Extra
```

6. Validar:

```powershell
.\dev.ps1 identity-test
.\dev.ps1 identity-verify
```

7. No VS Code, autenticar as contas GitHub necessarias.
8. Em cada workspace, configurar `Manage Extension Account Preferences -> GitHub Copilot` para a conta declarada pelo projeto.

---

## 17. Estado ao fim da versao 0.3.2

A versao 0.3.2 fecha a primeira fase do DevContext com:

- descoberta do ambiente;
- tres identidades separadas;
- verificacao SSH real;
- isolamento Extra;
- modelos mistos Git/Copilot;
- geracao de workspace VS Code;
- `Start-Dev.ps1`;
- criacao Monorepo e Standalone;
- BrowserProfileSync definido como `Personal-Enterprise`;
- Copilot empresarial consolidado como `barneycindumel`.

O proximo projeto planejado e o BrowserProfileSync, destinado ao backup/restauracao controlados de dados locais de perfis Chromium, inicialmente Microsoft Edge e Vivaldi, com destinos associados no OneDrive.
