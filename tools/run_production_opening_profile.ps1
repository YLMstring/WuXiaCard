[CmdletBinding()]
param(
    [double]$BudgetSeconds = 10.0,
    [int]$MaxOpenings = 14,
    [ValidateSet("complete_round", "self_turn")]
    [string]$DepthMode = "complete_round",
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
        "res://tests/benchmarks/production_opening_depth_profile.gd",
        "--",
        "--budget-seconds=$BudgetSeconds",
        "--max-openings=$MaxOpenings",
        "--depth-mode=$DepthMode"
    )
    $process = Start-Process `
        -FilePath $EnginePath `
        -ArgumentList $arguments `
        -Wait `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath
    $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
    $combined = "$stdout`n$stderr"
    Write-Host $combined.Trim()
    if (
        $process.ExitCode -ne 0 `
        -or $combined -notmatch "OPENING_DEPTH_PROFILE_COMPLETE" `
        -or $combined -match "(?im)OPENING_DEPTH_PROFILE_FAILED|SCRIPT ERROR:|^ERROR:"
    ) {
        exit 1
    }
}
finally {
    Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
}
exit 0
