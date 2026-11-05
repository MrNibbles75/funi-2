class_name PlayerRemote
extends CharacterBody2D

func update_from_event(player_data: Dictionary):
	global_position = Vector2(
		player_data["position_x"], 
		player_data["position_y"], 
	)

	$Sprite2D.modulate = player_data["color"]
