oh-my-posh init pwsh --config 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/powerlevel10k_rainbow.omp.json' | Invoke-Expression

# Abrir o Explorador de Arquivos no diretório atual
function e { Start-Process "explorer.exe" -ArgumentList "." }

# Abrir o VS Code ou outro editor visual
function code { Start-Process "Code-Insiders.exe" -ArgumentList $args }

# Abrir o navegador em uma URL específica
function web { Start-Process "chrome.exe" -ArgumentList $args }

# Abrir o navegador em uma URL específica
function notepad { Start-Process "010editor.exe" -ArgumentList $args }

function y {
	$tmp = (New-TemporaryFile).FullName
	yazi.exe @args --cwd-file="$tmp"
	$cwd = Get-Content -Path $tmp -Encoding UTF8
	if ($cwd -and $cwd -ne $PWD.Path -and (Test-Path -LiteralPath $cwd -PathType Container)) {
		Set-Location -LiteralPath (Resolve-Path -LiteralPath $cwd).Path
	}
	Remove-Item -Path $tmp
}

function start-basica {
    # Navega para a pasta do projeto
    Set-Location "e:\msxbasica"
    
    # Inicia o editor TUI ou GUI
    Start-Process "Code-Insiders.exe" -ArgumentList "."
    
    # Abre documentação técnica ou manuais de cross-compilação
    Start-Process "claude.exe" -ArgumentList ""
}

# Substitui o ls/dir pelo eza com ícones e detalhes
function ls { eza --icons $args }
function ll { eza -la --icons $args }

# Substitui o cat/type pelo bat
Set-Alias cat bat

# Inicializa o zoxide (agora você pode usar 'z' em vez de 'cd')
Invoke-Expression (& { (zoxide init powershell | Out-String) })

# Carrega a integração do fzf com o PowerShell (habilita os atalhos de teclado)
Import-Module PSFzf

# Configuração visual: layout reverso (barra de busca no topo), bordas e margens
$env:FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --margin=1 --padding=1"

# Opcional, mas altamente recomendado: 
# Se você instalou o 'fd', force o fzf a usá-lo como motor base. 
# Isso faz com que a busca de arquivos ignore diretórios como .git ou node_modules.
$env:FZF_DEFAULT_COMMAND="fd --type f --hidden --exclude .git"
$env:FZF_CTRL_T_COMMAND="$env:FZF_DEFAULT_COMMAND"