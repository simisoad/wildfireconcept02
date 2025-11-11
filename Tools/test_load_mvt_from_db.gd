extends Node

# Lade die Klassen aus den Addons, damit Godot sie kennt.
#const SQLite = preload("res://addons/godot-sqlite/bin/gdsqlite.gdns")
#const MvtTile = preload("res://addons/geo-tile-loader/bin/mvt_tile.gdns")

func latlon_to_tile_coords(lat_deg: float, lon_deg: float, zoom: int) -> Dictionary:
	var lat_rad = deg_to_rad(lat_deg)
	var n: float = 1 << zoom

	var x = int((lon_deg + 180.0) / 360.0 * n)
	var y_xyz = int((1.0 - asinh(tan(lat_rad)) / PI) / 2.0 * n)
	var y_tms = (1 << zoom) - 1 - y_xyz

	return {
		"x": x,
		"y_xyz": y_xyz,
		"y_tms": y_tms
	}

func _ready() -> void:
#	44.23889759°, 4.591820113° Carsan
# 	44.22289205737807°, 4.58693659181454° schönstes OSM Feld
	var coords: = latlon_to_tile_coords(44.22289205737807, 4.58693659181454, 14)
	print(coords)
	#_get_mvt_from_db()

func _get_mvt_from_db() -> void:
		# 1. Datenbank-Setup
	var db = SQLite.new()
	db.path = "res://db/languedoc-roussillon.mbtiles"
	if not db.open_db():
		print("Error: Konnte die Datenbank nicht öffnen!")
		return

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

	# 3. Anfrage ausführen
	db.query(sql_query)
	var result = db.query_result
	db.close_db() # Datenbank nach der Abfrage schliessen

	# 4. Ergebnis verarbeiten
	if result.is_empty():
		print("Keine Kachel für diese Koordinaten gefunden.")
		return

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
	var layers = my_tile.layer_names()
	for feature: MvtFeature in my_tile.layer("landcover").features():
		var array: PackedVector2Array = feature.geometry()

		var test: = feature.geometry()
		print(feature.geom_type())

		var arr_mesh = ArrayMesh.new()
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = array

		# Create the Mesh.
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var m = MeshInstance3D.new()
		m.mesh = arr_mesh
		self.add_child(m)

#		512264, 5500961

	print("Erfolgreich geparst! Gefundene Layer: ", layers)

	# Ab hier kannst du mit dem 'my_tile' Objekt arbeiten und die Features auslesen.
	var landuse_layer = my_tile.layer("landcover")
	if landuse_layer:
		print("Anzahl der 'landcover' Features: ", landuse_layer.features().size())
