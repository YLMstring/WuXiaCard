extends SceneTree

const Settings = preload("res://scripts/game_settings.gd")
const Uploader = preload("res://scripts/balance_telemetry_uploader.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(
		Uploader.classify_response(HTTPRequest.RESULT_SUCCESS, 200) == Uploader.RESPONSE_SUCCESS,
		"HTTP success confirms a report"
	)
	_check(
		Uploader.classify_response(HTTPRequest.RESULT_SUCCESS, 409) == Uploader.RESPONSE_SUCCESS,
		"Duplicate report conflicts are idempotent success"
	)
	_check(
		Uploader.classify_response(HTTPRequest.RESULT_CANT_CONNECT, 0) == Uploader.RESPONSE_RETRY,
		"Connection failures remain retryable"
	)
	_check(
		Uploader.classify_response(HTTPRequest.RESULT_SUCCESS, 429) == Uploader.RESPONSE_RETRY
		and Uploader.classify_response(HTTPRequest.RESULT_SUCCESS, 503) == Uploader.RESPONSE_RETRY,
		"Rate limits and server failures remain retryable"
	)
	_check(
		Uploader.classify_response(HTTPRequest.RESULT_SUCCESS, 400) == Uploader.RESPONSE_PERMANENT,
		"Invalid client payloads are permanent for the current report"
	)
	_check(Uploader.is_valid_endpoint("https://example.com/v1/reports"), "HTTPS endpoints are accepted")
	_check(not Uploader.is_valid_endpoint("http://example.com"), "Plain HTTP endpoints are rejected")
	_check(
		Uploader.event_endpoint_from_report_endpoint("https://example.com/v1/reports")
			== "https://example.com/v1/events",
		"The event endpoint is derived from the configured report route"
	)
	_check(
		Uploader.event_endpoint_from_report_endpoint("https://example.com/v1/reports/")
			== "https://example.com/v1/events"
		and Uploader.event_endpoint_from_report_endpoint("https://example.com/v1/other").is_empty(),
		"Endpoint derivation tolerates a trailing slash and rejects an unrelated route"
	)
	_check(
		Settings.should_capture_balance_telemetry(false, false, false),
		"Normal exported runtime captures telemetry"
	)
	_check(
		not Settings.should_capture_balance_telemetry(true, false, false)
		and not Settings.should_capture_balance_telemetry(false, true, false)
		and not Settings.should_capture_balance_telemetry(false, false, true),
		"Testing, editor, and headless runtimes do not capture by default"
	)
	_check(
		Settings.should_capture_balance_telemetry(false, true, true, true),
		"Tests may explicitly enable isolated local capture"
	)
	_check(
		Settings.should_upload_balance_telemetry(
			true, true, "https://example.com/v1/reports", "Windows"
		)
		and Settings.should_upload_balance_telemetry(
			true, true, "https://example.com/v1/reports", "Android"
		),
		"Only configured Windows and Android exports may upload"
	)
	_check(
		not Settings.should_upload_balance_telemetry(
			false, true, "https://example.com/v1/reports", "Windows"
		)
		and not Settings.should_upload_balance_telemetry(
			true, false, "https://example.com/v1/reports", "Windows"
		)
		and not Settings.should_upload_balance_telemetry(
			true, true, "", "Windows"
		)
		and not Settings.should_upload_balance_telemetry(
			true, true, "https://example.com/v1/reports", "Linux"
		),
		"Disabled, unconfigured, and unsupported runtimes cannot upload"
	)

	var uploader := Uploader.new()
	root.add_child(uploader)
	uploader.configure(null, "", false)
	_check(not uploader.try_upload_pending(), "A disabled uploader never starts a request")
	uploader.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("BALANCE_TELEMETRY_UPLOADER_TESTS_PASSED checks=%d" % _checks)
	else:
		push_error(
			"BALANCE_TELEMETRY_UPLOADER_TESTS_FAILED failures=%d checks=%d"
			% [_failures, _checks]
		)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("CHECK_FAILED: %s" % message)
