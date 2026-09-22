[CmdletBinding()]
param(
	[ValidateSet("All", "Reports", "Events")]
	[string]$Dataset = "All",
    [ValidateSet("Csv", "Json")]
    [string]$Format = "Csv",
    [string]$Endpoint = "",
    [string]$From = "",
    [string]$To = "",
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Dataset -eq "All" -and -not [string]::IsNullOrWhiteSpace($OutputPath)) {
	throw "-OutputPath can only be used when downloading a single dataset."
}

if ([string]::IsNullOrWhiteSpace($Endpoint)) {
    $Endpoint = $env:WUXIA_TELEMETRY_ADMIN_ENDPOINT
}
if ([string]::IsNullOrWhiteSpace($Endpoint)) {
    $Endpoint = [Environment]::GetEnvironmentVariable("WUXIA_TELEMETRY_ADMIN_ENDPOINT", "User")
}
$adminToken = $env:WUXIA_TELEMETRY_ADMIN_TOKEN
if ([string]::IsNullOrWhiteSpace($adminToken)) {
    $adminToken = [Environment]::GetEnvironmentVariable("WUXIA_TELEMETRY_ADMIN_TOKEN", "User")
}
if ([string]::IsNullOrWhiteSpace($Endpoint)) {
    throw "Pass -Endpoint or set WUXIA_TELEMETRY_ADMIN_ENDPOINT."
}
if (-not $Endpoint.StartsWith("https://", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The telemetry admin endpoint must use HTTPS."
}
if ([string]::IsNullOrWhiteSpace($adminToken)) {
    throw "Set WUXIA_TELEMETRY_ADMIN_TOKEN in the current shell or user environment."
}

$selectedDatasets = if ($Dataset -eq "All") {
	@("Reports", "Events")
} else {
	@($Dataset)
}
$extension = $Format.ToLowerInvariant()
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$exports = [System.Collections.Generic.List[hashtable]]::new()

foreach ($selectedDataset in $selectedDatasets) {
	$query = [System.Collections.Generic.List[string]]::new()
	$query.Add("format=$extension")
	if ($selectedDataset -eq "Events") {
		$query.Add("dataset=events")
	}
	if (-not [string]::IsNullOrWhiteSpace($From)) {
		$query.Add("from=$([uri]::EscapeDataString($From))")
	}
	if (-not [string]::IsNullOrWhiteSpace($To)) {
		$query.Add("to=$([uri]::EscapeDataString($To))")
	}
	$separator = if ($Endpoint.Contains("?")) { "&" } else { "?" }
	$requestUri = "$Endpoint$separator$($query -join '&')"
	$selectedOutputPath = $OutputPath
	if ([string]::IsNullOrWhiteSpace($selectedOutputPath)) {
		$prefix = if ($selectedDataset -eq "Events") {
			"balance-events"
		} else {
			"balance-reports"
		}
		$selectedOutputPath = Join-Path (Get-Location) "$prefix-$stamp.$extension"
	}
	$resolvedOutput = [System.IO.Path]::GetFullPath($selectedOutputPath)
	if (Test-Path -LiteralPath $resolvedOutput) {
		throw "Refusing to overwrite an existing export: $resolvedOutput"
	}
	$exports.Add(@{
		Dataset = $selectedDataset
		RequestUri = $requestUri
		OutputPath = $resolvedOutput
	})
}

foreach ($export in $exports) {
	$resolvedOutput = [string]$export.OutputPath
	$outputDirectory = Split-Path -Parent $resolvedOutput
	if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
		New-Item -ItemType Directory -Path $outputDirectory | Out-Null
	}
	$temporaryOutput = "$resolvedOutput.tmp"
	try {
		Invoke-WebRequest `
			-Uri ([string]$export.RequestUri) `
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
		Write-Host "Downloaded balance $(([string]$export.Dataset).ToLowerInvariant()): $resolvedOutput"
	}
	finally {
		if (Test-Path -LiteralPath $temporaryOutput) {
			Remove-Item -LiteralPath $temporaryOutput -Force
		}
	}
}
