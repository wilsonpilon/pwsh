#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('new','doctor','status','identities','identity-setup','identity-test','identity-verify','config')]
    [string]$Command = 'status',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

$devContext = Join-Path $PSScriptRoot 'DevContext.ps1'
& pwsh -NoProfile -File $devContext -Command $Command @RemainingArguments
exit $LASTEXITCODE
