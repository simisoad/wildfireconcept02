extends Camera3D

func _ready() -> void:
	self.size = 100.0

func zoom_in():
	var current_zoom = self.size
	self.size = current_zoom * 0.95


func zoom_out():
	var current_zoom = self.size
	self.size = current_zoom * 1.05

func move_offset(event: InputEventMouseMotion):

	var rel_x = event.relative.x
	var rel_y = event.relative.y

	var current_zoom = self.size

	self.h_offset -= rel_x * current_zoom / 300.0
	self.v_offset += rel_y * current_zoom / 300.0
	#self.offset = cam_pos

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and \
		(event.button_mask == MOUSE_BUTTON_MASK_MIDDLE or \
		event.button_mask == MOUSE_BUTTON_MASK_RIGHT):
		self.move_offset(event)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		self.zoom_in()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		self.zoom_out()

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		shoot_ray(event.position)

func shoot_ray(start_pos: Vector2):
	var ray_length = 1000
	var from = project_ray_origin(start_pos)
	var to = from + project_ray_normal(start_pos) * ray_length
	var space = get_world_3d().direct_space_state
	var ray_query = PhysicsRayQueryParameters3D.new()
	ray_query.from = from
	ray_query.to = to
	var raycast_result = space.intersect_ray(ray_query)
	print(raycast_result)
	print("......")
