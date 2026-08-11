$raw = @(winget update --include-unknown 2>&1)
foreach ($item in $raw) {
  $line = [string]$item
  $trimmed = $line.Trim()
  if ($trimmed) {
    Write-Output "LINE=$trimmed"
    $columns = @($trimmed -split '\s{2,}')
    Write-Output "COLS=$($columns.Count)"
    for ($i = 0; $i -lt $columns.Count; $i++) {
      Write-Output "COL[$i]=$($columns[$i])"
    }
    Write-Output '---'
  }
}
