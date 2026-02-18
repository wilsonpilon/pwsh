param(
    [Parameter(Position=0)]
    [string]$Path = (Get-Location).Path
)

function Format-FileSize {
    param([long]$Size)
    
    if ($Size -gt 1TB) {
        return "{0:N2} TB" -f ($Size / 1TB)
    }
    elseif ($Size -gt 1GB) {
        return "{0:N2} GB" -f ($Size / 1GB)
    }
    elseif ($Size -gt 1MB) {
        return "{0:N2} MB" -f ($Size / 1MB)
    }
    elseif ($Size -gt 1KB) {
        return "{0:N2} KB" -f ($Size / 1KB)
    }
    else {
        return "{0:N0} Bytes" -f $Size
    }
}

if (-not (Test-Path $Path)) {
    Write-Error "O caminho '$Path' não existe."
    exit 1
}

Write-Host "`nAnalisando diretório: $Path`n" -ForegroundColor Cyan

Get-ChildItem -Path $Path -Directory | ForEach-Object {
    $folder = $_
    $size = (Get-ChildItem -Path $folder.FullName -Recurse -File -ErrorAction SilentlyContinue | 
             Measure-Object -Property Length -Sum).Sum
    
    if ($null -eq $size) { $size = 0 }
    
    [PSCustomObject]@{
        Nome = $folder.Name
        Tamanho = Format-FileSize -Size $size
        TamanhoBytes = $size
    }
} | Sort-Object TamanhoBytes -Descending | 
    Format-Table Nome, Tamanho -AutoSize

Write-Host "Concluído!`n" -ForegroundColor Green