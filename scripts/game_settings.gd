class_name GameSettings
extends RefCounted


static func should_enable_testing_mode(is_editor_runtime: bool) -> bool:
	return is_editor_runtime


static func default_testing_mode() -> bool:
	# Editor Play uses the editor binary and carries this feature. Export
	# templates do not, including Windows and Android debug exports.
	return should_enable_testing_mode(OS.has_feature("editor"))


static func should_capture_balance_telemetry(
	testing_mode: bool,
	is_editor_runtime: bool,
	is_headless_runtime: bool,
	force_local_capture_for_tests: bool = false
) -> bool:
	if testing_mode:
		return false
	if force_local_capture_for_tests:
		return true
	return not is_editor_runtime and not is_headless_runtime


static func should_upload_balance_telemetry(
	capture_enabled: bool,
	telemetry_enabled: bool,
	endpoint: String,
	platform_name: String
) -> bool:
	return (
		capture_enabled
		and telemetry_enabled
		and endpoint.strip_edges().begins_with("https://")
		and platform_name in ["Windows", "Android"]
	)
