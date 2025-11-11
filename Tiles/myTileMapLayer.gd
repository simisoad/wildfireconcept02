class_name MyTileMapLayer extends TileMapLayer

var tile_map_size: int
var lod_level: int
var camera: Camera2D
var sprite: Sprite2D

func _init(p_tile_map_size: int, p_lod_level: int, p_camera: Camera2D) -> void:
	self.tile_map_size = p_tile_map_size
	self.lod_level = p_lod_level
	self.camera = p_camera
	self.sprite = Sprite2D.new()
	self.add_child(self.sprite)
	self.sprite.texture = load('res://addons/_Godot-IDE_/icon.svg')
	self.sprite.scale = Vector2(4,4)
	self.sprite.z_index = 4096
	self.sprite.visible = false
	
	#if self.lod_level == 2:
		#self.modulate = Color(0.8,0.8,0.8)

func delete_empty() -> void:
	var used_cells: Array = self.get_used_cells()
	if used_cells.is_empty():
		self.queue_free()

func _process(delta: float) -> void:
	if !Engine.is_editor_hint():
		pass
		#set_visibility()
	if self.lod_level == 1:
		set_visibility_roads()

func set_visibility_roads() -> void:
	var target_lod: int = 1
	self.visible = false
	if self.camera.zoom.x > 0.04:
		var visible_pos: Vector2 = Vector2(self.global_position.x + self.tile_map_size/2, 
			self.global_position.y + self.tile_map_size/2)
		self.sprite.global_position = visible_pos
		if camera.offset.distance_to(visible_pos) >= 23200:
			if lod_level == target_lod:
				self.visible = false
		else:
			if lod_level == target_lod:
				self.visible = true
		

func set_visibility() -> void:
	var target_lod: int = 2
	self.visible = false
	if self.camera.zoom.x > 0.04:
		target_lod = 1
		
	var visible_pos: Vector2 = Vector2(self.global_position.x + self.tile_map_size/2, 
		self.global_position.y + self.tile_map_size/2)
	self.sprite.global_position = visible_pos
	if camera.offset.distance_to(visible_pos) >= 23200:
		if lod_level == target_lod:
			self.visible = false
	else:
		if lod_level == target_lod:
			self.visible = true


		
