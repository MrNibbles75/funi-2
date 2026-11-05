extends HTTPRequest

@export var player: PlayerLocal

const WRITE_INTERVAL := 0.1
const HEARTBEAT_INTERVAL := 2.0
const REQUEST_TIMEOUT := 5.0

var request_pending := false
var pending_for := 0.0
var time_since_write := WRITE_INTERVAL
var cooldown := 0.0
var last_signature := ""
var close_requested := false

func _ready() -> void:
	timeout = REQUEST_TIMEOUT
	get_tree().set_auto_accept_quit(false)
	request_completed.connect(_on_request_completed)
	_install_web_delete_hook()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_begin_close()

func _install_web_delete_hook() -> void:
	if not OS.has_feature("web") or player == null:
		return
	var url := URLS.get_player_url(player.player_id)
	var js := "window.addEventListener('pagehide',function(){fetch(%s,{method:'DELETE',keepalive:true});});" % JSON.stringify(url)
	JavaScriptBridge.eval(js, true)

func _begin_close() -> void:
	if close_requested:
		return
	close_requested = true
	cancel_request()
	request_pending = false
	# Let a cancelled PUT finish so it cannot consume the delete completion.
	await get_tree().process_frame
	if player == null:
		get_tree().quit()
		return
	var url := URLS.get_player_url(player.player_id)
	var done := {"ok": false}
	var on_done := func(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		done["ok"] = true
	request_completed.connect(on_done, CONNECT_ONE_SHOT)
	var err := request(url, PackedStringArray(), HTTPClient.METHOD_DELETE, "")
	if err != OK:
		push_warning("player delete did not start: %s" % error_string(err))
		get_tree().quit()
		return
	print("local player delete %s" % player.player_id)
	var waited := 0.0
	var frames := 0
	while not done["ok"] and waited < 0.75 and frames < 90:
		await get_tree().process_frame
		frames += 1
		waited += get_process_delta_time()
	get_tree().quit()

func _process(delta: float) -> void:
	if close_requested:
		return
	time_since_write += delta
	if request_pending:
		pending_for += delta
		if pending_for > REQUEST_TIMEOUT + 1.0:
			_abandon_stuck_write()
		return
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)
		return
	if time_since_write < WRITE_INTERVAL:
		return
	_send_local_player()

func _abandon_stuck_write() -> void:
	cancel_request()
	request_pending = false
	pending_for = 0.0
	last_signature = ""
	cooldown = 0.5
	push_warning("player write stuck; retrying")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	request_pending = false
	pending_for = 0.0
	if close_requested:
		return
	if result != RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		last_signature = ""
		cooldown = 0.5
		push_warning("player write failed result=%s code=%s" % [result, response_code])

func _send_local_player() -> void:
	if player == null:
		return
	var signature := _signature()
	var changed := signature != last_signature
	var heartbeat := time_since_write >= HEARTBEAT_INTERVAL
	if not changed and not heartbeat:
		return
	var player_data := {
		"id": player.player_id,
		"position_x": player.global_position.x,
		"position_y": player.global_position.y,
		"color": player.player_color.to_html(false),
		"last_seen": Time.get_unix_time_from_system(),
	}
	var player_data_json := JSON.stringify(player_data)
	var url := URLS.get_player_url(player.player_id)
	var err := request(url, PackedStringArray(), HTTPClient.METHOD_PUT, player_data_json)
	if err != OK:
		request_pending = false
		cooldown = 0.5
		push_warning("player write did not start: %s" % error_string(err))
		return
	request_pending = true
	pending_for = 0.0
	time_since_write = 0.0
	last_signature = signature
	print("local player %s" % player_data_json)

func _signature() -> String:
	var pos := player.global_position
	return "%d|%d|%s" % [int(round(pos.x)), int(round(pos.y)), player.player_color.to_html(false)]
