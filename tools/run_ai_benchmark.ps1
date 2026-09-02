[CmdletBinding()]
param(
    [ValidateSet("Quick", "Pilot", "Extended", "Production")]
    [string]$Mode = "Quick",
    [ValidateSet("Final")]
    [string]$Variant = "Final",
    [string]$EnginePath = "",
    [string]$ProjectRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$resolvedProject = [System.IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($EnginePath)) {
    $EnginePath = Join-Path $env:LOCALAPPDATA "SummerEngine\current\Summer.exe"
}
if (-not (Test-Path -LiteralPath $EnginePath -PathType Leaf)) {
    throw "Summer Engine not found: $EnginePath"
}

function Forward-NewCompleteLines {
    param(
        [string]$Path,
        [hashtable]$State,
        [System.Collections.Generic.List[string]]$CapturedLines,
        [switch]$FlushRemainder
    )

    $currentText = ""
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $readText = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
        if ($null -ne $readText) {
            $currentText = [string]$readText
        }
    }
    if ($currentText.Length -lt [int]$State.Offset) {
        $State.Offset = 0
        $State.Remainder = ""
    }
    if ($currentText.Length -gt [int]$State.Offset) {
        $newText = $currentText.Substring([int]$State.Offset)
        $State.Offset = $currentText.Length
        $pendingText = [string]$State.Remainder + $newText
        $matches = [regex]::Matches($pendingText, "(.*?)(?:`r`n|`n|`r)")
        $consumedCharacters = 0
        foreach ($match in $matches) {
            $line = $match.Groups[1].Value
            Write-Host $line
            $CapturedLines.Add($line)
            $consumedCharacters = $match.Index + $match.Length
        }
        $State.Remainder = $pendingText.Substring($consumedCharacters)
    }
    if ($FlushRemainder -and -not [string]::IsNullOrEmpty([string]$State.Remainder)) {
        $line = [string]$State.Remainder
        Write-Host $line
        $CapturedLines.Add($line)
        $State.Remainder = ""
    }
}

$stdoutPath = [System.IO.Path]::GetTempFileName()
$stderrPath = [System.IO.Path]::GetTempFileName()
try {
    $arguments = @(
        "--headless",
        "--audio-driver",
        "Dummy",
        "--path",
        ('"{0}"' -f $resolvedProject),
        "--script",
        "res://tests/benchmarks/duel_ai_benchmark.gd",
        "--",
        "--mode=$Mode",
        "--variant=$Variant"
    )
    $process = Start-Process `
        -FilePath $EnginePath `
        -ArgumentList $arguments `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath
    $capturedLines = [System.Collections.Generic.List[string]]::new()
    $stdoutState = @{ Offset = 0; Remainder = "" }
    $stderrState = @{ Offset = 0; Remainder = "" }
    while (-not $process.HasExited) {
        Forward-NewCompleteLines -Path $stdoutPath -State $stdoutState -CapturedLines $capturedLines
        Forward-NewCompleteLines -Path $stderrPath -State $stderrState -CapturedLines $capturedLines
        Start-Sleep -Milliseconds 250
        $process.Refresh()
    }
    $process.WaitForExit()
    Forward-NewCompleteLines -Path $stdoutPath -State $stdoutState -CapturedLines $capturedLines -FlushRemainder
    Forward-NewCompleteLines -Path $stderrPath -State $stderrState -CapturedLines $capturedLines -FlushRemainder
    $combined = $capturedLines -join "`n"
    if ($process.ExitCode -ne 0 -or $combined -match "(?im)AI_BENCHMARK_FAILED|SCRIPT ERROR:|^ERROR:") {
        exit 1
    }
}
finally {
    Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
}
exit 0
