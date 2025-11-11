@tool
extends Control



@export_tool_button("Create Chunk")
var create_chunk = create_chunk_parts_editor.bind()

var tile_map_layers: Array
@onready var tile_set: TileSet = load('res://Tiles/BlendingTest.tres')

@onready var marker_2d: Marker2D = %Marker2D
#@onready var layers: Node2D = %Layers
@onready var ref_image: Sprite2D = %RefImage
@onready var tiles_dict: Dictionary = {
	"#354248": [null,[0,1]],
	#"#575757": [null,[26]],
	#"#828282": [null,[33]],
	#"#d4d4d4": [null,[34,35,36]],
	#"#b7b7b7": [null,[23,24,25]],
	"#6e9316": [null,[3,4]],
	"#c4af94": [null,[59,61]],
	"#785426": [null,[11,12,13]],
	"#919338": [null,[39,40,41]],
}

@onready var tiles_dict_roads: Dictionary = {
	"#575757": [null,[26]],
	"#828282": [null,[33]],
	"#d4d4d4": [null,[34,35,36]],
	"#b7b7b7": [null,[23,24,25]]
}
# #354248 Forrest
# #575757 Asphalt
# #828282 AsphaltOverlay
# #D4D4D4 Gravel/Sand
# #6E9316 Grass01
# #C4AF94 Grass02
# #785426 Grass03
# #919338 Grass04

@onready var LODs: Dictionary = {
		"LOD01": null,
		"LOD02": null,
		}



@onready var tile_size: float = 128.0
@onready var road_mm_pos: Array

@onready var create_roads: bool = false


@onready var material_mm: ShaderMaterial = ShaderMaterial.new()

func _mvt_test() -> void:
	var bytes_gz: PackedByteArray = FileAccess.get_file_as_bytes("res://186.pbf")
	var bytes = bytes_gz.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var my_tile: MvtTile = MvtTile.read(bytes)
	var layers = my_tile.layer_names()
	print("Gefundene Layer: ", layers)
	
	var data_sqlite = SQLite.new()
	data_sqlite.path = "res://db/languedoc-roussillon.mbtiles"
	data_sqlite.open_db()

	
func _ready() -> void:
	_mvt_test()
	
	#var atlas: AtlasTexture = AtlasTexture.new()
	#atlas.atlas = load('res://Tiles/Textures/Trees01.png')
	#var atlas2: TileSetAtlasSource
	#var what: TileSetAtlasSource = self.tile_set.get_source(1)
	#var new_texture: Texture2D = what.get_runtime_texture()
	#var new_texture_rect: Rect2 = what.get_runtime_tile_texture_region(Vector2(0,0),0)
	#print(new_texture_rect)
	

	var texture: Texture2D = load('res://Tiles/Textures/Asphalt01.png')
	var shader: Shader = load('res://Tiles/Shader/Tiles.gdshader')
	material_mm.shader = shader
	material_mm.set_shader_parameter("texture_atlas", texture)

	#
	if !Engine.is_editor_hint():
		pass
		create_chunk_parts(128.0)
		
func create_chunk_parts_editor() -> void:
	create_chunk_parts(128.0)
	
func create_chunk_parts(p_image_size: float) -> void:
	var images_dict: Dictionary = load_images('res://RefImages/Chunk00_2/')
	var image_dict_size: int = images_dict.size()
	var count: int = 1
	for image: String in images_dict:
		count += 1
		var x_pos: int = image.get_slice("y",0).replace("x","").to_int()
		var y_pos: int = image.get_slice("y",1).replace("y","").to_int()
		#print("x_pos: ", x_pos, ", y_pos: ", y_pos)
		var im_pos: Vector2 = Vector2(p_image_size*x_pos, p_image_size*y_pos)
		createChunks(im_pos, images_dict[image], p_image_size)
		#road_mm_pos.set(im_pos, [])
		if count == image_dict_size:
			self.create_roads = true
		pass
		
	
func createChunks(p_pos: Vector2i, p_texture: Texture2D, p_image_size: float):	
	ref_image.texture = p_texture
	#set_new_tile_layers(2, p_pos, p_image_size, self.tiles_dict)
	#load_terrain(2, self.tiles_dict, p_pos)
	
	set_new_tile_layers(1, p_pos, p_image_size, self.tiles_dict_roads)
	load_terrain(1, self.tiles_dict_roads,p_pos, true)
	
	#set_new_tile_layers(2, p_pos, p_image_size, self.tiles_dict_roads)
	#load_terrain(2, self.tiles_dict_roads)
#
	#set_new_tile_layers(1, p_pos, p_image_size, self.tiles_dict_roads)
	#load_terrain(1, self.tiles_dict_roads)
	
	#set_new_tile_layers(3, p_pos, p_image_size)
	#load_terrain(3)
	
	
func load_images(p_path: String) -> Dictionary:
	var images_dict: Dictionary = {}
	for file_name in DirAccess.get_files_at(p_path):
		if (file_name.get_extension() == "png"):
			var im_name: String = file_name.replace(".png", "")
			var image: Texture2D = load(p_path + file_name)
			images_dict[im_name] = image

	return images_dict

func set_new_tile_layers(lod_level: float, pos: Vector2, p_image_size: float, p_tiles_dict: Dictionary) -> void:
	var new_LOD_name: String = "LOD0" + str(int(lod_level))
	var new_LOD_node: Node2D 
	if LODs.get(new_LOD_name) == null:
		new_LOD_node = Node2D.new()
		#new_LOD_node.scale *= 0.25
		new_LOD_node.scale *= lod_level
		new_LOD_node.name = new_LOD_name
		self.add_child(new_LOD_node)
		new_LOD_node.owner = get_tree().edited_scene_root
	else:
		new_LOD_node = LODs.get(new_LOD_name)
	
	#self.LODs.assign()
	self.LODs.set(new_LOD_name, new_LOD_node)
	var new_tile_layer: MyTileMapLayer = MyTileMapLayer.new(p_image_size*tile_size, lod_level, %Camera2D)
	new_tile_layer.tile_set = load('res://Tiles/BlendingTest.tres')
	#new_tile_layer.material = load('res://Tiles/BlendingTest3.tres')
	new_tile_layer.collision_enabled = false
	new_tile_layer.rendering_quadrant_size = 1024
	new_LOD_node.add_child(new_tile_layer)
	new_tile_layer.owner = get_tree().edited_scene_root
	var corrected_pos: Vector2 = pos*tile_size
	new_tile_layer.position = (corrected_pos) / lod_level
	for tiles in p_tiles_dict:

		#var vis_on_screen: ChunkTileVisible = ChunkTileVisible.new(new_tile_layer)
		#new_LOD_node.add_child(vis_on_screen)
		
		#vis_on_screen.rect = Rect2(0,0,p_image_size*tile_size,p_image_size*tile_size)
		#vis_on_screen.position = corrected_pos / lod_level
		p_tiles_dict[tiles][0] = new_tile_layer

		#print("Node: ", vis_on_screen, " script: ",vis_on_screen.get_script())
		
		

func load_terrain(lod_level: int, p_tiles_dict: Dictionary,p_pos: Vector2, is_road: bool = false) -> void:
	var image: Image = ref_image.texture.get_image()
	for y in range(0, image.get_height(), lod_level):
		for x in range(0, image.get_height(), lod_level):
			var array: Array
			
			var pixel_color: String = "#" + str(image.get_pixel(x,y).to_html(false))
			if p_tiles_dict.get(pixel_color) != null:
				if is_road:
					pass
					road_mm_pos.append(Vector2(x/lod_level+p_pos.x,y/lod_level+p_pos.y))
				else:
					p_tiles_dict[pixel_color][0].set_cell(Vector2i(x/lod_level,y/lod_level),p_tiles_dict[pixel_color][1].pick_random(),Vector2i(randi_range(0,3), randi_range(0,3)))
	for tile in p_tiles_dict:
		var tile_map_layer: MyTileMapLayer = p_tiles_dict[tile][0]
		tile_map_layer.delete_empty()
	if is_road and self.create_roads:
		var road_mm_size: int = road_mm_pos.size()
		var road_mm: MultiMeshInstance2D = MultiMeshInstance2D.new()
		var mulitmesh: MultiMesh = MultiMesh.new()
		mulitmesh.transform_format = MultiMesh.TRANSFORM_2D
		var quad_mesh: Mesh = PlaneMesh.new()
		quad_mesh.size = Vector2(256,256)
		quad_mesh.orientation = PlaneMesh.FACE_Z
		
		
		mulitmesh.mesh = quad_mesh
		road_mm.multimesh = mulitmesh
		road_mm.multimesh.use_custom_data = true
		road_mm.multimesh.instance_count = road_mm_size
		#var texture: Texture2D = load('res://Tiles/Textures/Asphalt_01.png')
		var atlas_tex: AtlasTexture = AtlasTexture.new()
		#atlas_tex.atlas = texture
		atlas_tex.region = Rect2(0,0,256,256)
		
		var textures_dict: Dictionary = load_images('res://Tiles/Textures/Asphalt/')
		#print(textures_dict.size())
		#road_mm.material = load('res://Tiles/Shader/Tiles.tres')
		road_mm.material = material_mm
		for mm in road_mm_size:
		
			#road_mm.material = material_mm#road_mm.texture = textures_dict.get(textures_dict.keys().pick_random())
			road_mm
			road_mm.multimesh.set_instance_transform_2d(mm,Transform2D(0.0,road_mm_pos[mm]*128))
			var custom_data: Color = Color()
			custom_data.r = randi_range(0, 15)
			
			road_mm.multimesh.set_instance_custom_data(mm,custom_data)
		road_mm.position = Vector2(256,256)
		
		
		self.add_child(road_mm)


			
func _process(delta: float) -> void:
	$Sprite2D.position = %Camera2D.offset
	pass
	#if %Camera2D.zoom.x < 0.05:
		#LODs.get("LOD01").visible = false
		#LODs.get("LOD02").visible = true
	#else:
		#LODs.get("LOD01").visible = true
		#LODs.get("LOD02").visible = false
	
