$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Do-Unix.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$processDirectory = [Environment]::CurrentDirectory
$driveName = 'UnixTest' + [guid]::NewGuid().ToString('N')
$locationPushed = $false
$driveCreated = $false

function Assert-Output {
    param([string] $Name, [object[]] $Actual, [object[]] $Expected)

    if (($Actual -join "`n") -cne ($Expected -join "`n")) {
        throw "$Name failed: expected '$($Expected -join '\n')', got '$($Actual -join '\n')'."
    }
}

try {
    $null = New-Item -ItemType Directory -Path $testRoot
    $filePath = Join-Path $testRoot 'resume[1].txt'
    [System.IO.File]::WriteAllText($filePath, "alpha beta`ngamma`ndelta`n")
    Push-Location -LiteralPath $testRoot
    $locationPushed = $true
    [Environment]::CurrentDirectory = [System.IO.Path]::GetTempPath()

    Assert-Output 'head relative path' (& $scriptPath head -n 2 '.\resume[1].txt') @('alpha beta', 'gamma')
    Assert-Output 'tail relative path' (& $scriptPath tail -n 1 '.\resume[1].txt') @('delta')
    Assert-Output 'wc relative path' (& $scriptPath wc -lwmc '.\resume[1].txt') @("3`t4`t23`t23`t.\resume[1].txt")
    Assert-Output 'grep relative path' (& $scriptPath grep -n gamma '.\resume[1].txt') @('2:gamma')
    Assert-Output 'absolute path' (& $scriptPath head -n 1 $filePath) @('alpha beta')
    Assert-Output 'byte selection' (& $scriptPath head -c 5 '.\resume[1].txt') @('alpha')
    Assert-Output 'pipeline' (@('one', 'two') | & $scriptPath tail -n 1) @('two')
    Assert-Output 'multiple files' (& $scriptPath head -q -n 1 $filePath $filePath) @('alpha beta', 'alpha beta')

    $null = New-PSDrive -Name $driveName -PSProvider FileSystem -Root $testRoot
    $driveCreated = $true
    Assert-Output 'PowerShell drive path' (& $scriptPath head -n 1 "${driveName}:\resume[1].txt") @('alpha beta')

    $bomPath = Join-Path $testRoot 'bom.txt'
    [System.IO.File]::WriteAllText($bomPath, "first`nsecond", [System.Text.UnicodeEncoding]::new($false, $true))
    Assert-Output 'BOM detection' (& $scriptPath head -n 1 '.\bom.txt') @('first')

    $lock = [System.IO.File]::Open($filePath, 'Open', 'ReadWrite', 'None')
    try {
        $readErrors = @()
        $output = @(& {
            $ErrorActionPreference = 'Continue'
            try {
                & $scriptPath head '.\resume[1].txt'
            }
            catch {
                $_
            }
        } 2>&1)
        $readErrors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
        if ($readErrors.Count -ne 1 -or $output.Count -ne 1 -or
            $readErrors[0].Exception.Message -match 'null-valued') {
            throw "Expected one read error without output or null-reader errors; got: $output"
        }
    }
    finally {
        $lock.Dispose()
    }

    Write-Output 'All Do-Unix regression tests passed.'
}
finally {
    [Environment]::CurrentDirectory = $processDirectory
    if ($locationPushed) { Pop-Location }
    if ($driveCreated) { Remove-PSDrive -Name $driveName }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
