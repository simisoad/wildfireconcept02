# world_builder.gd
class_name WorldBuilder extends Node3D

var loaded_tile_nodes: Dictionary = {}

var test_colors: Array[Texture2D] = [
	load('res://Tiles/Textures/Grass02_D.png'),
	load('res://Tiles/Textures/Water01_A.png'),
	load('res://Tiles/Textures/Grass01_A.png'),
	load('res://Tiles/Textures/Grass01_F_V2.png'),
	load('res://Tiles/Textures/Grass04_F.png'),
	load('res://Tiles/Textures/GrassSand09.png'),
	load('res://Tiles/Textures/Grass04_B.png'),
	load('res://Tiles/Textures/Grass03_A.png'),
	load('res://Tiles/Textures/Grass03_B.png'),
	]
var test_materials: Array[ShaderMaterial] = []
var node: Node3D = Node3D.new()
func _ready() -> void:
	node.rotate_x(deg_to_rad(90))
	self.add_child(node)
	for color in test_colors:
		var new_mat: ShaderMaterial = ShaderMaterial.new()
		var shader: Shader = load('res://Tiles/Shader/Tiles.gdshader')
		new_mat.shader = shader
		var texture: Texture2D = color
		new_mat.set_shader_parameter("texture_atlas", texture)
		test_materials.append(new_mat)

# Wird vom ChunkGenerator aufgerufen, um den Parent-Node zu erstellen
func start_tile_build(build_data: TileBuildData):
	var coord = build_data.parent_coord
	if loaded_tile_nodes.has(coord): return

	var tile_node: Node3D
	if build_data.sub_chunks_to_build.is_empty() and build_data.raster_tile == null:
		tile_node = Node3D.new()
		tile_node.name = "EmptyTile_%s" % coord
	else:
		tile_node = Node3D.new()
		tile_node.name = "Tile_%s" % coord

	var size = float(DebugManager.TILE_WORLD_SIZE)
	tile_node.position = Vector3(coord.x * size, 0, coord.y * size)
	get_parent().add_child(tile_node)
	loaded_tile_nodes[coord] = tile_node

	# Baue sofort Dinge, die nicht per Sub-Chunk kommen (z.B. das Raster-Overlay)
	if DebugManager.should_load_raster_overlay and is_instance_valid(build_data.raster_tile):
		if not build_data.raster_tile == null:
			_build_raster_overlay(tile_node, build_data.raster_tile)

# Wird vom ChunkGenerator für jeden einzelnen Sub-Chunk aufgerufen
func build_chunk_visuals(parent_coord: Vector2i, sub_chunk_data: SubChunkBuildData) -> Node3D:
	var parent_node = loaded_tile_nodes.get(parent_coord)
	if not is_instance_valid(parent_node):
		return

	var sub_chunk_node: Node3D = Node3D.new()
	sub_chunk_node.name = "SubChunk_%s_Res%s" % [sub_chunk_data.coord, sub_chunk_data.resolution]
	var sub_chunk_world_size = float(DebugManager.TILE_WORLD_SIZE) / DebugManager.SUB_CHUNKS_PER_AXIS
	sub_chunk_node.position = Vector3(sub_chunk_data.coord.x * sub_chunk_world_size, 0, sub_chunk_data.coord.y * sub_chunk_world_size)
	sub_chunk_node.scale = Vector3(0.95,0.95,0.95)
	# --- REGELBASIERTE ENTSCHEIDUNGEN ---
	# Hier entscheidest du, WELCHE Art von Visualisierung du baust.

	if DebugManager.should_load_shader_terrain:
		#var start_time: int = Time.get_ticks_usec()
		_build_shader_terrain_for_sub_chunk(sub_chunk_node, sub_chunk_data)
		#print("", Time.get_ticks_usec() - start_time)
	if DebugManager.should_load_multimesh_vegetation:
		#var start_time: int = Time.get_ticks_usec()
		_build_multimesh_for_sub_chunk(sub_chunk_node, sub_chunk_data)
		#print("", Time.get_ticks_usec() - start_time)
	parent_node.add_child(sub_chunk_node)
	return sub_chunk_node

func finish_tile_build(coord: Vector2i):
	if loaded_tile_nodes.has(coord):
		pass
		#print("Kachel fertig gebaut: ", coord)
		# Hier könntest du später Logik hinzufügen, z.B. das "Baking" von Lichtern

func build_empty_tile(coord: Vector2i):
	# Erstelle einen leeren Node, wenn die Datenabfrage fehlschlägt
	var tile_node = Node3D.new()
	tile_node.name = "FailedTile_%s" % coord
	var size = float(DebugManager.TILE_WORLD_SIZE)
	tile_node.position = Vector3(coord.x * size, 0, coord.y * size)
	get_parent().add_child(tile_node)
	loaded_tile_nodes[coord] = tile_node

# Wird vom ChunkGenerator (via Signal vom WorldStreamer) aufgerufen
func remove_tile(coord: Vector2i) -> void:
	if loaded_tile_nodes.has(coord):
		var node = loaded_tile_nodes[coord]
		if is_instance_valid(node):
			node.queue_free()
		loaded_tile_nodes.erase(coord)

func _build_raster_overlay(parent_node: Node3D, raster_tile: Image):

	var raster_sprite: Sprite3D = Sprite3D.new()
	var raster_scale: Vector2i = Vector2i(DebugManager.TILE_WORLD_SIZE, DebugManager.TILE_WORLD_SIZE) / raster_tile.get_size()
	print("raster_scale: ", raster_scale)
	#image_copy.resize(DebugManager.TILE_WORLD_SIZE, DebugManager.TILE_WORLD_SIZE, Image.INTERPOLATE_NEAREST)
	var raster_tex: Texture2D = ImageTexture.create_from_image(raster_tile)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = raster_tex
	#raster_sprite.scale = Vector3(raster_scale.x, raster_scale.x, raster_scale.x)
	raster_sprite.texture = raster_tex
	raster_sprite.material_override = mat
	raster_sprite.position = Vector3(0,5.0, 0)
	raster_sprite.pixel_size =raster_scale.x
	raster_sprite.offset.x = raster_tile.get_size().x/2
	raster_sprite.offset.y = -raster_tile.get_size().y/2
	raster_sprite.rotate_x(deg_to_rad(-90))
	parent_node.add_child(raster_sprite)


func _build_multimesh_for_sub_chunk(sub_chunk_node: Node3D, sub_chunk_task: SubChunkBuildData) -> void:

	#var sub_chunk_coord = sub_chunk_task.coord
	var vegetation_buffers: Dictionary = sub_chunk_task.vegetation_buffers

	if vegetation_buffers.is_empty():
		return # Nichts zu bauen für diesen Sub-Chunk

	#var sub_chunk_world_size = float(DebugManager.TILE_WORLD_SIZE) / DebugManager.SUB_CHUNKS_PER_AXIS
	#
	#var sub_chunk_node = Node3D.new()
	#sub_chunk_node.name = "SubChunk_%s" % sub_chunk_coord
	#sub_chunk_node.position = Vector3(sub_chunk_coord.x * sub_chunk_world_size, 0, sub_chunk_coord.y * sub_chunk_world_size)

	# Die Schleife durchläuft jetzt die fertigen Buffer, nicht mehr die Pixel
	for type_id in vegetation_buffers:
		var data_buffer: PackedFloat32Array = vegetation_buffers[type_id]
		var instance_count = data_buffer.size() / 16 # 16 floats pro Instanz

		if instance_count == 0: continue

		var mmi = MultiMeshInstance3D.new()
		mmi.name = "Vegetation_Type_%s" % type_id
		var multimesh = MultiMesh.new()

		# Konfiguration des MultiMesh
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.instance_count = instance_count

		var plane_mesh = PlaneMesh.new()
		plane_mesh.size = Vector2(2, 2)
		plane_mesh.orientation = PlaneMesh.FACE_Y
		multimesh.mesh = plane_mesh

		mmi.material_override = test_materials[type_id]

		multimesh.set_buffer(data_buffer)

		mmi.multimesh = multimesh
		sub_chunk_node.add_child(mmi)
	#if is_instance_valid(parent_node):
		#parent_node.add_child(sub_chunk_node)



func _build_shader_terrain_for_sub_chunk(sub_chunk_node: Node3D, sub_chunk_task: SubChunkBuildData):
	var sub_chunk_world_size = float(DebugManager.TILE_WORLD_SIZE) / DebugManager.SUB_CHUNKS_PER_AXIS
	#sub_chunk_res *= DebugManager.TILE_WORLD_SIZE / sub_chunk_res
	var plane_mesh = PlaneMesh.new()

	plane_mesh.size = Vector2(sub_chunk_world_size, sub_chunk_world_size)
	plane_mesh.center_offset = Vector3(plane_mesh.size.x / 2.0, 0.0, plane_mesh.size.y / 2.0)
	plane_mesh.orientation = PlaneMesh.FACE_Y

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = plane_mesh
	var sub_chunk_coord = sub_chunk_task.coord
	mesh_instance.name = "SubChunk_%s" % sub_chunk_coord

	#mesh_instance.position = Vector3(sub_chunk_coord.x * sub_chunk_world_size, 0.0, sub_chunk_coord.y * sub_chunk_world_size)


	# 2. Erstelle das Material und den Shader
	var shader_material = ShaderMaterial.new()
	shader_material.shader = load('res://Shaders/terrain_shader.gdshader') # Dein neuer Shader
	var image: Image = sub_chunk_task.logic_map.duplicate()
	#image.resize(image.get_size().x*10, image.get_size().y*10,Image.INTERPOLATE_NEAREST)
	# 3. Übergebe die Daten an den Shader
	var logic_map_texture: Texture = ImageTexture.create_from_image(image)
	shader_material.set_shader_parameter("logic_map", logic_map_texture)

	# Übergebe auch die echten Terrain-Texturen
	shader_material.set_shader_parameter("farmland_texture", load('res://Terrain_Textures/Farmland.png'))
	shader_material.set_shader_parameter("forest_texture", load('res://Terrain_Textures/Forest.png'))
	shader_material.set_shader_parameter("grass_texture", load('res://Terrain_Textures/Grass.png'))
	shader_material.set_shader_parameter("grassland_texture", load('res://Terrain_Textures/Grassland.png'))
	shader_material.set_shader_parameter("residential_texture", load('res://Terrain_Textures/residential.png'))
	shader_material.set_shader_parameter("vineyard_texture", load('res://Terrain_Textures/vineyard.png'))
	shader_material.set_shader_parameter("water_texture", load('res://Terrain_Textures/Water.png'))


	mesh_instance.material_override = shader_material

	if is_instance_valid(sub_chunk_node):
		sub_chunk_node.add_child(mesh_instance)
