param(
    [string]$Server,
    [int]$Port = 5433,
    [string]$Database,
    [string]$User,
    [string]$Password,
    [int]$Interval = 30
)

$env:PGPASSWORD = $Password

try {
    while ($true) {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Querying $Server..." -ForegroundColor Cyan

        C:\PostgreSQL\18\bin\psql `
            -h $Server `
            -p $Port `
            -U $User `
            -d $Database `
            -tAc "SELECT version();"

        Start-Sleep -Seconds $Interval
    }
}
finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}