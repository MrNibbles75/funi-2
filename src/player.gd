class_name PlayerLocal
extends CharacterBody2D

var player_id = randi_range(100000, 999999)
var player_color: Color = Color.from_hsv(randf(), 0.6, 1)

const SPEED = 300.0

func _ready() -> void :
	$Sprite2D.modulate = player_color

func _physics_process(delta: float) -> void :
	var direction: = Input.get_vector("left", "right", "up", "down")
	if direction:
		velocity = direction * SPEED
	else:
		velocity = lerp(velocity, Vector2.ZERO, 0.1)

	move_and_slide()
