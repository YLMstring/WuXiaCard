[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$resolvedProject = [System.IO.Path]::GetFullPath($ProjectRoot)
$nativeRoot = Join-Path $resolvedProject "native\duel_core"
$buildRoot = Join-Path $resolvedProject ".summer\local\native-build\duel-core\windows-x86_64"
$cmake = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"

if (-not (Test-Path -LiteralPath $cmake -PathType Leaf)) {
    throw "Visual Studio CMake not found: $cmake"
}
if (-not (Test-Path -LiteralPath (Join-Path $nativeRoot "godot-cpp\CMakeLists.txt") -PathType Leaf)) {
    throw "godot-cpp submodule is missing. Run: git submodule update --init --recursive"
}

& $cmake `
    -S $nativeRoot `
    -B $buildRoot `
    -G "Visual Studio 18 2026" `
    -A x64
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $cmake --build $buildRoot --config $Configuration --target wuxia-duel-native
exit $LASTEXITCODE
