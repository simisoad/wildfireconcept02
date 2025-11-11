extends Node3D

@export var speed = 1.0
@onready var camera_3d: Camera3D = %Camera3D

# Wichtig: Hole die Referenz zum WorldContainer
@onready var world_container: Node3D = %WorldContainer


func _process(delta: float):

	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	# Konvertiere 2D-Input in 3D-Bewegung
	var move_vector = Vector3(direction.x, 0, direction.y).normalized()

	# Bewege den WorldContainer, NICHT den Spieler!
	world_container.position -= move_vector * speed * delta * camera_3d.size
