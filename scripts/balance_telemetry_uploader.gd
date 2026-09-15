class_name BalanceTelemetryUploader
extends Node

signal report_uploaded(report_id: String)
signal report_rejected(report_id: String, message: String)

const RESPONSE_SUCCESS: StringName = &"success"
const RESPONSE_RETRY: StringName = &"retry"
const RESPONSE_PERMANENT: StringName = &"permanent"

var _store: RefCounted = null
var _endpoint: String = ""
var _enabled: bool = false
var _request: HTTPRequest = null
var _busy: bool = false
var _active_report_id: String = ""


func configure(store: RefCounted, endpoint: String, enabled: bool) -> void:
	_store = store
	_endpoint = endpoint.strip_edges()
	_enabled = enabled and is_valid_endpoint(_endpoint)
	if _request == null:
		_request = HTTPRequest.new()
		_request.name = "BalanceTelemetryRequest"
		_request.timeout = 15.0
		add_child(_request)
		_request.request_completed.connect(_on_request_completed)


func try_upload_pending() -> bool:
	if not _enabled or _busy or _store == null or _request == null:
		return false
	var report: Dictionary = _next_uploadable_report()
	if report.is_empty():
		return false
	_active_report_id = String(report.get("report_id", ""))
	_busy = true
	var request_error: Error = _request.request(
		_endpoint,
		["Content-Type: application/json", "Accept: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(report)
	)
	if request_error == OK:
		return true
	_busy = false
	_active_report_id = ""
	return false


func is_busy() -> bool:
	return _busy


static func is_valid_endpoint(endpoint: String) -> bool:
	return endpoint.strip_edges().begins_with("https://")


static func classify_response(result: int, response_code: int) -> StringName:
	if result != HTTPRequest.RESULT_SUCCESS or response_code == 0:
		return RESPONSE_RETRY
	if response_code >= 200 and response_code < 300:
		return RESPONSE_SUCCESS
	# The report endpoint reserves conflict for an already stored report_id.
	if response_code == 409:
		return RESPONSE_SUCCESS
	if response_code == 429 or response_code >= 500:
		return RESPONSE_RETRY
	if response_code >= 400 and response_code < 500:
		return RESPONSE_PERMANENT
	return RESPONSE_RETRY


func _next_uploadable_report() -> Dictionary:
	for report: Dictionary in _store.get_pending_reports():
		if String(report.get("permanent_error", "")).is_empty():
			return report
	return {}


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if not _busy:
		return
	var report_id: String = _active_report_id
	_busy = false
	_active_report_id = ""
	var classification: StringName = classify_response(result, response_code)
	if classification == RESPONSE_SUCCESS:
		if _store.confirm_report_uploaded(report_id):
			report_uploaded.emit(report_id)
			try_upload_pending.call_deferred()
		return
	if classification == RESPONSE_PERMANENT:
		var message: String = body.get_string_from_utf8().strip_edges().left(500)
		if message.is_empty():
			message = "HTTP %d" % response_code
		if _store.record_permanent_error(report_id, message):
			report_rejected.emit(report_id, message)
			try_upload_pending.call_deferred()
	# Retryable failures deliberately stop here. A later main-menu visit or
	# completed run starts a fresh attempt without a disconnected hot loop.
