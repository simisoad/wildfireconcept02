# TileStreamer.gd
extends Node

# --- Konfiguration ---
const TILE_ZOOM_LEVEL = 14 # Wir arbeiten vorerst mit einem festen Zoom-Level
const TILE_PIXEL_SIZE = 256 # Die Grösse unserer generierten Meshes
const LOAD_BUFFER = 2 # Wie viele Kacheln über den Bildschirmrand hinaus laden?

# --- Referenzen ---
var world_container: Node3D
var camera: Camera3D

# --- Status ---
var loaded_tiles: Dictionary = {} # Speichert geladene Kacheln: {Vector2i(x,y): Node}
var current_tile_coords = Vector2i(-100, -100) # Startwert ausserhalb der Welt

# --- Threads ---
var db_mutex = Mutex.new()
var running_threads: Dictionary = {} # Verfolgt laufende Threads pro Kachel
var creation_queue: Array = [] # Warteschlange für fertige Kacheln

func _ready() -> void:
	# Wir warten einen Frame, damit die Hauptszene sicher geladen ist
	await get_tree().process_frame
	
	# Hole die Referenzen aus dem Szenenbaum
	world_container = get_tree().root.get_node("Main/WorldContainer")
	camera = get_tree().root.get_node("Main/Player/Camera3D")
	
	if not world_container or not camera:
		push_error("TileStreamer konnte WorldContainer oder Camera nicht finden!")

func _process(delta: float) -> void:
	if not is_instance_valid(world_container):
		return

	# 1. Berechne die "logische" Spielerposition
	# Die Welt bewegt sich, also ist die logische Position des Spielers
	# die negative Position des WorldContainers.
	var logical_player_pos: Vector3 = -world_container.position

	# 2. Konvertiere die Weltposition in Kachel-Koordinaten
	var player_on_tile = world_to_tile_coords(logical_player_pos)

	# 3. Prüfe, ob wir die Kacheln aktualisieren müssen
	if player_on_tile != current_tile_coords:
		current_tile_coords = player_on_tile
		update_loaded_tiles(current_tile_coords)
		
	if not creation_queue.is_empty():
		var tile_data = creation_queue.pop_front()
		_actually_create_tile_nodes(tile_data.coord, tile_data.tile_node)

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
	var view_size_in_tiles = ceili(camera.size / TILE_PIXEL_SIZE)
	var load_radius_x = view_size_in_tiles / 2 + LOAD_BUFFER
	var load_radius_y = view_size_in_tiles / 2 + LOAD_BUFFER # Für Orthogonal ist size ein einzelner Wert

	for x in range(center_tile.x - load_radius_x, center_tile.x + load_radius_x):
		for y in range(center_tile.y - load_radius_y, center_tile.y + load_radius_y):
			required_tiles[Vector2i(x, y)] = true

	# 2. Entlade Kacheln, die wir nicht mehr brauchen
	for loaded_coord in loaded_tiles.keys():
		if not required_tiles.has(loaded_coord):
			_unload_tile(loaded_coord)

	# 3. Lade Kacheln, die wir brauchen, aber noch nicht haben
	for required_coord in required_tiles.keys():
		if not loaded_tiles.has(required_coord):
			_load_tile(required_coord)
			
func _load_tile(tile_coord: Vector2i) -> void:
	# Verhindere doppeltes Laden
	if running_threads.has(tile_coord) or loaded_tiles.has(tile_coord):
		return

	print("Starte Ladevorgang für Kachel: ", tile_coord)
	
	var thread = Thread.new()
	running_threads[tile_coord] = thread # Referenz auf den Thread speichern!
	
	# Binde nicht nur die Koordinate, sondern auch den Thread selbst
	thread.start(_thread_worker_load_and_prepare.bind(tile_coord, thread))
	
	
func _thread_worker_load_and_prepare(tile_coord: Vector2i, thread_ref: Thread):
	var db_data = _query_database_for_tile(TILE_ZOOM_LEVEL, tile_coord)
	var mvt_tile = _get_mvt_tile(db_data)
	
	if mvt_tile == null:
		var empty_node: Node3D = Node3D.new()
		_push_to_creation_queue.call_deferred(tile_coord, empty_node, thread_ref)
		return

	var prepared_data = _get_tile_data(mvt_tile)
	var tile_node: Node3D =  _create_Meshes(tile_coord, prepared_data)
	
	_push_to_creation_queue.call_deferred(tile_coord, tile_node, thread_ref)

func _push_to_creation_queue(tile_coord: Vector2i, tile_node: Node3D, thread_ref: Thread):
	# Läuft auf dem Hauptthread
	creation_queue.push_back({"coord": tile_coord, "tile_node": tile_node})
	
	# Jetzt, wo der Thread seine Arbeit getan hat, können wir ihn sicher beenden
	thread_ref.wait_to_finish()
	running_threads.erase(tile_coord)
	
func _actually_create_tile_nodes(tile_coord: Vector2i, tile_node: Node3D):

	tile_node.position = tile_to_world_coords(tile_coord)
	world_container.add_child(tile_node)
	loaded_tiles[tile_coord] = tile_node
	
func _load_error(tile_coord: Vector2i) -> void:
	var empty_tile_node = Node3D.new()
	empty_tile_node.name = "EmptyTile_%s" % tile_coord
	empty_tile_node.position = tile_to_world_coords(tile_coord)
	world_container.add_child(empty_tile_node)
	loaded_tiles[tile_coord] = empty_tile_node
		
func _unload_tile(tile_coord: Vector2i) -> void:
	print("Entlade Kachel: ", tile_coord)
	if loaded_tiles.has(tile_coord):
		var node_to_remove = loaded_tiles[tile_coord]
		node_to_remove.queue_free()
		loaded_tiles.erase(tile_coord)
		
func _query_database_for_tile(zoomlevel: int, tile_pos: Vector2i) -> Array:
	db_mutex.lock()
	var db = SQLite.new()
	db.verbosity_level = 0
	db.path = "res://db/languedoc-roussillon.mbtiles"
	if not db.open_db():
		push_error("Error: Konnte die Datenbank nicht öffnen!")
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
		push_error("Keine Kachel für diese Koordinaten gefunden.")
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
		push_error("Konnte keine gültigen Kacheldaten extrahieren.")
		return null
	
	# 7. Bytes an das MVT-Plugin übergeben
	var my_tile: MvtTile = MvtTile.read(decompressed_bytes)
	return my_tile
	
func _get_tile_data(mvt_tile: MvtTile) -> Dictionary:
	var all_layers: Array = mvt_tile.layers()
	
	var polygons_arr: Array = []
	var holes_arr: Array = []
	var color_arr: Array = []
	
	for mvt_layer:MvtLayer in all_layers:
		#if mvt_layer.name() == "wood" or mvt_layer.name() == "forest" or mvt_layer.name() == "vineyard":
		for feature: MvtFeature in mvt_layer.features():
			if feature.geom_type().get("GeomType") != "POLYGON":
				push_error("not a polygon, its a: GeomType: ", feature.geom_type().get("GeomType"))
				continue

			var tags: Dictionary = feature.tags(mvt_layer)
			var color: Color = Color.PINK
			var type_tag = tags.get("type")
			var id = tags.get("id")

			if type_tag == "swimming_pool":
				color == Color.AQUA
			elif type_tag == "orchard":
				color = Color.AQUAMARINE
			elif type_tag == "wood" or type_tag == "forest":
				color = Color.WEB_GREEN
			elif type_tag == "grassland" or type_tag == "grass":
				color = Color.GREEN_YELLOW
			elif type_tag == "residential":
				color = Color.DARK_SEA_GREEN
			elif type_tag == "vineyard":
				color = Color.LAWN_GREEN
			var type: String = type_tag


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
					push_error("Warnung: Polygon-Feature ohne Aussenring gefunden. Tags: ", tags)
					continue
			polygons_arr.append(outer_rings)
			holes_arr.append(inner_rings)
			color_arr.append(color)
	var prepared_data = {
		"polygons": polygons_arr,
		"holes": holes_arr,
		"color": color_arr,
	}
	return prepared_data
func _create_Meshes(tile_coord: Vector2i, data) -> Node3D:
		# Entferne den alten Platzhalter
	if loaded_tiles.has(tile_coord):
		loaded_tiles[tile_coord].queue_free()

	if data == null:
		# Leere Kachel, erstelle einen permanenten leeren Node
		print("data == null !")
		var empty_node = Node3D.new()
		empty_node.position = tile_to_world_coords(tile_coord)
		#world_container.add_child(empty_node)
		loaded_tiles[tile_coord] = empty_node
		return empty_node
	
	# HIER: Nimm die vorbereiteten Daten und erstelle die echten CSG-Nodes
	var tile_node = Node3D.new()
	
	for i in data.polygons.size():

		var color: Color = data.color[i]
		var outer_rings = data.polygons[i]
		var inner_rings = data.holes[i]
		var feature_node = CSGCombiner3D.new()
		var new_mat: StandardMaterial3D = StandardMaterial3D.new()
		new_mat.albedo_color = color
		feature_node.operation = CSGCombiner3D.OPERATION_UNION

		for outer_ring in outer_rings:
			
			var csg_poly = CSGPolygon3D.new()
			csg_poly.polygon = outer_ring # Direkt das PackedVector2Array zuweisen!
			#feature_node.add_child(csg_poly)

		# --- Erstelle die Löcher und ziehe sie ab ---
		for hole in inner_rings:
			var csg_hole = CSGPolygon3D.new()
			csg_hole.polygon = hole
			
			# Das ist die Magie: Setze die Operation auf Subtraktion
			csg_hole.operation = CSGPolygon3D.OPERATION_SUBTRACTION
			
			# Füge das Loch als Kind zum Container hinzu
			#feature_node.add_child(csg_hole)

		# WICHTIG: Die Vektor-Koordinaten sind 2D. CSGPolygon3D erwartet sie
		# auf der XY-Ebene. Wir müssen das Endergebnis rotieren, damit es flach auf dem Boden liegt.
		feature_node.rotate_x(deg_to_rad(-90))
		feature_node.rotate_y(deg_to_rad(90))
		feature_node.material_override = new_mat

		# Skalierung und Positionierung
		var tile_extent = 8192 #float(mvt_layer.extent()) müsste man auch noch anpassen!
		var p_scale = 256.0 / tile_extent
		feature_node.scale = Vector3(p_scale, p_scale, 1.0)

		feature_node.use_collision = true
		#tile_node.add_child(feature_node)
	return tile_node
