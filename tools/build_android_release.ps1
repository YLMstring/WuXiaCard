[CmdletBinding()]
param(
    [string]$EnginePath = "",
    [string]$ProjectRoot = "",
    [string]$TemplateArchive = "",
    [string]$AndroidSdkRoot = "",
    [string]$SigningKeystore = "",
    [string]$SigningAlias = "androiddebugkey",
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$resolvedProject = [System.IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $resolvedProject "build\android\WuxiaCard-android-arm64-0.1.0.apk"
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)

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
            return [System.IO.Path]::GetFullPath($candidate)
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
$resolvedEngine = Resolve-EnginePath -RequestedPath $EnginePath

$templateDirectory = Join-Path $resolvedProject ".summer\local\export-templates\4.7.2"
$releaseTemplate = Join-Path $templateDirectory "android_release.apk"
$androidSourceTemplate = Join-Path $templateDirectory "android_source.zip"
$templateArchiveWasSpecified = -not [string]::IsNullOrWhiteSpace($TemplateArchive)
$cachedTemplatesExist =
    (Test-Path -LiteralPath $releaseTemplate -PathType Leaf) -and
    (Test-Path -LiteralPath $androidSourceTemplate -PathType Leaf)
if ($templateArchiveWasSpecified -or -not $cachedTemplatesExist) {
    if (-not $templateArchiveWasSpecified) {
        $TemplateArchive = Join-Path $resolvedProject "Godot_v4.7.2-stable_export_templates.tpz"
    }
    $resolvedTemplateArchive = [System.IO.Path]::GetFullPath($TemplateArchive)
    if (-not (Test-Path -LiteralPath $resolvedTemplateArchive -PathType Leaf)) {
        throw "Cached Android templates are missing and the Godot 4.7.2 export template archive was not found: $resolvedTemplateArchive"
    }

    New-Item -ItemType Directory -Force -Path $templateDirectory | Out-Null
    & tar -xf $resolvedTemplateArchive -C $templateDirectory --strip-components=1 `
        templates/android_release.apk templates/android_source.zip
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $releaseTemplate -PathType Leaf)) {
        throw "Failed to extract the Android release template."
    }
    if (-not (Test-Path -LiteralPath $androidSourceTemplate -PathType Leaf)) {
        throw "Failed to extract the Android source template: $androidSourceTemplate"
    }
} else {
    Write-Host "Reusing cached Godot 4.7.2 Android export templates."
}

$androidRoot = Join-Path $resolvedProject "android"
$androidBuildRoot = Join-Path $androidRoot "build"
$androidBuildVersion = Join-Path $androidRoot ".build_version"
$expectedBuildVersion = "4.7.2.stable.mono"
$installedBuildVersion = if (Test-Path -LiteralPath $androidBuildVersion -PathType Leaf) {
    (Get-Content -LiteralPath $androidBuildVersion -Raw).Trim()
} else {
    ""
}
if ($installedBuildVersion -ne $expectedBuildVersion) {
    $resolvedAndroidRoot = [System.IO.Path]::GetFullPath($androidRoot)
    if (-not $resolvedAndroidRoot.StartsWith($resolvedProject + [System.IO.Path]::DirectorySeparatorChar)) {
        throw "Refusing to replace Android template outside the project: $resolvedAndroidRoot"
    }
    if (Test-Path -LiteralPath $androidBuildRoot -PathType Container) {
        $backupRoot = Join-Path $resolvedProject ".summer\local\android-template-backups"
        New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
        $backupName = "build-{0}-{1}" -f `
            ($(if ([string]::IsNullOrWhiteSpace($installedBuildVersion)) { "unknown" } else { $installedBuildVersion })), `
            (Get-Date -Format "yyyyMMdd-HHmmss")
        $backupPath = Join-Path $backupRoot $backupName
        Move-Item -LiteralPath $androidBuildRoot -Destination $backupPath
        Write-Host "Backed up old Android source template: $backupPath"
    }
    New-Item -ItemType Directory -Force -Path $androidBuildRoot | Out-Null
    Expand-Archive -LiteralPath $androidSourceTemplate -DestinationPath $androidBuildRoot -Force
    [System.IO.File]::WriteAllText(
        $androidBuildVersion,
        $expectedBuildVersion,
        [System.Text.UTF8Encoding]::new($false)
    )
    Write-Host "Installed Android source template: $expectedBuildVersion"
}
$androidGdIgnore = Join-Path $androidBuildRoot ".gdignore"
if (-not (Test-Path -LiteralPath $androidGdIgnore -PathType Leaf)) {
    [System.IO.File]::WriteAllText($androidGdIgnore, "")
}
$androidResourceRoot = Join-Path $androidBuildRoot "res"
if (Test-Path -LiteralPath $androidResourceRoot -PathType Container) {
    Get-ChildItem -LiteralPath $androidResourceRoot -Filter "*.import" -File -Recurse |
        Remove-Item -Force
}

# Keep the Android splash visible until Godot has finished setup and can render
# its own boot splash. The stock template only installs a keep condition when
# the Godot boot splash is disabled, which otherwise leaves a blank frame gap
# between the Android and Godot splash screens.
$godotAppPath = Join-Path $androidBuildRoot "src\main\java\com\godot\game\GodotApp.java"
if (-not (Test-Path -LiteralPath $godotAppPath -PathType Leaf)) {
    throw "GodotApp.java was not found in the Android source template: $godotAppPath"
}
$godotAppSource = Get-Content -LiteralPath $godotAppPath -Raw
if (-not $godotAppSource.Contains("keepSplashScreenVisible")) {
    $lineEnding = if ($godotAppSource.Contains("`r`n")) { "`r`n" } else { "`n" }

    $importAnchor = "import android.util.Log;${lineEnding}"
    if (-not $godotAppSource.Contains($importAnchor)) {
        throw "Unable to locate the Java import anchor for the Android splash patch."
    }
    $godotAppSource = $godotAppSource.Replace(
        $importAnchor,
        "${importAnchor}${lineEnding}import java.util.concurrent.atomic.AtomicBoolean;${lineEnding}"
    )

    $classAnchor = "public class GodotApp extends GodotActivity {${lineEnding}"
    if (-not $godotAppSource.Contains($classAnchor)) {
        throw "Unable to locate the GodotApp class anchor for the Android splash patch."
    }
    $godotAppSource = $godotAppSource.Replace(
        $classAnchor,
        "${classAnchor}`tprivate final AtomicBoolean keepSplashScreenVisible = new AtomicBoolean(true);${lineEnding}${lineEnding}"
    )

    $onCreatePattern = '(?ms)\t@Override\r?\n\tpublic void onCreate\(Bundle savedInstanceState\) \{\r?\n\t\tSplashScreen splashScreen = SplashScreen\.installSplashScreen\(this\);\r?\n\t\tEdgeToEdge\.enable\(this\);\r?\n\t\tsuper\.onCreate\(savedInstanceState\);\r?\n\r?\n\t\tGodot godot = getGodot\(\);\r?\n\t\tif \(godot != null && godot\.getDisableGodotSplash\(\)\) \{\r?\n\t\t\tsplashScreen\.setKeepOnScreenCondition\(\(\) -> godot\.getRunStatus\(\) != Godot\.RunStatus\.STARTED\);\r?\n\t\t\}\r?\n\t\}'
    $onCreateReplacement = @(
        "`t@Override",
        "`tpublic void onCreate(Bundle savedInstanceState) {",
        "`t`tSplashScreen splashScreen = SplashScreen.installSplashScreen(this);",
        "`t`tsplashScreen.setKeepOnScreenCondition(() -> keepSplashScreenVisible.get());",
        "`t`tEdgeToEdge.enable(this);",
        "`t`tsuper.onCreate(savedInstanceState);",
        "`t}",
        "",
        "`t@Override",
        "`tpublic void onGodotSetupCompleted() {",
        "`t`tsuper.onGodotSetupCompleted();",
        "`t`tkeepSplashScreenVisible.set(false);",
        "`t}"
    ) -join $lineEnding
    $patchedGodotAppSource = [regex]::Replace(
        $godotAppSource,
        $onCreatePattern,
        $onCreateReplacement,
        1
    )
    if ($patchedGodotAppSource -eq $godotAppSource) {
        throw "Unable to locate the stock onCreate method for the Android splash patch."
    }
    [System.IO.File]::WriteAllText(
        $godotAppPath,
        $patchedGodotAppSource,
        [System.Text.UTF8Encoding]::new($false)
    )
    Write-Host "Patched Android splash handoff in GodotApp.java."
}

$nativeBuildScript = Join-Path $resolvedProject "tools\build_duel_native_android.ps1"
& $nativeBuildScript -ProjectRoot $resolvedProject -AndroidSdkRoot $resolvedSdk `
    -Configuration Release -GodotCppTarget template_release
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$env:ANDROID_HOME = $resolvedSdk
$env:ANDROID_SDK_ROOT = $resolvedSdk
$env:GRADLE_OPTS = (("{0} -Dorg.gradle.daemon=false" -f $env:GRADLE_OPTS).Trim())
if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    $env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutput) | Out-Null
if (Test-Path -LiteralPath $resolvedOutput -PathType Leaf) {
    Remove-Item -LiteralPath $resolvedOutput -Force
}
$logDirectory = Join-Path $resolvedProject ".summer\local\logs"
$stdoutLog = Join-Path $logDirectory "android-release-export.stdout.log"
$stderrLog = Join-Path $logDirectory "android-release-export.stderr.log"
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
Remove-Item -LiteralPath $stdoutLog, $stderrLog -Force -ErrorAction SilentlyContinue
$exportArguments = @(
    "--headless",
    "--audio-driver", "Dummy",
    "--summer-no-publish",
    "--verbose",
    "--path", ('"{0}"' -f $resolvedProject),
    "--export-release", "Android", ('"{0}"' -f $resolvedOutput)
)
$exportProcess = Start-Process -FilePath $resolvedEngine -ArgumentList $exportArguments `
    -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog `
    -Wait -PassThru
if ($exportProcess.ExitCode -ne 0) {
    if (Test-Path -LiteralPath $stdoutLog -PathType Leaf) {
        Get-Content -LiteralPath $stdoutLog -Tail 120
    }
    if (Test-Path -LiteralPath $stderrLog -PathType Leaf) {
        Get-Content -LiteralPath $stderrLog -Tail 120
    }
    exit $exportProcess.ExitCode
}
Write-Host "SUMMER_ANDROID_EXPORT_PASSED"
if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) {
    throw "Android release APK was not created: $resolvedOutput"
}

$nativeEntry = & tar -tf $resolvedOutput |
    Where-Object { $_ -match '^lib/arm64-v8a/libduel_native\.android\.template_release\.arm64\.so$' } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($nativeEntry)) {
    throw "APK does not contain the ARM64 release native rules library."
}

$buildTools = Get-ChildItem -LiteralPath (Join-Path $resolvedSdk "build-tools") -Directory |
    Sort-Object { [version]($_.Name -replace '-rc.*$', '') } -Descending |
    Select-Object -First 1 -ExpandProperty FullName
$apksigner = Join-Path $buildTools "apksigner.bat"
if (-not (Test-Path -LiteralPath $apksigner -PathType Leaf)) {
    throw "apksigner was not found: $apksigner"
}
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $apksigner verify $resolvedOutput 1>$null 2>$null
$initialVerifyExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($initialVerifyExitCode -ne 0) {
    $usingDebugKeystore = [string]::IsNullOrWhiteSpace($SigningKeystore)
    if ($usingDebugKeystore) {
        $SigningKeystore = Join-Path $env:APPDATA "Godot\keystores\debug.keystore"
    }
    if (-not (Test-Path -LiteralPath $SigningKeystore -PathType Leaf)) {
        throw "Signing keystore was not found: $SigningKeystore"
    }

    if ($usingDebugKeystore) {
        Write-Warning "Signing this local release build with the Godot debug keystore."
        & $apksigner sign --v4-signing-enabled false --ks $SigningKeystore `
            --ks-key-alias $SigningAlias --ks-pass "pass:android" --key-pass "pass:android" `
            $resolvedOutput
    } else {
        if ([string]::IsNullOrWhiteSpace($env:WUXIA_ANDROID_KEYSTORE_PASSWORD)) {
            throw "Set WUXIA_ANDROID_KEYSTORE_PASSWORD before using a release keystore."
        }
        if ([string]::IsNullOrWhiteSpace($env:WUXIA_ANDROID_KEY_PASSWORD)) {
            $env:WUXIA_ANDROID_KEY_PASSWORD = $env:WUXIA_ANDROID_KEYSTORE_PASSWORD
        }
        & $apksigner sign --v4-signing-enabled false --ks $SigningKeystore `
            --ks-key-alias $SigningAlias --ks-pass env:WUXIA_ANDROID_KEYSTORE_PASSWORD `
            --key-pass env:WUXIA_ANDROID_KEY_PASSWORD $resolvedOutput
    }
    if ($LASTEXITCODE -ne 0) {
        throw "APK signing failed."
    }
    & $apksigner verify --verbose --print-certs $resolvedOutput
    if ($LASTEXITCODE -ne 0) {
        throw "APK signature verification failed after signing."
    }
}

Write-Host "ANDROID_RELEASE_BUILD_PASSED"
Write-Host "APK:        $resolvedOutput"
Write-Host "Native lib: $nativeEntry"
