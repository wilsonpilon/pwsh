# 🚀 PowerShell Scripts & CLI Tools Hub

Uma coleção completa de **scripts PowerShell**, **ferramentas de linha de comando** e **documentação interativa** para aumentar sua produtividade no Windows.

## 📋 Sobre o Projeto

Este repositório reúne exemplos práticos, scripts úteis e guias para trabalhar com PowerShell e ferramentas CLI como **Winget**, **Scoop** e outras utilidades de linha de comando. Tudo foi desenvolvido pensando em ser fácil de entender e aplicar em seus projetos.

### O que você encontrará aqui:
- ✅ Scripts PowerShell prontos para usar
- ✅ Tutoriais passo-a-passo com exemplos
- ✅ Guias de ferramentas CLI (Winget, Scoop)
- ✅ Dicas e boas práticas
- ✅ Automação de tarefas do Windows

---

## 📋 Pré-requisitos

Antes de começar, certifique-se de que você tem:

| Requisito | Versão Mínima | Descrição |
|-----------|---------------|-----------|
| **Windows** | 7 ou superior | Sistema operacional |
| **PowerShell** | v5.1+ | Ou Windows PowerShell, recomenda-se v7+ |
| **Winget** | Última versão | Gerenciador de pacotes do Windows |

### Verificar sua versão do PowerShell

Abra o PowerShell e execute:

```powershell
$PSVersionTable.PSVersion
```

Se você tiver PowerShell v5.0 ou anterior, considere atualizar para o [PowerShell 7](https://github.com/PowerShell/PowerShell).

---

## 🛠️ Instalação e Configuração

### 1. **Habilitar Execução de Scripts**

Por padrão, o PowerShell bloqueia a execução de scripts. Para permitir, **abra o PowerShell como Administrador** e execute:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Explicação**: Isso permite executar scripts locais e scripts baixados da internet que estejam assinados.

✅ Digite `Y` (Sim) quando solicitado.

### 2. **Instalar Winget** (Gerenciador de Pacotes)

O Winget vem pré-instalado no Windows 10/11. Para verificar:

```powershell
winget --version
```

Se não estiver instalado, acesse: https://github.com/microsoft/winget-cli

### 3. **Instalar Scoop** (Alternativa ao Winget)

O **Scoop** é um gerenciador de pacotes leve e poderoso. Para instalar:

```powershell
# 1. Habilite a execução de scripts (se não fez ainda)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 2. Baixe e instale o Scoop
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

# 3. Verifique a instalação
scoop --version
```

#### **Adicionar buckets (repositórios) no Scoop**

Os buckets são repositórios de aplicativos. Para aumentar suas opções:

```powershell
# Adicionar um bucket
scoop bucket add extras

# Listar alguns buckets úteis
scoop bucket add main           # Padrão
scoop bucket add extras         # Aplicativos adicionais
scoop bucket add games          # Jogos
scoop bucket add nerd-fonts     # Fontes Nerd
scoop bucket add nirsoft        # Ferramentas Nirsoft
scoop bucket add sysinternals   # Ferramentas de sistema
scoop bucket add java           # Distribuições Java
```

---

## 📚 Tutoriais com Exemplos

### **Winget - Seu Primeiro Script**

#### 📖 Tutorial: Instalar e atualizar aplicativos com Winget

```powershell
# 1. Buscar um pacote disponível
winget search "Visual Studio Code"

# 2. Ver detalhes de um pacote
winget show --id Microsoft.VisualStudioCode

# 3. Instalar um aplicativo
winget install --id Microsoft.VisualStudioCode --source winget

# 4. Listar aplicativos instalados
winget list

# 5. Atualizar um aplicativo específico
winget upgrade --id Microsoft.VisualStudioCode

# 6. Atualizar todos os aplicativos
winget upgrade --all
```

**Dica**: Use `--accept-license` para aceitar licenças automaticamente em scripts.

---

### **Scoop - Instalação Inteligente**

#### 📖 Tutorial: Usar Scoop para gerenciar ferramentas

```powershell
# 1. Instalar uma ferramenta simples
scoop install aria2  # Download manager com múltiplas conexões

# 2. Instalar múltiplas ferramentas de uma vez
scoop install git nodejs python

# 3. Listar aplicativos instalados
scoop list

# 4. Atualizar uma ferramenta específica
scoop update git

# 5. Atualizar todos os buckets
scoop update *

# 6. Procurar um aplicativo
scoop search "python"

# 7. Desinstalar uma ferramenta
scoop uninstall aria2
```

**Vantagem do Scoop**: Instalação portável, sem necessidade de UAC (administrador), ideal para desenvolvimento.

---

### **PowerShell Básico - Primeiros Passos**

#### 📖 Tutorial: Criar seu primeiro script

Crie um arquivo chamado `hello.ps1`:

```powershell
# Seu primeiro script PowerShell
Write-Host "Bem-vindo ao PowerShell!" -ForegroundColor Green

# Variáveis
$nome = "Desenvolvedor"
Write-Host "Olá, $nome!"

# Loops
Write-Host "`nNúmeros de 1 a 5:"
for ($i = 1; $i -le 5; $i++) {
    Write-Host "Número: $i"
}
```

**Para executar**:

```powershell
# Navegue até a pasta do script
cd "C:\caminho\do\seu\script"

# Execute o script
.\hello.ps1
```

---

#### 📖 Tutorial: Criar uma função útil

```powershell
# Função que lista arquivos de uma pasta
function Get-FolderSize {
    param(
        [string]$Path = "."
    )
    
    $size = (Get-ChildItem -Path $Path -Recurse | 
             Measure-Object -Property Length -Sum).Sum
    
    $sizeMB = [math]::Round($size / 1MB, 2)
    Write-Host "Tamanho da pasta: $sizeMB MB" -ForegroundColor Cyan
}

# Usar a função
Get-FolderSize -Path "C:\Users"
```

---

### **Automatização Prática**

#### 📖 Tutorial: Criar um script de limpeza de arquivos temporários

```powershell
# script-cleanup.ps1
# Deleta arquivos temporários do Windows

Write-Host "Iniciando limpeza de arquivos temporários..." -ForegroundColor Yellow

# Limpar pasta TEMP do usuário
$tempPath = $env:TEMP
Get-ChildItem -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue | 
    Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host "Limpeza concluída!" -ForegroundColor Green
```

---

## 📁 Estrutura do Projeto

```
pwsh/
├── README.md                 # Este arquivo
├── LICENSE                   # Licença do projeto
│
├── scripts/                  # Scripts PowerShell prontos
│   ├── install-tools.ps1     # Instalar ferramentas úteis
│   ├── system-info.ps1       # Informações do sistema
│   └── cleanup.ps1           # Limpeza de arquivos temporários
│
├── examples/                 # Exemplos de código
│   ├── basico/               # Exemplos básicos
│   │   ├── variáveis.ps1
│   │   ├── loops.ps1
│   │   └── funções.ps1
│   │
│   └── avancado/             # Exemplos avançados
│       ├── json-manipulation.ps1
│       └── rest-api-calls.ps1
│
├── docs/                     # Documentação adicional
│   ├── winget-guide.md       # Guia completo do Winget
│   ├── scoop-guide.md        # Guia completo do Scoop
│   └── powershell-tips.md    # Dicas e truques
│
└── tools/                    # Scripts de ferramentas CLI
    └── setup-cli-tools.ps1   # Setup de ferramentas úteis
```

---

## 🎓 Guia Rápido de Ferramentas CLI

### **Winget - Gerenciador de Pacotes Windows**

```powershell
# Buscar pacotes
winget search "PackageName"

# Instalar via Winget
winget install --id PackageID

# Listar atualizações disponíveis
winget upgrade --all --include-unknown

# Instalar com opções custom
winget install --id PackageID --override "/S"  # Modo silencioso
```

**Use Winget quando**: Quiser instalar aplicativos gráficos do Windows (Visual Studio Code, 7-Zip, etc.)

---

### **Scoop - Gerenciador Portável**

```powershell
# Instalar ferramenta
scoop install toolname

# Instalar versão específica
scoop install toolname@version

# Limpar downloads antigos
scoop cleanup *

# Verificar integridade
scoop checkup
```

**Use Scoop quando**: Trabalhar com ferramentas CLI (Git, Node.js, Python) ou quiser portabilidade.

---

## 🚀 Como Usar Este Repositório

1. **Clone ou baixe** os scripts para sua máquina
2. **Leia os comentários** dentro de cada script para entender o que faz
3. **Execute os scripts** (após habilitar execução com `Set-ExecutionPolicy`)
4. **Customize** os scripts para suas necessidades específicas

### Exemplo: Usar um script

```powershell
# 1. Navegue até a pasta
cd C:\projetos\pwsh\scripts

# 2. Execute
.\install-tools.ps1
```

---

## 💬 Contribuindo

Gostaria de adicionar seus próprios scripts? Siga os passos:

1. Crie um branch para sua feature (`git checkout -b feature/meu-script`)
2. Commit suas mudanças (`git commit -am 'Adiciona novo script'`)
3. Push para o branch (`git push origin feature/meu-script`)
4. Abra um Pull Request

**Standards**:
- Adicione comentários explicativos ao código
- Inclua um exemplo de uso
- Atualize a documentação se necessário

---

## 📝 Licença

Este projeto está licenciado sob a [Licença MIT](LICENSE) - sinta-se livre para usar, modificar e distribuir.

---

## 🤝 Suporte

Encontrou um problema? Dicas e sugestões:

- 📖 Consulte a [Página oficial do PowerShell](https://aka.ms/PowerShell-Docs)
- 🔍 Procure na documentação dos respectivos projetos (Winget, Scoop)
- 💡 Abra uma issue descrevendo o problema

---

## 📚 Recursos Úteis

- [Documentação PowerShell](https://docs.microsoft.com/pt-br/powershell/)
- [Winget - GitHub](https://github.com/microsoft/winget-cli)
- [Scoop - GitHub](https://github.com/lukesampson/scoop)
- [PowerShell Gallery](https://www.powershellgallery.com/)

---

**Desenvolvido com ❤️ para a comunidade PowerShell**


