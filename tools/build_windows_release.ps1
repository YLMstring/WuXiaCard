[CmdletBinding()]
param(
    [string]$EnginePath = "",
    [string]$ProjectRoot = "",
    [string]$TemplateArchive = "",
    [string]$OutputPath = "",
    [string]$ArchivePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$resolvedProject = [System.IO.Path]::GetFullPath($ProjectRoot)

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $resolvedProject "build\windows\九宫论剑.exe"
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutput

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path $resolvedProject "build\九宫论剑-windows-x86_64-0.1.0.zip"
}
$resolvedArchive = [System.IO.Path]::GetFullPath($ArchivePath)

function Resolve-EnginePath {
    param([string]$RequestedPath)

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidates.Add($RequestedPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:SUMMER_ENGINE_EXE)) {
        $candidates.Add($env:SUMMER_ENGINE_EXE)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA "SummerEngine\current\Summer.exe"))
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    foreach ($commandName in @("Summer.exe", "godot.exe", "godot")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    throw "No compatible engine found. Pass -EnginePath or set SUMMER_ENGINE_EXE."
}

$resolvedEngine = Resolve-EnginePath -RequestedPath $EnginePath
$templateDirectory = Join-Path $resolvedProject ".summer\local\export-templates\4.7.2"
$releaseTemplate = Join-Path $templateDirectory "windows_release_x86_64.exe"
$nativeBuildScript = Join-Path $resolvedProject "tools\build_duel_native.ps1"
$engineDirectory = Split-Path -Parent $resolvedEngine
$bundledTemplateCandidates = @(
    (Join-Path $engineDirectory "export_templates\4.7.2.stable.mono\windows_release_x86_64.exe"),
    (Join-Path $engineDirectory "export_templates\4.7.2.stable\windows_release_x86_64.exe")
)

New-Item -ItemType Directory -Force -Path $templateDirectory | Out-Null
$bundledTemplate = $bundledTemplateCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($TemplateArchive) -and $null -ne $bundledTemplate) {
    Copy-Item -LiteralPath $bundledTemplate -Destination $releaseTemplate -Force
    Write-Host "Using Summer Engine bundled template: $bundledTemplate"
} else {
    if ([string]::IsNullOrWhiteSpace($TemplateArchive)) {
        $TemplateArchive = Join-Path $resolvedProject "Godot_v4.7.2-stable_export_templates.tpz"
    }
    $resolvedTemplateArchive = [System.IO.Path]::GetFullPath($TemplateArchive)
    if (-not (Test-Path -LiteralPath $resolvedTemplateArchive -PathType Leaf)) {
        throw "Godot 4.7.2 export template archive not found: $resolvedTemplateArchive"
    }
    & tar -xf $resolvedTemplateArchive -C $templateDirectory --strip-components=1 `
        templates/windows_release_x86_64.exe
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract the Windows x86-64 release template."
    }
    Write-Host "Using template archive: $resolvedTemplateArchive"
}
if (-not (Test-Path -LiteralPath $releaseTemplate -PathType Leaf)) {
    throw "Extracted release template is missing: $releaseTemplate"
}

& $nativeBuildScript -ProjectRoot $resolvedProject -Configuration Release `
    -GodotCppTarget template_debug
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& $nativeBuildScript -ProjectRoot $resolvedProject -Configuration Release `
    -GodotCppTarget template_release
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
& $resolvedEngine --headless --audio-driver Dummy --path $resolvedProject `
    --export-release "Windows Desktop" $resolvedOutput
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) {
    throw "Windows release executable was not created: $resolvedOutput"
}

$releaseLibrary = Join-Path $outputDirectory "duel_native.windows.template_release.x86_64.dll"
if (-not (Test-Path -LiteralPath $releaseLibrary -PathType Leaf)) {
    throw "Windows release native library was not created: $releaseLibrary"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedArchive) | Out-Null
Compress-Archive -LiteralPath @($resolvedOutput, $releaseLibrary) `
    -DestinationPath $resolvedArchive -CompressionLevel Optimal -Force

Write-Host "WINDOWS_RELEASE_BUILD_PASSED"
Write-Host "Executable: $resolvedOutput"
Write-Host "Native DLL: $releaseLibrary"
Write-Host "Archive:    $resolvedArchive"
