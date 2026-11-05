class_name PlayerRemote
extends CharacterBody2D

func update_from_event(player_data: Dictionary) -> void:
	var x = player_data.get("position_x", global_position.x)
	var y = player_data.get("position_y", global_position.y)
	if (x is int or x is float) and (y is int or y is float):
		global_position = Vector2(float(x), float(y))
	var color_text := str(player_data.get("color", "ffffff"))
	$Sprite2D.modulate = Color.from_string(color_text, Color.WHITE)
