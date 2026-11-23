#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$context = Get-Content (Join-Path $root '.project-context.json') -Raw | ConvertFrom-Json
Write-Host "Project....... $($context.projectName)" -ForegroundColor Cyan
Write-Host "Context....... $($context.contextModel)"
Write-Host "GitHub........ $($context.repository.gitHubAccount)"
Write-Host "Copilot....... $($context.copilot.account)"
Write-Host "M365 Copilot.. $($context.microsoft365Copilot.enabled)"
Write-Host "IMPORTANT: Confirm the active GitHub Copilot account in VS Code before sending project content." -ForegroundColor Yellow
$workspace = Join-Path $root 'BrowserProfileSync.code-workspace'
& code $workspace
