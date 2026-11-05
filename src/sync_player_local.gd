extends HTTPRequest

@export var player: PlayerLocal

var host = "https://godot-mmo-thang-default-rtdb.firebaseio.com/"

var request_pending: bool
var prev_player_data_json: String

func _ready() -> void :
	get_tree().set_auto_accept_quit(false)
	request_completed.connect(_on_request_completed)

func _notification(what: int) -> void :
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		delete_local_player()

func delete_local_player():
	var url = URLS.get_player_url(player.player_id)
	cancel_request()
	request(url, [], HTTPClient.METHOD_DELETE, "")
	await request_completed
	get_tree().quit()

func _on_request_completed(
	result: int, 
	response_code: int, 
	_headers: PackedStringArray, 
	_body: PackedByteArray, 
) -> void :
	if result != RESULT_SUCCESS:
		printerr("requst failed. respond code " + str(response_code))
	request_pending = false

func _process(delta: float) -> void :
	if !request_pending:
		_send_local_player()

func _send_local_player() -> void :
	var player_data = {
		"id": player.player_id, 
		"position_x": player.global_position.x, 
		"position_y": player.global_position.y, 
		"color": player.player_color.to_html(false)
	}

	var player_data_json = JSON.stringify(player_data)
	if player_data_json == prev_player_data_json:
		return
	prev_player_data_json = player_data_json

	request_pending = true
	var url = URLS.get_player_url(player.player_id)

	request(url, [], HTTPClient.METHOD_PUT, player_data_json)
	print(player_data_json)
