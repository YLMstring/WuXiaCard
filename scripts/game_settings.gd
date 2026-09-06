class_name GameSettings
extends RefCounted


static func should_enable_testing_mode(is_editor_runtime: bool) -> bool:
	return is_editor_runtime


static func default_testing_mode() -> bool:
	# Editor Play uses the editor binary and carries this feature. Export
	# templates do not, including Windows and Android debug exports.
	return should_enable_testing_mode(OS.has_feature("editor"))
