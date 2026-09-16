class_name BalanceTelemetryUploader
extends Node

signal report_uploaded(report_id: String)
signal report_rejected(report_id: String, message: String)
signal event_uploaded(event_id: String)
signal event_rejected(event_id: String, message: String)

const RESPONSE_SUCCESS: StringName = &"success"
const RESPONSE_RETRY: StringName = &"retry"
const RESPONSE_PERMANENT: StringName = &"permanent"

var _store: RefCounted = null
var _endpoint: String = ""
var _enabled: bool = false
var _request: HTTPRequest = null
var _busy: bool = false
var _active_kind: StringName = &""
var _active_payload_id: String = ""


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
	var queued_item: Dictionary = _next_uploadable_item()
	if queued_item.is_empty():
		return false
	_active_kind = StringName(String(queued_item.get("kind", "")))
	var payload := queued_item.get("payload", {}) as Dictionary
	_active_payload_id = String(queued_item.get("id", ""))
	_busy = true
	var request_error: Error = _request.request(
		String(queued_item.get("endpoint", "")),
		["Content-Type: application/json", "Accept: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if request_error == OK:
		return true
	_busy = false
	_active_kind = &""
	_active_payload_id = ""
	return false


func is_busy() -> bool:
	return _busy


static func is_valid_endpoint(endpoint: String) -> bool:
	return endpoint.strip_edges().begins_with("https://")


static func event_endpoint_from_report_endpoint(endpoint: String) -> String:
	var normalized: String = endpoint.strip_edges().trim_suffix("/")
	if not normalized.ends_with("/reports"):
		return ""
	return normalized.trim_suffix("/reports") + "/events"


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


func _next_uploadable_item() -> Dictionary:
	for report: Dictionary in _store.get_pending_reports():
		if String(report.get("permanent_error", "")).is_empty():
			return {
				"kind": "report",
				"id": String(report.get("report_id", "")),
				"endpoint": _endpoint,
				"payload": report,
			}
	var event_endpoint: String = event_endpoint_from_report_endpoint(_endpoint)
	if event_endpoint.is_empty():
		return {}
	for player_event: Dictionary in _store.get_pending_events():
		if String(player_event.get("permanent_error", "")).is_empty():
			return {
				"kind": "event",
				"id": String(player_event.get("event_id", "")),
				"endpoint": event_endpoint,
				"payload": player_event,
			}
	return {}


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if not _busy:
		return
	var payload_id: String = _active_payload_id
	var active_kind: StringName = _active_kind
	_busy = false
	_active_kind = &""
	_active_payload_id = ""
	var classification: StringName = classify_response(result, response_code)
	if classification == RESPONSE_SUCCESS:
		var confirmed: bool = (
			_store.confirm_event_uploaded(payload_id)
			if active_kind == &"event"
			else _store.confirm_report_uploaded(payload_id)
		)
		if confirmed:
			if active_kind == &"event":
				event_uploaded.emit(payload_id)
			else:
				report_uploaded.emit(payload_id)
			try_upload_pending.call_deferred()
		return
	if classification == RESPONSE_PERMANENT:
		var message: String = body.get_string_from_utf8().strip_edges().left(500)
		if message.is_empty():
			message = "HTTP %d" % response_code
		var recorded: bool = (
			_store.record_permanent_event_error(payload_id, message)
			if active_kind == &"event"
			else _store.record_permanent_error(payload_id, message)
		)
		if recorded:
			if active_kind == &"event":
				event_rejected.emit(payload_id, message)
			else:
				report_rejected.emit(payload_id, message)
			try_upload_pending.call_deferred()
	# Retryable failures deliberately stop here. A later main-menu visit or
	# completed run starts a fresh attempt without a disconnected hot loop.
