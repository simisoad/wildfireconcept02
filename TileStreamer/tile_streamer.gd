# TileStreamer.gd
extends Node

# --- Konfiguration ---
const TILE_ZOOM_LEVEL = 14 # Wir arbeiten vorerst mit einem festen Zoom-Level
const TILE_PIXEL_SIZE = 64 # Die Grösse unserer generierten Meshes
const LOAD_BUFFER = 1 # Wie viele Kacheln über den Bildschirmrand hinaus laden?

# --- Referenzen ---
var world_container: Node3D
var camera: Camera3D
var debug: Label
# --- Status ---
var loaded_tiles: Dictionary = {} # Speichert geladene Kacheln: {Vector2i(x,y): Node}
var current_tile_coords = Vector2i(-100, -100) # Startwert ausserhalb der Welt

# --- Threads ---
var db_mutex = Mutex.new()
var running_threads: Dictionary = {} # Verfolgt laufende Threads pro Kachel
var creation_queue: Array = [] # Warteschlange für fertige Kacheln
var current_creation_task: Dictionary = {}
var current_feature_index: int = 0

var test_colors: Array[Color] = [
	Color.AQUA,
	Color.GREEN_YELLOW,
	Color.YELLOW_GREEN,
	Color.BURLYWOOD,
	Color.DARK_OLIVE_GREEN,
	Color.SEA_GREEN,
	Color.DARK_GREEN,
	Color.DARK_GREEN,
	]
var test_materials: Array[StandardMaterial3D] = []
func _ready() -> void:
	# Wir warten einen Frame, damit die Hauptszene sicher geladen ist
	await get_tree().process_frame
	for color in test_colors:
		var new_mat: StandardMaterial3D = StandardMaterial3D.new()
		new_mat.albedo_color = color
		test_materials.append(new_mat)
		
	# Hole die Referenzen aus dem Szenenbaum
	world_container = get_tree().root.get_node("Main/WorldContainer")
	camera = get_tree().root.get_node("Main/Player/Camera3D")
	debug = get_tree().root.get_node("Main/Debug/VBoxContainer/HBoxContainer/Label")
	
	if not world_container or not camera:
		push_error("TileStreamer konnte WorldContainer oder Camera nicht finden!")
	if debug == null:
		push_error("Dubug Label not found!")

func _process(delta: float) -> void:
	if not is_instance_valid(world_container):
		return

	# 1. Berechne die "logische" Spielerposition
	# Die Welt bewegt sich, also ist die logische Position des Spielers
	# die negative Position des WorldContainers.
	var logical_player_pos: Vector3 = -world_container.position
	logical_player_pos.x += TILE_PIXEL_SIZE
	logical_player_pos.z += TILE_PIXEL_SIZE
	# 2. Konvertiere die Weltposition in Kachel-Koordinaten
	var player_on_tile: Vector2i = world_to_tile_coords(logical_player_pos)
	if debug != null:
		debug.text = str("current_tile_coords: ", current_tile_coords, "\n player_on_tile: ", player_on_tile)

	# 3. Prüfe, ob wir die Kacheln aktualisieren müssen
	#if player_on_tile != current_tile_coords:
		#current_tile_coords = player_on_tile
		#update_loaded_tiles(current_tile_coords)
	update_loaded_tiles(player_on_tile)
		
	if current_creation_task.is_empty():
		# Wenn wir gerade nichts bauen, schauen wir, ob ein neuer Job in der Warteschlange ist.
		if not creation_queue.is_empty():
			var new_task = creation_queue.pop_front()
			_start_new_creation_task(new_task)
	else:
		# Wenn wir mitten in einem Bau-Job sind, fahren wir fort.
		_process_current_creation_task()
		
func _start_new_creation_task(task: Dictionary):
	var tile_coord = task.coord
	var data = task.data

	# WICHTIG: Prüfe, ob die Kachel in der Zwischenzeit entladen wurde
	if not loaded_tiles.has(tile_coord):
		print("Bau-Job für ", tile_coord, " abgebrochen, da sie bereits wieder entladen wurde.")
		return

	if data == null:
		var empty_node = Node3D.new()
		empty_node.name = "Empty_Tile_%s" % tile_coord
		empty_node.position = tile_to_world_coords(tile_coord)
		world_container.add_child(empty_node)
		# Ersetze den null-Platzhalter durch den echten Node
		loaded_tiles[tile_coord] = empty_node
		return

	var tile_node = Node3D.new()
	
	var sub_chunk_list = []
	for coord in task.data.sub_chunks:
		var sub_chunk_data = task.data.sub_chunks[coord]
		if sub_chunk_data.is_dirty: # Überspringe leere Sub-Chunks
			sub_chunk_list.append({"coord": coord, "map": sub_chunk_data.logic_map})
	
	tile_node.name = "Tile_%s" % tile_coord
	tile_node.position = tile_to_world_coords(tile_coord)
	world_container.add_child(tile_node)
	# Ersetze den null-Platzhalter durch den echten Node
	loaded_tiles[tile_coord] = tile_node

	# Richte den Task für die nächsten Frames ein
	#current_creation_task = {
		#"tile_node": tile_node,
		#"data": data
	#}
	current_creation_task = {
		"tile_node": tile_node,
		"sub_chunks_to_build": sub_chunk_list
	}
	current_feature_index = 0
	
func _process_current_creation_task():
	var tile_node: Node3D = current_creation_task.get("tile_node")
	var sub_chunks_to_build: Array = current_creation_task.get("sub_chunks_to_build")

	if not is_instance_valid(tile_node):
		print("Bau-Job abgebrochen, da Parent-Node ungültig wurde.")
		current_creation_task.clear()
		return
		
	# Überprüfe, ob der Job beendet ist
	if sub_chunks_to_build.is_empty():
		print("Kachel fertig gebaut: ", tile_node.name)
		current_creation_task.clear()
		return

	# --- BAUE EINEN SUB-CHUNK PRO FRAME ---
	var sub_chunk_task = sub_chunks_to_build.pop_front()
	var sub_chunk_coord = sub_chunk_task.coord
	var logic_map: Image = sub_chunk_task.map
	
	# Erstelle einen Parent-Node für diesen Sub-Chunk
	var sub_chunk_node = Node3D.new()
	sub_chunk_node.name = "SubChunk_%s" % sub_chunk_coord
	sub_chunk_node.position = Vector3(sub_chunk_coord.x * TILE_PIXEL_SIZE, 0, sub_chunk_coord.y * TILE_PIXEL_SIZE)

	# --- OPTIMIERUNG: Finde heraus, welche Typen wir wirklich brauchen ---
	var types_in_this_chunk: Dictionary = {}
	for y in TILE_PIXEL_SIZE:
		for x in TILE_PIXEL_SIZE:
			var type_id = int(logic_map.get_pixel(x, y).r * 255)
			if type_id > 0:
				types_in_this_chunk[type_id] = true

	# --- Erstelle die MultiMesh-Instanzen NUR für die benötigten Typen ---
	var multimeshes_by_type: Dictionary = {}
	for type_id in types_in_this_chunk:
		var mmi = MultiMeshInstance3D.new()
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var plane_mesh = PlaneMesh.new() # Oder lade ein Mesh aus einer Ressource
		plane_mesh.size = Vector2(5, 5) # 1 Meter pro Tile
		plane_mesh.orientation = PlaneMesh.FACE_Y
		multimesh.mesh = plane_mesh
		multimesh.mesh.surface_set_material(0, test_materials[type_id])
		mmi.multimesh = multimesh
		multimeshes_by_type[type_id] = mmi
		sub_chunk_node.add_child(mmi)

	# Fülle die MultiMesh-Instanzen
	var instance_counts: Dictionary = {} # Zählt, wie viele Instanzen pro Typ wir haben
	for type_id in multimeshes_by_type:
		instance_counts[type_id] = 0

	for y in TILE_PIXEL_SIZE:
		for x in TILE_PIXEL_SIZE:
			var type_id = int(logic_map.get_pixel(x, y).r * 255)
			if type_id in multimeshes_by_type:
				var mmi = multimeshes_by_type[type_id]
				# Dynamisches Erhöhen der Instanzanzahl ist langsam.
				# Besser: Zuerst zählen, dann setzen, dann füllen.
				# Aber für den Anfang ist das so einfacher.
				var current_count = instance_counts[type_id]
				mmi.multimesh.instance_count = current_count + 1
				var position = Vector3(x, 0, y) # Lokale Position im Sub-Chunk
				mmi.multimesh.set_instance_transform(current_count, Transform3D(Basis.IDENTITY, position))
				instance_counts[type_id] += 1
	
	# Füge den fertigen Sub-Chunk zum Kachel-Parent hinzu
	tile_node.add_child(sub_chunk_node)

func world_to_tile_coords(world_pos: Vector3) -> Vector2i:
	# Konvertiert eine Weltkoordinate in eine Kachel-Koordinate
	var x = floori(world_pos.x / TILE_PIXEL_SIZE)
	var y = floori(world_pos.z / TILE_PIXEL_SIZE) # In 3D ist Z die "Tiefe"
	return Vector2i(x, y)

func tile_to_world_coords(tile_coords: Vector2i) -> Vector3:
	# Konvertiert eine Kachel-Koordinate in die obere linke Ecke der Weltkoordinate
	return Vector3(tile_coords.x * TILE_PIXEL_SIZE, 0, tile_coords.y * TILE_PIXEL_SIZE)

# --- Die Kern-Logik ---

func update_loaded_tiles(center_tile: Vector2i) -> void:
	# 1. Bestimme, welche Kacheln wir jetzt brauchen
	var required_tiles: Dictionary = {}
	var view_size_in_tiles = ceili(100 / TILE_PIXEL_SIZE)
	var load_radius_x = view_size_in_tiles / 2 + LOAD_BUFFER
	var load_radius_y = view_size_in_tiles / 2 + LOAD_BUFFER # Für Orthogonal ist size ein einzelner Wert

	for x in range(center_tile.x - load_radius_x, center_tile.x + load_radius_x):
		for y in range(center_tile.y - load_radius_y, center_tile.y + load_radius_y):
			required_tiles[Vector2i(x, y)] = true

	# 2. Entlade Kacheln, die wir nicht mehr brauchen
	var tiles_to_unload: Array[Vector2i] = []
	for loaded_coord in loaded_tiles.keys():
		if not required_tiles.has(loaded_coord):
			tiles_to_unload.append(loaded_coord)
	for coord_to_unload in tiles_to_unload:
		_unload_tile(coord_to_unload)
	# 3. Lade Kacheln, die wir brauchen, aber noch nicht haben
	for required_coord in required_tiles.keys():
		if not loaded_tiles.has(required_coord) and not running_threads.has(required_coord):
			_load_tile(required_coord)
			
func _load_tile(tile_coord: Vector2i) -> void:
	# Verhindere doppeltes Laden
	#if running_threads.has(tile_coord) or loaded_tiles.has(tile_coord):
		#return

	print("Starte Ladevorgang für Kachel: ", tile_coord)
	loaded_tiles[tile_coord] = null
	var thread = Thread.new()
	running_threads[tile_coord] = thread # Referenz auf den Thread speichern!
	
	# Binde nicht nur die Koordinate, sondern auch den Thread selbst
	thread.start(_thread_worker_load_and_prepare.bind(tile_coord, thread))
	
	
func _thread_worker_load_and_prepare(tile_coord: Vector2i, thread_ref: Thread):
	var db_data = _query_database_for_tile(TILE_ZOOM_LEVEL, tile_coord)
	var mvt_tile = _get_mvt_tile(db_data)
	
	if mvt_tile == null:
		_push_to_creation_queue.call_deferred(tile_coord, null, thread_ref)
		return

	var prepared_data = _get_tile_data(mvt_tile)

	_push_to_creation_queue.call_deferred(tile_coord, prepared_data, thread_ref)

func _push_to_creation_queue(tile_coord: Vector2i, data, thread_ref: Thread):
	# Läuft auf dem Hauptthread
	creation_queue.push_back({"coord": tile_coord, "data": data})
	
	# Jetzt, wo der Thread seine Arbeit getan hat, können wir ihn sicher beenden
	thread_ref.wait_to_finish()
	running_threads.erase(tile_coord)
	

		
func _unload_tile(tile_coord: Vector2i) -> void:
	if not loaded_tiles.has(tile_coord):
		return

	# Hole eine Referenz auf den Node, den wir löschen wollen.
	var node_to_unload = loaded_tiles[tile_coord]

	# PRÜFUNG: Ist der Node, den wir löschen wollen, derselbe wie der,
	# den wir gerade aktiv bauen?
	if not current_creation_task.is_empty():
		var currently_building_node = current_creation_task.tile_node
		if node_to_unload == currently_building_node:
			# Ja! Breche den Bau-Job für DIESEN Node sofort ab.
			print("Bau-Job für Kachel ", tile_coord, " abgebrochen, da sie entladen wird.")
			current_creation_task.clear()
			current_feature_index = 0
			
	# Jetzt, wo wir sicher sind, dass kein aktiver Bau-Job mehr darauf zugreift,
	# können wir den Node sicher entfernen.
	if is_instance_valid(node_to_unload):
		node_to_unload.queue_free()
	
	loaded_tiles.erase(tile_coord)
		
func _query_database_for_tile(zoomlevel: int, tile_pos: Vector2i) -> Array:
	db_mutex.lock()
	var db = SQLite.new()
	db.verbosity_level = 0
	db.path = "res://db/languedoc-roussillon.mbtiles"
	if not db.open_db():
		#print("Error: Konnte die Datenbank nicht öffnen!")
		return []


	var zoom = zoomlevel
	# 8400 und 10440 als Start-Koordinaten zum testen.
	var col = 8400 - tile_pos.x
	var row = 10440 + tile_pos.y

	var sql_query = "SELECT tile_data FROM tiles WHERE zoom_level = %d AND tile_column = %d AND tile_row = %d" % [zoom, col, row]
	#print("Führe Query aus: ", sql_query)

	db.query(sql_query)
	var result = db.query_result
	db.close_db() # Datenbank nach der Abfrage schliessen

	db_mutex.unlock()
	if result.is_empty() :
		#print("Keine Kachel für diese Koordinaten gefunden.")
		return []
	return result
	
func _get_mvt_tile(result: Array) -> MvtTile:
	
	if result.size() == 0:
		return null
	var row_dict = result[0]
	var tile_data_blob: PackedByteArray = row_dict["tile_data"]

	var decompressed_bytes = tile_data_blob.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	
	if decompressed_bytes == null or decompressed_bytes.is_empty():
		# Fallback für nicht-komprimierte Daten
		decompressed_bytes = tile_data_blob

	if decompressed_bytes == null or decompressed_bytes.is_empty():
		#print("Konnte keine gültigen Kacheldaten extrahieren.")
		return null
	
	# 7. Bytes an das MVT-Plugin übergeben
	var my_tile: MvtTile = MvtTile.read(decompressed_bytes)
	return my_tile
	
func _get_tile_data(mvt_tile: MvtTile) -> Dictionary:
	var sub_chunk_resolution = TILE_PIXEL_SIZE # Grösse eines einzelnen Render-Chunks
	var sub_chunks_per_axis = 10   # Wir teilen die 2560px Kachel in 10x10 Chunks auf
	var prepared_sub_chunks: Dictionary = {} # Hier speichern wir die fertigen logic_maps
	#var logic_map = Image.create(logic_map_size, logic_map_size, false, Image.FORMAT_R8) # 8-bit reichen für 256 Typen
	#logic_map.fill(Color(0, 0, 0, 1)) # 0 = Leerer Grund
	for y in sub_chunks_per_axis:
		for x in sub_chunks_per_axis:
			var sub_chunk_coord = Vector2i(x, y)
			var logic_map = Image.create(sub_chunk_resolution, sub_chunk_resolution, false, Image.FORMAT_R8)
			logic_map.fill(Color(0,0,0,1))
			prepared_sub_chunks[sub_chunk_coord] = {
				"logic_map": logic_map,
				"is_dirty": false # Um leere Chunks später zu überspringen
			}

	# Definiere deine Typen und die Render-Reihenfolge
	var type_map = {
		"water": 1, "grass": 2, "grassland": 2, "farmland": 3,
		"residential": 4, "vineyard": 5, "wood": 6, "forest": 6
	}
	var render_order = ["water", "grass", "grassland", "farmland", "residential", "vineyard", "wood", "forest"]

	var all_features_by_type: Dictionary = {}

	# Sammle zuerst alle Features, gruppiert nach Typ
	for layer:MvtLayer in mvt_tile.layers():
		for feature:MvtFeature in layer.features():
			var tags = feature.tags(layer)
			var type_tag = tags.get("type")
			if type_tag in type_map:
				if not all_features_by_type.has(type_tag):
					all_features_by_type[type_tag] = []
				all_features_by_type[type_tag].append(feature)

	# Jetzt zeichne sie in der korrekten Reihenfolge
	for type_name in render_order:
		if not all_features_by_type.has(type_name):
			continue

		var type_id = type_map[type_name]
		var type_color = Color(type_id / 255.0, 0, 0, 1) # Speichere ID im Rot-Kanal

		for feature in all_features_by_type[type_name]:

			var geometry_commands = feature.geometry()

			# --- Schritt 1: Alle Ringe des Features sammeln ---
			var all_rings: Array[PackedVector2Array] = []
			var current_ring = PackedVector2Array()
			var cursor = Vector2.ZERO
			var last_clockwise: bool = true
			for command_sequence in geometry_commands:
				var command_id = command_sequence[0]
				
				if command_id == 1: # MoveTo
					cursor += Vector2(command_sequence[2], command_sequence[1])
					current_ring.append(cursor)
				elif command_id == 2: # LineTo
					for i in range(1, command_sequence.size(), 2):
						cursor += Vector2(command_sequence[i+1], command_sequence[i])
						current_ring.append(cursor)
				elif command_id == 7: # ClosePath
					if not current_ring.is_empty():
						
						all_rings.append(current_ring)
						current_ring = PackedVector2Array() # Nächsten Ring starten
			
			if all_rings.is_empty():
				continue
			
			var outer_rings: Array[PackedVector2Array] = []
			var inner_rings: Array[PackedVector2Array] = []
			for ring in all_rings:
				if not Geometry2D.is_polygon_clockwise(ring):
					inner_rings.append(ring)
				else:
					outer_rings.append(ring)

				if outer_rings.is_empty():
					#print("Warnung: Polygon-Feature ohne Aussenring gefunden. Tags: ", tags)
					continue
			var final_polygons = all_rings
			# --- RASTERISIERUNG ---
			for poly in outer_rings:
				var bounds: Rect2 = _get_rect(poly)
				var tile_extent = float(mvt_tile.layers()[0].extent())

				# --- KORREKTUR START ---
				
				# Skaliere die Polygon-Grenzen auf den globalen Pixelraum der Vektor-Kachel (0-2560)
				var global_pixel_bounds_pos = bounds.position * (TILE_PIXEL_SIZE * 10.0 / tile_extent)
				var global_pixel_bounds_size = bounds.size * (TILE_PIXEL_SIZE * 10.0 / tile_extent)

				# Finde heraus, welche Sub-Chunks diese Pixel-Grenzen berühren
				var start_chunk = (global_pixel_bounds_pos / TILE_PIXEL_SIZE).floor()
				var end_chunk = ((global_pixel_bounds_pos + global_pixel_bounds_size) / TILE_PIXEL_SIZE).floor()

				# Iteriere über die betroffenen Sub-Chunks
				for chunk_y in range(start_chunk.y, end_chunk.y + 1):
					for chunk_x in range(start_chunk.x, end_chunk.x + 1):
						var sub_chunk_coord = Vector2i(chunk_x, chunk_y)
						if not prepared_sub_chunks.has(sub_chunk_coord): continue

						var current_logic_map = prepared_sub_chunks[sub_chunk_coord].logic_map
						prepared_sub_chunks[sub_chunk_coord].is_dirty = true
						
						# Iteriere über JEDES PIXEL INNERHALB des aktuellen Sub-Chunks
						for pixel_y in sub_chunk_resolution:
							for pixel_x in sub_chunk_resolution:
								# Berechne die globale Pixel-Koordinate
								var global_pixel_x = (sub_chunk_coord.x * sub_chunk_resolution + pixel_x) * (tile_extent / (TILE_PIXEL_SIZE * 10.0))
								var global_pixel_y = (sub_chunk_coord.y * sub_chunk_resolution + pixel_y) * (tile_extent / (TILE_PIXEL_SIZE * 10.0))

								# Konvertiere die globale Pixel-Koordinate zurück in den Vektor-Raum
								var point_in_poly_space = Vector2(global_pixel_x, global_pixel_y) 

								# Prüfe, ob dieser Punkt innerhalb des Polygons (und nicht in einem Loch) ist
								if Geometry2D.is_point_in_polygon(point_in_poly_space, poly):
									var is_in_hole = false
									for hole in inner_rings:
										if Geometry2D.is_point_in_polygon(point_in_poly_space, hole):
											is_in_hole = true
											break
									if not is_in_hole:
										current_logic_map.set_pixel(pixel_x, pixel_y, type_color)


	return {
		"sub_chunks": prepared_sub_chunks,
		"type_map": type_map,
		}
	
func _get_rect(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()

	var min_p = poly[0]
	var max_p = poly[0]

	for i in range(1, poly.size()):
		var p = poly[i]
		min_p.x = min(min_p.x, p.x)
		min_p.y = min(min_p.y, p.y)
		max_p.x = max(max_p.x, p.x)
		max_p.y = max(max_p.y, p.y)
		
	return Rect2(min_p, max_p - min_p)
