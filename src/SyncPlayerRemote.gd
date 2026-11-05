extends Node

@export var player_local: PlayerLocal
@export var remote_player_scene: PackedScene

## Full-snapshot polling. Godot 4.7 web HTTPClient rejects absolute URLs, and a
## POST is not a Firebase listen. HTTPRequest accepts the full URL.
const POLL_INTERVAL := 0.12
const STALE_SECONDS := 10.0
const REQUEST_TIMEOUT := 5.0

var http: HTTPRequest
var request_pending := false
var pending_for := 0.0
var poll_wait := 0.0
var cooldown := 0.0
var announced_poll := false
var player_remote: Dictionary = {}
var last_logged_pos: Dictionary = {}

func _ready() -> void:
	http = HTTPRequest.new()
	http.name = "ReadPlayers"
	http.timeout = REQUEST_TIMEOUT
	add_child(http)
	http.request_completed.connect(_on_request_completed)
	_poll_players()

func _process(delta: float) -> void:
	poll_wait += delta
	if request_pending:
		pending_for += delta
		if pending_for > REQUEST_TIMEOUT + 1.0:
			_abandon_stuck_poll()
		return
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)
		return
	if poll_wait < POLL_INTERVAL:
		return
	_poll_players()

func _poll_players() -> void:
	poll_wait = 0.0
	if player_local == null:
		push_error("SyncPlayerRemote has no local player")
		return
	# Unknown query keys are ignored by Firebase and keep the browser from
	# reusing a cached snapshot.
	var url := URLS.get_all_player_urls() + "?t=" + str(Time.get_ticks_msec())
	var err := http.request(url, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		request_pending = false
		cooldown = 0.5
		push_warning("player poll did not start: %s" % error_string(err))
		return
	request_pending = true
	pending_for = 0.0

func _abandon_stuck_poll() -> void:
	http.cancel_request()
	request_pending = false
	pending_for = 0.0
	cooldown = 0.5
	push_warning("player poll stuck; retrying")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	request_pending = false
	pending_for = 0.0
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		cooldown = 0.5
		push_warning("player poll failed result=%s code=%s" % [result, response_code])
		return
	var text := body.get_string_from_utf8().strip_edges()
	var players := {}
	if text != "null" and not text.is_empty():
		var parsed = JSON.parse_string(text)
		if not (parsed is Dictionary):
			cooldown = 0.5
			push_warning("player poll returned unexpected JSON")
			return
		players = parsed
	if not announced_poll:
		announced_poll = true
		print("player poll ok")
	_reconcile(players)

func _reconcile(players: Dictionary) -> void:
	var now := Time.get_unix_time_from_system()
	var own_id := str(player_local.player_id)
	var seen := {}
	for raw_id in players.keys():
		var player_id := str(raw_id)
		if player_id == own_id:
			continue
		var data = players[raw_id]
		if not (data is Dictionary):
			continue
		if not _is_fresh(data, now):
			continue
		if not _is_number(data.get("position_x")) or not _is_number(data.get("position_y")):
			continue
		seen[player_id] = true
		_create_or_update_player(player_id, data)
	var gone: Array[String] = []
	for player_id in player_remote.keys():
		if not seen.has(str(player_id)):
			gone.append(str(player_id))
	for player_id in gone:
		delete_player(player_id)

func _is_fresh(data: Dictionary, now: float) -> bool:
	if not data.has("last_seen"):
		return false
	var seen = data["last_seen"]
	if not _is_number(seen):
		return false
	return now - float(seen) <= STALE_SECONDS

func _is_number(value) -> bool:
	return value is int or value is float

func _create_or_update_player(player_id: String, player_data: Dictionary) -> void:
	var player: PlayerRemote = null
	var created := false
	if player_remote.has(player_id):
		var existing = player_remote[player_id]
		if is_instance_valid(existing):
			player = existing
		else:
			player_remote.erase(player_id)
	if player == null:
		player = remote_player_scene.instantiate() as PlayerRemote
		if player == null:
			push_warning("remote player scene is not a PlayerRemote")
			return
		add_child(player)
		player_remote[player_id] = player
		created = true
		print("remote player %s joined" % player_id)
	player.update_from_event(player_data)
	var pos := player.global_position
	var prev = last_logged_pos.get(player_id)
	if created or not (prev is Vector2) or (prev as Vector2).distance_to(pos) >= 1.0:
		print("remote player %s at %s,%s" % [player_id, pos.x, pos.y])
		last_logged_pos[player_id] = pos

func delete_player(player_id: String) -> void:
	if player_local != null and player_id == str(player_local.player_id):
		return
	if not player_remote.has(player_id):
		return
	var player = player_remote[player_id]
	player_remote.erase(player_id)
	last_logged_pos.erase(player_id)
	if is_instance_valid(player):
		player.queue_free()
	print("remote player %s left" % player_id)
