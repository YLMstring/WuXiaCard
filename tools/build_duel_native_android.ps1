[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$AndroidSdkRoot = "",
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [ValidateSet("template_debug", "template_release")]
    [string]$GodotCppTarget = "template_release",
    [ValidateSet("arm64-v8a")]
    [string]$AndroidAbi = "arm64-v8a",
    [int]$AndroidApiLevel = 24
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$resolvedProject = [System.IO.Path]::GetFullPath($ProjectRoot)
$nativeRoot = Join-Path $resolvedProject "native\duel_core"
$buildRoot = Join-Path $resolvedProject (
    ".summer\local\native-build\duel-core\android-{0}\{1}" -f $AndroidAbi, $GodotCppTarget
)

if ([string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
    foreach ($candidate in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, "C:\Games")) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            (Test-Path -LiteralPath $candidate -PathType Container)) {
            $AndroidSdkRoot = $candidate
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
    throw "Android SDK not found. Pass -AndroidSdkRoot."
}
$resolvedSdk = [System.IO.Path]::GetFullPath($AndroidSdkRoot)
$ndkRoot = Get-ChildItem -LiteralPath (Join-Path $resolvedSdk "ndk") -Directory |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1 -ExpandProperty FullName
if ([string]::IsNullOrWhiteSpace($ndkRoot)) {
    throw "Android NDK not found under: $resolvedSdk\ndk"
}
$toolchain = Join-Path $ndkRoot "build\cmake\android.toolchain.cmake"
if (-not (Test-Path -LiteralPath $toolchain -PathType Leaf)) {
    throw "Android CMake toolchain not found: $toolchain"
}

$cmake = Get-ChildItem -LiteralPath (Join-Path $resolvedSdk "cmake") -Directory |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName "bin\cmake.exe" } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($cmake)) {
    throw "Android SDK CMake was not found under: $resolvedSdk\cmake"
}
$ninja = Join-Path (Split-Path -Parent $cmake) "ninja.exe"
if (-not (Test-Path -LiteralPath $ninja -PathType Leaf)) {
    throw "Ninja was not found beside CMake: $ninja"
}
if (-not (Test-Path -LiteralPath (Join-Path $nativeRoot "godot-cpp\CMakeLists.txt") -PathType Leaf)) {
    throw "godot-cpp submodule is missing. Run: git submodule update --init --recursive"
}

& $cmake `
    -S $nativeRoot `
    -B $buildRoot `
    -G Ninja `
    "-DCMAKE_MAKE_PROGRAM=$ninja" `
    "-DCMAKE_TOOLCHAIN_FILE=$toolchain" `
    "-DCMAKE_BUILD_TYPE=$Configuration" `
    "-DANDROID_ABI=$AndroidAbi" `
    "-DANDROID_PLATFORM=android-$AndroidApiLevel" `
    "-DANDROID_STL=c++_static" `
    "-DGODOTCPP_API_VERSION=4.7" `
    "-DGODOTCPP_TARGET=$GodotCppTarget"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $cmake --build $buildRoot --target wuxia-duel-native
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$archName = if ($AndroidAbi -eq "arm64-v8a") { "arm64" } else { throw "Unsupported ABI: $AndroidAbi" }
$output = Join-Path $nativeRoot (
    "bin\libduel_native.android.{0}.{1}.so" -f $GodotCppTarget, $archName
)
if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
    throw "Android native library was not created: $output"
}

Write-Host "ANDROID_NATIVE_BUILD_PASSED"
Write-Host "Library: $output"
