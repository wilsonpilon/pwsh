param(
    [string] $Utility
)

$validUtilities = @("head", "tail", "wc", "tr", "less", "grep")
if ([string]::IsNullOrWhiteSpace($Utility) -or $Utility -notin $validUtilities) {
    throw "Informe um comando válido: $($validUtilities -join ', ')."
}

$arguments = @($args)
$pipelineLines = [System.Collections.Generic.List[string]]::new()
foreach ($pipelineValue in $input) {
    if ($null -ne $pipelineValue) {
        $pipelineLines.Add([string]$pipelineValue)
    }
}
$hasPipelineInput = $pipelineLines.Count -gt 0

function Read-TextFile {
    param([Parameter(Mandatory = $true)][string] $Path)

    $reader = [System.IO.StreamReader]::new($Path, $true)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }
}

function Split-TextLines {
    param([AllowEmptyString()][string] $Text)

    if ($Text.Length -eq 0) {
        return @()
    }

    $lines = [regex]::Split($Text, "\r\n|\n|\r")
    if ($Text -match "(?:\r\n|\n|\r)$") {
        $lines = $lines[0..($lines.Length - 2)]
    }
    return $lines
}

function Expand-TrSet {
    param([Parameter(Mandatory = $true)][string] $Set)

    $characters = [System.Collections.Generic.List[char]]::new()
    for ($i = 0; $i -lt $Set.Length; $i++) {
        if ($Set[$i] -eq '\' -and $i + 1 -lt $Set.Length) {
            $i++
            $escaped = switch ($Set[$i]) {
                'n' { "`n" }
                'r' { "`r" }
                't' { "`t" }
                '0' { [char]0 }
                default { [char]$Set[$i] }
            }
            $characters.Add([char]$escaped)
            continue
        }

        if ($i + 2 -lt $Set.Length -and $Set[$i + 1] -eq '-') {
            $first = [int][char]$Set[$i]
            $last = [int][char]$Set[$i + 2]
            if ($last -lt $first) {
                throw "Intervalo inválido no conjunto: '$Set'."
            }
            for ($code = $first; $code -le $last; $code++) {
                $characters.Add([char]$code)
            }
            $i += 2
            continue
        }

        $characters.Add([char]$Set[$i])
    }
    return $characters.ToArray()
}

$paths = [System.Collections.Generic.List[string]]::new()

switch ($Utility.ToLowerInvariant()) {
        { $_ -in "head", "tail" } {
            $lineCount = 10
            $byteCount = $null
            $quiet = $false
            $alwaysHeader = $false
            for ($i = 0; $i -lt $arguments.Count; $i++) {
                $arg = $arguments[$i]
                if ($arg -in "-q", "--quiet") { $quiet = $true; continue }
                if ($arg -in "-v", "--verbose") { $alwaysHeader = $true; continue }
                if ($arg -in "-n", "--lines", "-c", "--bytes") {
                    if ($i + 1 -ge $arguments.Count -or $arguments[$i + 1] -notmatch '^\d+$') {
                        throw "A opção $arg requer uma quantidade numérica."
                    }
                    $count = [long]$arguments[++$i]
                    if ($arg -in "-c", "--bytes") { $byteCount = $count } else { $lineCount = $count }
                    continue
                }
                if ($arg -match '^--(?:lines|bytes)=(\d+)$') {
                    if ($arg.StartsWith("--bytes=")) { $byteCount = [long]$Matches[1] } else { $lineCount = [long]$Matches[1] }
                    continue
                }
                if ($arg -match '^-(\d+)$') { $lineCount = [long]$Matches[1]; continue }
                if ($arg.StartsWith("-")) { throw "Opção não suportada para $Utility`: $arg" }
                $paths.Add($arg)
            }

            if ($paths.Count -eq 0 -and -not $hasPipelineInput) { return }
            $sourceCount = [Math]::Max(1, $paths.Count)
            for ($sourceIndex = 0; $sourceIndex -lt $sourceCount; $sourceIndex++) {
                $path = if ($paths.Count -gt 0) { $paths[$sourceIndex] } else { $null }
                if ($null -ne $path) {
                    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Arquivo não encontrado: $path" }
                    $text = Read-TextFile -Path $path
                    $lines = @(Split-TextLines -Text $text)
                }
                else {
                    $lines = $pipelineLines.ToArray()
                }

                if ($paths.Count -gt 1 -and -not $quiet -or $alwaysHeader) {
                    if ($null -ne $path) { Write-Output "==> $path <==" } else { Write-Output "==> standard input <==" }
                }

                if ($null -ne $byteCount) {
                    $textToWrite = if ($null -ne $path) { $text } else { ($pipelineLines -join [Environment]::NewLine) }
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($textToWrite)
                    if ($Utility -eq "head") { $slice = $bytes | Select-Object -First ([Math]::Min($byteCount, $bytes.Length)) }
                    else { $slice = $bytes | Select-Object -Last ([Math]::Min($byteCount, $bytes.Length)) }
                    if ($slice.Count -gt 0) {
                        [System.Text.Encoding]::UTF8.GetString([byte[]]$slice)
                    }
                    continue
                }

                if ($Utility -eq "head") { $selected = $lines | Select-Object -First $lineCount }
                else { $selected = $lines | Select-Object -Last $lineCount }
                $selected
            }
        }

        "wc" {
            $countLines = $false
            $countWords = $false
            $countBytes = $false
            $countCharacters = $false
            $explicitOptions = $false
            for ($i = 0; $i -lt $arguments.Count; $i++) {
                $arg = $arguments[$i]
                if ($arg -match '^-[lwmc]+$') {
                    $explicitOptions = $true
                    foreach ($option in $arg.Substring(1).ToCharArray()) {
                        switch ($option) {
                            'l' { $countLines = $true }
                            'w' { $countWords = $true }
                            'm' { $countCharacters = $true }
                            'c' { $countBytes = $true }
                        }
                    }
                } elseif ($arg.StartsWith("-")) { throw "Opção não suportada para wc: $arg" }
                else { $paths.Add($arg) }
            }
            if (-not $explicitOptions) { $countLines = $countWords = $countBytes = $true }

            $totals = [long[]]@(0, 0, 0, 0)
            $sourceCount = [Math]::Max(1, $paths.Count)
            for ($sourceIndex = 0; $sourceIndex -lt $sourceCount; $sourceIndex++) {
                $path = if ($paths.Count -gt 0) { $paths[$sourceIndex] } else { $null }
                if ($null -ne $path) {
                    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Arquivo não encontrado: $path" }
                    $text = Read-TextFile -Path $path
                    $bytes = (Get-Item -LiteralPath $path).Length
                    $lines = ([regex]::Matches($text, "\r\n|\n|\r")).Count
                }
                else {
                    $text = if ($hasPipelineInput) { $pipelineLines -join [Environment]::NewLine } else { "" }
                    $bytes = [System.Text.Encoding]::UTF8.GetByteCount($text)
                    $lines = $pipelineLines.Count
                }
                $words = [regex]::Matches($text.Trim(), '\S+').Count
                $characters = $text.Length
                $values = @($lines, $words, $bytes, $characters)
                for ($i = 0; $i -lt $values.Count; $i++) { $totals[$i] += $values[$i] }

                $display = [System.Collections.Generic.List[string]]::new()
                if ($countLines) { $display.Add([string]$lines) }
                if ($countWords) { $display.Add([string]$words) }
                if ($countBytes) { $display.Add([string]$bytes) }
                if ($countCharacters) { $display.Add([string]$characters) }
                if ($null -ne $path) { $display.Add($path) }
                Write-Output ($display -join "`t")
            }
            if ($paths.Count -gt 1) {
                $display = [System.Collections.Generic.List[string]]::new()
                for ($i = 0; $i -lt $totals.Count; $i++) {
                    if (@($countLines, $countWords, $countBytes, $countCharacters)[$i]) {
                        $display.Add([string]$totals[$i])
                    }
                }
                $display.Add("total")
                Write-Output ($display -join "`t")
            }
        }

        "tr" {
            $delete = $false
            $squeeze = $false
            $sets = [System.Collections.Generic.List[string]]::new()
            foreach ($arg in $arguments) {
                if ($arg -in "-d", "--delete") { $delete = $true; continue }
                if ($arg -in "-s", "--squeeze-repeats") { $squeeze = $true; continue }
                if ($arg.StartsWith("-")) { throw "Opção não suportada para tr: $arg" }
                $sets.Add($arg)
            }
            $validSetCount = if ($delete) { $sets.Count -eq 1 } elseif ($squeeze) { $sets.Count -in 1, 2 } else { $sets.Count -eq 2 }
            if (-not $validSetCount) {
                throw "Uso: Do-Unix.ps1 tr [-d] [-s] conjunto1 [conjunto2]"
            }

            $sourceText = if ($paths.Count -gt 0) {
                throw "tr aceita texto pelo pipeline; informe a entrada com Get-Content -Raw."
            }
            elseif ($hasPipelineInput) {
                $pipelineLines -join [Environment]::NewLine
            }
            else { "" }
            $from = @(Expand-TrSet -Set $sets[0])
            $to = if ($sets.Count -eq 1) { @() } else { @(Expand-TrSet -Set $sets[1]) }
            $builder = [System.Text.StringBuilder]::new()
            $lastOutput = [char]0
            $hasLastOutput = $false
            $squeezeCharacters = if ($to.Count -gt 0) { $to } else { $from }
            foreach ($character in $sourceText.ToCharArray()) {
                $index = [Array]::IndexOf($from, $character)
                if ($delete -and $index -ge 0) { continue }
                $outputCharacter = if ($index -ge 0 -and -not $delete -and $to.Count -gt 0) {
                    $to[[Math]::Min($index, $to.Count - 1)]
                }
                else { $character }
                if ($squeeze -and $hasLastOutput -and $outputCharacter -eq $lastOutput -and [Array]::IndexOf($squeezeCharacters, $outputCharacter) -ge 0) { continue }
                [void]$builder.Append($outputCharacter)
                $lastOutput = $outputCharacter
                $hasLastOutput = $true
            }
            Write-Output -NoEnumerate $builder.ToString()
        }

        "less" {
            foreach ($arg in $arguments) {
                if ($arg.StartsWith("-")) { throw "Opções de navegação do less não são suportadas: $arg" }
                $paths.Add($arg)
            }
            if ($paths.Count -gt 0) {
                foreach ($path in $paths) {
                    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Arquivo não encontrado: $path" }
                    Get-Content -LiteralPath $path | Out-Host -Paging
                }
            }
            elseif ($hasPipelineInput) {
                $pipelineLines | Out-Host -Paging
            }
        }

        "grep" {
            $ignoreCase = $false
            $invert = $false
            $lineNumbers = $false
            $countMatches = $false
            $listFiles = $false
            $noFilename = $false
            $wholeWord = $false
            $wholeLine = $false
            $fixedStrings = $false
            $maxCount = [long]::MaxValue
            $pattern = $null
            for ($i = 0; $i -lt $arguments.Count; $i++) {
                $arg = $arguments[$i]
                if ($arg -in "-i", "--ignore-case") { $ignoreCase = $true; continue }
                if ($arg -in "-v", "--invert-match") { $invert = $true; continue }
                if ($arg -in "-n", "--line-number") { $lineNumbers = $true; continue }
                if ($arg -in "-c", "--count") { $countMatches = $true; continue }
                if ($arg -in "-l", "--files-with-matches") { $listFiles = $true; continue }
                if ($arg -in "-h", "--no-filename") { $noFilename = $true; continue }
                if ($arg -in "-w", "--word-regexp") { $wholeWord = $true; continue }
                if ($arg -in "-x", "--line-regexp") { $wholeLine = $true; continue }
                if ($arg -in "-F", "--fixed-strings") { $fixedStrings = $true; continue }
                if ($arg -match '^-[ivnclhwxF]+$') {
                    foreach ($option in $arg.Substring(1).ToCharArray()) {
                        switch ($option) {
                            'i' { $ignoreCase = $true }
                            'v' { $invert = $true }
                            'n' { $lineNumbers = $true }
                            'c' { $countMatches = $true }
                            'l' { $listFiles = $true }
                            'h' { $noFilename = $true }
                            'w' { $wholeWord = $true }
                            'x' { $wholeLine = $true }
                            'F' { $fixedStrings = $true }
                        }
                    }
                    continue
                }
                if ($arg -in "-e", "--regexp", "-m", "--max-count") {
                    if ($i + 1 -ge $arguments.Count) { throw "A opção $arg requer um valor." }
                    if ($arg -in "-e", "--regexp") { $pattern = $arguments[++$i] }
                    else {
                        if ($arguments[$i + 1] -notmatch '^\d+$') { throw "A opção $arg requer uma quantidade numérica." }
                        $maxCount = [long]$arguments[++$i]
                    }
                    continue
                }
                if ($arg.StartsWith("-")) { throw "Opção não suportada para grep: $arg" }
                if ($null -eq $pattern) { $pattern = $arg } else { $paths.Add($arg) }
            }
            if ([string]::IsNullOrEmpty($pattern)) { throw "Informe o padrão que deseja buscar." }
            if ($fixedStrings) { $pattern = [regex]::Escape($pattern) }
            if ($wholeWord) { $pattern = "(?<!\w)(?:$pattern)(?!\w)" }
            if ($wholeLine) { $pattern = "^(?:$pattern)$" }
            $regexOptions = if ($ignoreCase) { [System.Text.RegularExpressions.RegexOptions]::IgnoreCase } else { [System.Text.RegularExpressions.RegexOptions]::None }
            try { $regex = [regex]::new($pattern, $regexOptions) }
            catch { throw "Expressão regular inválida: $_" }

            $sourceCount = [Math]::Max(1, $paths.Count)
            for ($sourceIndex = 0; $sourceIndex -lt $sourceCount; $sourceIndex++) {
                $path = if ($paths.Count -gt 0) { $paths[$sourceIndex] } else { $null }
                if ($null -ne $path) {
                    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Arquivo não encontrado: $path" }
                    $lines = @(Split-TextLines -Text (Read-TextFile -Path $path))
                }
                else { $lines = $pipelineLines.ToArray() }

                $found = 0
                if ($maxCount -eq 0) {
                    if ($countMatches) {
                        if ($paths.Count -gt 1 -and -not $noFilename) { Write-Output "$path`:0" }
                        else { Write-Output 0 }
                    }
                    continue
                }
                for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
                    $matchesPattern = $regex.IsMatch($lines[$lineIndex])
                    if ($matchesPattern -eq $invert) { continue }
                    $found++
                    if ($listFiles) { break }
                    if (-not $countMatches) {
                        $output = $lines[$lineIndex]
                        if ($lineNumbers) { $output = "$($lineIndex + 1):$output" }
                        if ($paths.Count -gt 1 -and -not $noFilename) { $output = "$path`:$output" }
                        Write-Output $output
                    }
                    if ($found -ge $maxCount) { break }
                }
                if ($listFiles -and $found -gt 0) { Write-Output $path }
                if ($countMatches) {
                    if ($paths.Count -gt 1 -and -not $noFilename) { Write-Output "$path`:$found" }
                    else { Write-Output $found }
                }
            }
        }
}
