extends Node

@export var player_local: PlayerLocal
@export var remote_player_scene: PackedScene

var http_client: = HTTPClient.new()

var player_remote: Dictionary

func _ready() -> void :
	_setup_comunications()

func _setup_comunications():
	http_client.connect_to_host(URLS.host)

	var status = http_client.get_status()
	while status in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		http_client.poll()
		status = http_client.get_status()

	if status != HTTPClient.STATUS_CONNECTED:
		printerr("cant connect to database")
		return

	http_client.request(
		HTTPClient.METHOD_POST, 
		URLS.get_all_player_urls(), 
		["accept: text/event-stream"]
		)

	print("connection Succsesful!")

func _process(delta: float) -> void :
	_check_for_new_events()

func _check_for_new_events():
	http_client.poll()
	if not http_client.has_response():
		return

	var body = http_client.read_response_body_chunk()
	if not body:
		return

	var response = body.get_string_from_utf8()
	var events = _parse_event_response_data(response)

	for event in events:
		_handle_player_events(event)

func _handle_player_events(event: Dictionary):
	var path = event["path"]
	var data = event["data"]

	if path == "/":
		if data != null:
			for player_id in data.keys():
				_create_or_update_player(player_id, data[player_id])
		for player_id in player_remote.keys():
			if data == null or player_id not in data.keys():
				delete_player(player_id)
	else:
		var player_id = path.split("/")[-1]
		if data == null:
			delete_player(player_id)
		else:
			_create_or_update_player(player_id, data)

func _create_or_update_player(player_id: String, player_data: Dictionary):
	if player_id == str(player_local.player_id):
		return

	var player = PlayerRemote
	if player_id in player_remote:
		player = player_remote[player_id]
	else:
		player = remote_player_scene.instantiate()
		add_child(player)

	player.update_from_event(player_data)
	player_remote[player_id] = player

func delete_player(player_id: String):
	if player_id == str(player_local.player_id):
		return

	if player_id not in player_remote:
		return

	var player = player_remote[player_id]
	player.queue_free()

func _parse_event_response_data(response: String) -> Array:
	var response_parts = response.replace("\r", "").split("\n\n")
	var event_data: Array[Dictionary] = []
	for response_part in response_parts:
		var event = _parse_event_data(response_part)
		if event == null:
			continue
		if event.type != "put":
			continue
		event_data.append(event.data)
	return event_data

class ServerSentEvent:
	var type: String
	var data: Dictionary

const EVENT_TYPE_PREFIX = "event: "
const EVENT_DATA_PREFIX = "data: "

func _parse_event_data(response_part) -> ServerSentEvent:
	var event_lines = response_part.split("\n")
	if event_lines.size() != 2:
		return null


	var event_type_line = event_lines[0]
	if !event_type_line.begins_with(EVENT_TYPE_PREFIX):
		return null

	var event_data_line = event_lines[1]
	if !event_data_line.begins_with(EVENT_DATA_PREFIX):
		return null

	var event_type_str = event_type_line.substr(EVENT_TYPE_PREFIX.length())
	var event_data_str = event_data_line.substr(EVENT_DATA_PREFIX.length())

	var event_data_json = JSON.parse_string(event_data_str)
	if event_data_json == null:
		event_data_json = {}

	var event = ServerSentEvent.new()
	event.type = event_type_str
	event.data = event_data_json

	return event
