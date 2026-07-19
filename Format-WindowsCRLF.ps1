param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath
)

if (-not (Test-Path $FilePath)) {
    Write-Error "File not found: $FilePath"
    exit 1
}

$content = Get-Content $FilePath -Raw
$convertedContent = $content -replace "`r`n", "`n" -replace "`n", "`r`n"

Set-Content $FilePath $convertedContent -NoNewline

Write-Host "File converted to Windows CRLF format: $FilePath"
