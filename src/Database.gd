extends Node

var host = "https://godot-mmo-thang-default-rtdb.firebaseio.com"

func get_player_url(player_id):
	return host + ("/players/%s.json" % player_id)

func get_all_player_urls():
	return host + ("/players.json")
