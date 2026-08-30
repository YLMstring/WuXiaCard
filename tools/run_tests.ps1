[CmdletBinding()]
param(
    [string]$EnginePath = "",
    [string]$ProjectRoot = "",
    [switch]$ShowFullOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

$resolvedProject = [System.IO.Path]::GetFullPath($ProjectRoot)
$projectFile = Join-Path $resolvedProject "project.godot"
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
    throw "Godot project not found: $projectFile"
}

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
$testScripts = @(
    "test_card_catalog.gd",
    "test_deck_rules.gd",
	"test_difficulty_rules.gd",
    "test_sect_catalog.gd",
    "test_enemy_catalog.gd",
    "test_deck_profile_store.gd",
    "test_ending_profile.gd",
    "test_deck_library_grid.gd",
    "test_deck_builder_integration.gd",
    "test_sect_selection_integration.gd",
    "test_main_menu.gd",
    "test_ending_scene.gd",
	"test_music_director.gd",
	"test_music_flow.gd",
    "test_main_flow.gd",
    "test_ending_flow.gd",
    "test_card_inspector.gd",
    "test_duel_backdrop.gd",
    "test_duel_outcome.gd",
	"test_card_mastery.gd",
	"test_duel_replay_record.gd",
	"test_duel_replay.gd",
    "test_enemy_memory.gd",
    "test_reward_profile.gd",
    "test_reward_selection_integration.gd",
    "test_duel_rules.gd",
	"test_duel_opening_setup.gd",
    "test_duel_card_selector.gd",
	"test_duel_simulator.gd",
	"test_duel_state_key.gd",
	"test_duel_compact_state.gd",
    "test_duel_search.gd",
	"test_duel_ai_benchmark.gd",
	"test_activation_targeting_swap_presentation.gd",
	"test_taishan_wudafu.gd",
	"test_taishan_wudafu_integration.gd",
	"test_qixin_luochangkong_abilities.gd",
	"test_tianchang_hengshan_abilities.gd",
	"test_wanyue_dasongyang_abilities.gd",
	"test_power_change_integration.gd",
	"test_yinyang_zhangli_abilities.gd",
	"test_hanbin_tianwai_abilities.gd",
	"test_internal_energy_abilities.gd",
	"test_jingang_buhuai_abilities.gd",
	"test_jingang_buhuai_integration.gd",
	"test_baocan_lijing_abilities.gd",
	"test_shaolin_discard_abilities.gd",
	"test_nianhua_sanru_abilities.gd",
	"test_fumo_qianshou_abilities.gd",
	"test_fumo_qianshou_integration.gd",
	"test_dugu_nine_swords_abilities.gd",
	"test_kuihua_abilities.gd",
	"test_taiji_abilities.gd",
	"test_wudang_nine_cards.gd",
	"test_tiyunzong_abilities.gd",
	"test_tiyunzong_integration.gd",
	"test_leizhen_huzhua_abilities.gd",
	"test_hengshan_three_families.gd",
	"test_jianfa_yanhui_abilities.gd",
	"test_jianfa_yanhui_integration.gd",
	"test_jinzhen_wanhua_abilities.gd",
	"test_jinzhen_wanhua_integration.gd",
	"test_mianli_cangzhen3.gd",
	"test_mianli_cangzhen3_integration.gd",
	"test_ki_bead_presentation.gd",
    "test_youfen_integration.gd",
    "test_zixia_integration.gd",
    "test_cangsong_sanqin_abilities.gd",
	"test_laihe_qinquan_abilities.gd",
    "test_duel_integration.gd"
)

$failedSuites = [System.Collections.Generic.List[string]]::new()
$totalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "Engine:  $resolvedEngine"
Write-Host "Project: $resolvedProject"

foreach ($testScript in $testScripts) {
    $resourcePath = "res://tests/$testScript"
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    $suiteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $arguments = @(
            "--headless",
            "--path",
            ('"{0}"' -f $resolvedProject),
            "--script",
            $resourcePath
        )
        $process = Start-Process `
            -FilePath $resolvedEngine `
            -ArgumentList $arguments `
            -Wait `
            -PassThru `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $suiteStopwatch.Stop()
        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        $combined = "$stdout`n$stderr"
        $hasPassMarker = $combined -match "(?m)^[A-Z0-9_]+_PASSED\b"
        $hasFailureText = $combined -match "(?im)_FAILED\b|CHECK_FAILED\b|SCRIPT ERROR:|^ERROR:"
        $passed = $process.ExitCode -eq 0 -and $hasPassMarker -and -not $hasFailureText

        if ($passed) {
            $marker = [regex]::Match($combined, "(?m)^[A-Z0-9_]+_PASSED[^\r\n]*").Value.Trim()
            Write-Host ("PASS {0} ({1:N2}s) {2}" -f $testScript, $suiteStopwatch.Elapsed.TotalSeconds, $marker)
            if ($ShowFullOutput) {
                Write-Host $combined.Trim()
            }
        }
        else {
            $failedSuites.Add($testScript)
            Write-Host ("FAIL {0} ({1:N2}s, exit {2})" -f $testScript, $suiteStopwatch.Elapsed.TotalSeconds, $process.ExitCode)
            Write-Host $combined.Trim()
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

$totalStopwatch.Stop()
if ($failedSuites.Count -gt 0) {
    Write-Host ("FAILED: {0} suite(s): {1}" -f $failedSuites.Count, ($failedSuites -join ", "))
    exit 1
}

Write-Host ("ALL_TEST_SUITES_PASSED: {0} suite(s) in {1:N2}s" -f $testScripts.Count, $totalStopwatch.Elapsed.TotalSeconds)
exit 0
