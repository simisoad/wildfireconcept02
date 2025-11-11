extends Node3D

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
	var sprite: Sprite3D = Sprite3D.new()
	sprite.rotate_x(deg_to_rad(-90))
	sprite.position = Vector3(128,0,128)
	sprite.scale *= 256.0
	sprite.texture = image_texture
	#self.add_child(sprite)
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
		_create_mesh_3d(layer)


	var layers = my_tile.layer_names()


	print("Erfolgreich geparst! Gefundene Layer: ", layers)

	# Ab hier kannst du mit dem 'my_tile' Objekt arbeiten und die Features auslesen.
	var landuse_layer = my_tile.layer("landcover")
	if landuse_layer:
		print("Anzahl der 'landcover' Features: ", landuse_layer.features().size())

func _create_mesh_3d(mvt_layer: MvtLayer) -> void:
	for feature: MvtFeature in mvt_layer.features():
		if feature.geom_type().get("GeomType") != "POLYGON":
			print("not a polygon, its a: GeomType: ", feature.geom_type().get("GeomType"))
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
				print("Warnung: Polygon-Feature ohne Aussenring gefunden. Tags: ", tags)
				continue



		if outer_rings.is_empty():
			return

		# --- Erstelle die Basis-Form aus allen Aussenringen ---
		# Wir brauchen einen Container-Node für das gesamte Feature
		var feature_node = CSGCombiner3D.new()
		var new_mat: StandardMaterial3D = StandardMaterial3D.new()
		new_mat.albedo_color = color
		feature_node.operation = CSGCombiner3D.OPERATION_UNION

		for outer_ring in outer_rings:

			var csg_poly = CSGPolygon3D.new()
			csg_poly.polygon = outer_ring # Direkt das PackedVector2Array zuweisen!
			feature_node.add_child(csg_poly)

		# --- Erstelle die Löcher und ziehe sie ab ---
		for hole in inner_rings:
			var csg_hole = CSGPolygon3D.new()
			csg_hole.polygon = hole

			# Das ist die Magie: Setze die Operation auf Subtraktion
			csg_hole.operation = CSGPolygon3D.OPERATION_SUBTRACTION

			# Füge das Loch als Kind zum Container hinzu
			feature_node.add_child(csg_hole)

		# WICHTIG: Die Vektor-Koordinaten sind 2D. CSGPolygon3D erwartet sie
		# auf der XY-Ebene. Wir müssen das Endergebnis rotieren, damit es flach auf dem Boden liegt.
		feature_node.rotate_x(deg_to_rad(-90))
		feature_node.material_override = new_mat

		# Skalierung und Positionierung
		var tile_extent = float(mvt_layer.extent())
		var p_scale = 256.0 / tile_extent
		feature_node.scale = Vector3(p_scale, p_scale, 1.0)

		feature_node.use_collision = true
		#await self.get_tree().create_timer(0.001).timeout
		#var array_mesh: ArrayMesh = feature_node.bake_static_mesh()
		#var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		#mesh_inst.mesh = array_mesh
		#mesh_inst.scale = Vector3(p_scale, p_scale, 1.0)
		#mesh_inst.material_override = new_mat
		#mesh_inst.rotate_x(deg_to_rad(-90))
		# Positioniere den Node entsprechend der Kachelposition in der Welt...

		#self.add_child(feature_node)
		#feature_node.queue_free()
		self.add_child(feature_node)
