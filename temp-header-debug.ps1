$raw = @(winget update --include-unknown 2>&1)
for ($i = 0; $i -lt $raw.Count; $i++) {
  $line = [string]$raw[$i]
  Write-Host ("LINE[{0}]={1}" -f $i, $line)
  Write-Host ("MATCH1={0}" -f ($line -match '(?i)\b(Nome|Name)\b'))
  Write-Host ("MATCH2={0}" -f ($line -match '(?i)\b(ID|Id)\b'))
  Write-Host ("MATCH3={0}" -f ($line -match '(?i)\b(Vers[ãa]o|Version)\b'))
  Write-Host '---'
}
