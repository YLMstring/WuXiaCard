[CmdletBinding()]
param(
    [string]$EnginePath = "",
    [string]$ProjectRoot = "",
    [switch]$SkipBuild
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
if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot "build_duel_native.ps1") `
        -ProjectRoot $resolvedProject `
        -Configuration Release
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $scanStdoutPath = [System.IO.Path]::GetTempFileName()
    $scanStderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $scanArguments = @(
            "--headless",
            "--audio-driver",
            "Dummy",
            "--editor",
            "--quit",
            "--path",
            ('"{0}"' -f $resolvedProject)
        )
        $scanProcess = Start-Process `
            -FilePath $EnginePath `
            -ArgumentList $scanArguments `
            -Wait `
            -PassThru `
            -WindowStyle Hidden `
            -RedirectStandardOutput $scanStdoutPath `
            -RedirectStandardError $scanStderrPath
        if ($scanProcess.ExitCode -ne 0) {
            Write-Host (Get-Content -LiteralPath $scanStdoutPath -Raw -ErrorAction SilentlyContinue)
            Write-Host (Get-Content -LiteralPath $scanStderrPath -Raw -ErrorAction SilentlyContinue)
            exit $scanProcess.ExitCode
        }
    }
    finally {
        Remove-Item -LiteralPath $scanStdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $scanStderrPath -Force -ErrorAction SilentlyContinue
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
        "res://tests/benchmarks/duel_native_compact_probe.gd"
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
        -or $combined -notmatch "DUEL_NATIVE_COMPACT_PROBE_COMPLETE" `
        -or $combined -match "(?im)DUEL_NATIVE_COMPACT_PROBE_FAILED|SCRIPT ERROR:|^ERROR:"
    ) {
        exit 1
    }
}
finally {
    Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
}
exit 0
