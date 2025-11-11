extends Node2D


func _ready() -> void:
	# Annahme: 'my_tile' ist bereits geladen und geparst
	# var my_tile: MvtTile = ... 
	_get_mvt_from_db()
	
func _get_mvt_from_db() -> void:
		# 1. Datenbank-Setup
	var db = SQLite.new()
	db.path = "res://db/languedoc-roussillon.mbtiles"
	if not db.open_db():
		print("Error: Konnte die Datenbank nicht öffnen!")
		return
		
	var db_rast = SQLite.new()

	db_rast.path = "res://db/world-cover-raster.mbtiles"
	if not db_rast.open_db():
		print("Error: Konnte Raster-DB nicht öffnen!")
	#db_rast.export_to_json("res://db/world-cover-raster.json")
	# 2. SQL-Anfrage formulieren
	# Wir holen uns eine Beispiel-Kachel. Du musst diese Werte (Z/X/Y)
	# anpassen, um eine Kachel in deiner Region zu finden.
	var zoom = 14
	var col = 8400
	var row = 10440 # In MBTiles ist die Y-Achse oft gespiegelt!

	# MBTiles speichert Y-Koordinaten oft "gespiegelt" (TMS-Standard).
	# Die Formel zur Umrechnung von der Standard-OSM-Koordinate (XYZ) lautet:
	#var tms_row = (1 << zoom) - 1 - row

	# Der SQL-Befehl als String. Wir wollen die Spalte 'tile_data' aus der Tabelle 'tiles'
	# wo die Z/X/Y-Werte übereinstimmen.
	var sql_query = "SELECT tile_data FROM tiles WHERE zoom_level = %d AND tile_column = %d AND tile_row = %d" % [zoom, col, row]
	print("Führe Query aus: ", sql_query)
	
	var sql_query_r = "SELECT tile_data FROM tiles WHERE zoom_level = %d AND tile_column = %d AND tile_row = %d" % [zoom, col, row]
	print("Führe Query aus: ", sql_query_r)
	# 3. Anfrage ausführen
	db.query(sql_query)
	var result = db.query_result
	db.close_db() # Datenbank nach der Abfrage schliessen
	
	db_rast.query(sql_query_r)
	var result_r: Array[Dictionary] = db_rast.query_result
	db_rast.close_db() # Datenbank nach der Abfrage schliessen

	# 4. Ergebnis verarbeiten
	if result.is_empty():
		print("Keine Kachel für diese Koordinaten gefunden.")
		return
	if result_r.is_empty():
		print("Keine Raster Kachel!")
		return
	var image: Image = Image.new()
	image.load_png_from_buffer(result_r[0].get("tile_data"))

	var image_texture: = ImageTexture.create_from_image(image)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.position = Vector2(128,128)
	sprite.texture = image_texture
	self.add_child(sprite)
	#return
	
	
	#var texture: Texture = result_r[0].get("tile_data")
	# 5. Den Blob extrahieren
	# Das Ergebnis ist ein Array. Da wir nur eine Kachel abgefragt haben,
	# nehmen wir das erste Element (Index 0). Dies ist ein Dictionary.
	var row_dict = result[0]
	# Aus dem Dictionary holen wir den Wert für den Schlüssel 'tile_data'.
	# Dies ist unser komprimierter Blob.
	var tile_data_blob: PackedByteArray = row_dict["tile_data"]
	
	# 6. Blob dekomprimieren (wie in deinem Test)
	# Die Daten in .mbtiles sind fast immer GZIP-komprimiert.
	var decompressed_bytes = tile_data_blob.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	
	if decompressed_bytes.is_empty():
		print("Fehler beim Dekomprimieren oder Blob war leer.")
		# Manchmal ist der Blob nicht komprimiert. Versuche es direkt:
		decompressed_bytes = tile_data_blob

	if decompressed_bytes.is_empty():
		print("Konnte keine gültigen Kacheldaten extrahieren.")
		return

	# 7. Bytes an das MVT-Plugin übergeben
	var my_tile: MvtTile = MvtTile.read(decompressed_bytes)
	var all_layers: Array = my_tile.layers()
	print(my_tile.layer_names())
	for layer:MvtLayer in all_layers:
		if layer.name() == "wood":
			_create_mesh(layer)

	
	var layers = my_tile.layer_names()

		
	print("Erfolgreich geparst! Gefundene Layer: ", layers)
	
	# Ab hier kannst du mit dem 'my_tile' Objekt arbeiten und die Features auslesen.
	var landuse_layer = my_tile.layer("landcover")
	if landuse_layer:
		print("Anzahl der 'landcover' Features: ", landuse_layer.features().size())

func _create_mesh(mvt_layer: MvtLayer) -> void:
	if not mvt_layer:
		print("Layer nicht gefunden.")
		return

	for feature: MvtFeature in mvt_layer.features():
		if feature.geom_type().get("GeomType") != "POLYGON":
			print("not a polygon, its a: GeomType: ", feature.geom_type().get("GeomType"))
			continue

		var tags: Dictionary = feature.tags(mvt_layer)
		var color: Color = Color.ALICE_BLUE
		var type_tag = tags.get("type")
		var id = tags.get("id")

		if type_tag == "swimming_pool":
			color == Color.AQUA
			continue
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
				cursor += Vector2(command_sequence[1], command_sequence[2])
				current_ring.append(cursor)
			elif command_id == 2: # LineTo
				for i in range(1, command_sequence.size(), 2):
					cursor += Vector2(command_sequence[i], command_sequence[i+1])
					current_ring.append(cursor)
			elif command_id == 7: # ClosePath
				if not current_ring.is_empty():
					
					all_rings.append(current_ring)
					current_ring = PackedVector2Array() # Nächsten Ring starten
		
		if all_rings.is_empty():
			continue

		# --- Schritt 2: Ringe in Aussenringe (CW) und Löcher (CCW) klassifizieren ---
		var outer_rings: Array[PackedVector2Array] = []
		var inner_rings: Array[PackedVector2Array] = []
		
		for ring in all_rings:
			if not Geometry2D.is_polygon_clockwise(ring):
				outer_rings.append(ring)
			else:
				inner_rings.append(ring)

		if outer_rings.is_empty():
			print("Warnung: Polygon-Feature ohne Aussenring gefunden. Tags: ", tags)
			continue
		var polygons_to_process: Array[PackedVector2Array] = outer_rings
		
		for hole in inner_rings:
			var next_polygons: Array[PackedVector2Array] = []
			for poly in polygons_to_process:
				var clipped_results: Array = Geometry2D.clip_polygons(poly, hole)
				for clipped_poly in clipped_results:
					#print("clipped_poly: ", clipped_poly)
					next_polygons.append(clipped_poly)
			polygons_to_process = next_polygons
			
		for final_polygon in polygons_to_process:
			if final_polygon.size() < 3: # Ungültiges Polygon nach dem Clipping
				#print("hugo")
				continue

			var indices = Geometry2D.triangulate_polygon(final_polygon)
			if indices.is_empty():
				print("Triangulierung für ein Feature-Teil fehlgeschlagen. Tags: ", tags)
				continue
			var arr_mesh = ArrayMesh.new()
			var arrays = []
			arrays.resize(Mesh.ARRAY_MAX)
					
			var vertices_2d = PackedVector2Array()
			var tile_extent = float(mvt_layer.extent())
			var p_scale = 256.0

			for p in final_polygon:
				vertices_2d.append(Vector2(p.x / tile_extent * p_scale, p.y / tile_extent * p_scale))
			if Geometry2D.is_polygon_clockwise(vertices_2d):
				color = Color.RED
				
			arrays[Mesh.ARRAY_VERTEX] = vertices_2d
			arrays[Mesh.ARRAY_INDEX] = indices

			arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
					
			var m = MeshInstance2D.new()
			m.mesh = arr_mesh
			m.modulate = color
			self.add_child(m)
			
