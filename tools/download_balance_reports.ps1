[CmdletBinding()]
param(
    [ValidateSet("Csv", "Json")]
    [string]$Format = "Csv",
    [string]$Endpoint = "",
    [string]$From = "",
    [string]$To = "",
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Endpoint)) {
    $Endpoint = $env:WUXIA_TELEMETRY_ADMIN_ENDPOINT
}
$adminToken = $env:WUXIA_TELEMETRY_ADMIN_TOKEN
if ([string]::IsNullOrWhiteSpace($Endpoint)) {
    throw "Pass -Endpoint or set WUXIA_TELEMETRY_ADMIN_ENDPOINT."
}
if (-not $Endpoint.StartsWith("https://", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The telemetry admin endpoint must use HTTPS."
}
if ([string]::IsNullOrWhiteSpace($adminToken)) {
    throw "Set WUXIA_TELEMETRY_ADMIN_TOKEN in the current shell."
}

$query = [System.Collections.Generic.List[string]]::new()
$query.Add("format=$($Format.ToLowerInvariant())")
if (-not [string]::IsNullOrWhiteSpace($From)) {
    $query.Add("from=$([uri]::EscapeDataString($From))")
}
if (-not [string]::IsNullOrWhiteSpace($To)) {
    $query.Add("to=$([uri]::EscapeDataString($To))")
}
$separator = if ($Endpoint.Contains("?")) { "&" } else { "?" }
$requestUri = "$Endpoint$separator$($query -join '&')"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $extension = $Format.ToLowerInvariant()
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path (Get-Location) "balance-reports-$stamp.$extension"
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}
if (Test-Path -LiteralPath $resolvedOutput) {
    throw "Refusing to overwrite an existing export: $resolvedOutput"
}
$temporaryOutput = "$resolvedOutput.tmp"

try {
    Invoke-WebRequest `
        -Uri $requestUri `
        -Headers @{ Authorization = "Bearer $adminToken" } `
        -OutFile $temporaryOutput `
        -UseBasicParsing

    if ((Get-Item -LiteralPath $temporaryOutput).Length -eq 0) {
        throw "The export response was empty."
    }
    if ($Format -eq "Json") {
        Get-Content -LiteralPath $temporaryOutput -Raw | ConvertFrom-Json | Out-Null
    }
    Move-Item -LiteralPath $temporaryOutput -Destination $resolvedOutput -Force
    Write-Host "Downloaded balance reports: $resolvedOutput"
}
finally {
    if (Test-Path -LiteralPath $temporaryOutput) {
        Remove-Item -LiteralPath $temporaryOutput -Force
    }
}
