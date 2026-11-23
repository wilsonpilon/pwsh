#requires -Version 7.0
$ErrorActionPreference='Stop'
$project='E:\pwsh\BrowserProfileSync'
$contextFile=Join-Path $project '.project-context.json'
if(-not(Test-Path -LiteralPath $contextFile)){throw "Nao encontrado: $contextFile"}
$context=Get-Content -LiteralPath $contextFile -Raw|ConvertFrom-Json
$context.copilot.account='barneycindumel'
$context|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $contextFile -Encoding utf8
$startFile=Join-Path $project 'Start-Dev.ps1'
$start=@'
#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$context=Get-Content -LiteralPath(Join-Path $root '.project-context.json')-Raw|ConvertFrom-Json
Write-Host "Project....... $($context.projectName)" -ForegroundColor Cyan
Write-Host "Context....... $($context.contextModel)"
Write-Host "GitHub........ $($context.repository.gitHubAccount)"
Write-Host "Copilot....... $($context.copilot.account)"
Write-Host "M365 Copilot.. $($context.microsoft365Copilot.enabled)"
Write-Host "Confirm GitHub Copilot account preference for this workspace: $($context.copilot.account)" -ForegroundColor Yellow
$workspace=Join-Path $root "$($context.projectName).code-workspace"
& code $workspace
'@
Set-Content -LiteralPath $startFile -Value $start -Encoding utf8
Write-Host 'BrowserProfileSync atualizado para Copilot barneycindumel e Start-Dev.ps1 recriado.' -ForegroundColor Green
