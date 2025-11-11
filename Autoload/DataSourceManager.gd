# data_source_manager.gd
extends Node

signal data_ready(coord, data)
signal data_failed(coord)

# --- NEU: I/O Worker Thread-Pool Konfiguration ---
# Für I/O sind weniger Threads oft besser, um die Festplatte nicht zu überlasten.
const NUM_IO_WORKERS = 2
var worker_threads: Array[Thread] = []

# Die "To-Do-Liste" für Ladeanfragen
var load_request_queue: Array[Vector2i] = []
var request_mutex = Mutex.new()

# Die "Postausgangs-Liste" für geladene Daten
var results_queue: Array = []
var results_mutex = Mutex.new()


var data_cache: Dictionary = {}
var db_mutex = Mutex.new() # Dieser Mutex wird weiterhin innerhalb der Threads genutzt

#Debug
#var how_many_requests: int = 0

func _ready() -> void:
	WorldStreamer.tile_no_longer_required.connect(_on_tile_no_longer_required)

	# Starte die festen I/O-Worker-Threads
	print("Starte ", NUM_IO_WORKERS, " I/O-Worker-Threads.")
	for i in NUM_IO_WORKERS:
		var thread = Thread.new()
		worker_threads.append(thread)
		thread.start(_io_worker_loop)

# Die öffentliche API: Nimmt nur noch Anfragen entgegen und legt sie in die Queue
func request_tile_data(coord: Vector2i) -> void:
	#how_many_requests += 1
	#print("how_many_requests: ", how_many_requests)
	# 1. Aus dem Cache bedienen (schnellster Weg)
	if data_cache.has(coord):
		var cached_data = data_cache[coord]
		if cached_data != null:
			data_ready.emit(coord, cached_data)
		else:
			data_failed.emit(coord)
		return

	# 2. Prüfen, ob die Anfrage schon in der Queue ist, um Doppelarbeit zu vermeiden
	request_mutex.lock()
	if coord in load_request_queue:
		request_mutex.unlock()
		return # Aufgabe ist schon geplant, tue nichts.

	# 3. Wenn nicht, zur Queue hinzufügen. Einer der Worker wird es sich holen.
	load_request_queue.push_back(coord)
	request_mutex.unlock()


# Die Schleife, die jeder I/O-Worker-Thread ausführt
func _io_worker_loop():
	while true:
		var task_found = false
		var coord_to_load: Vector2i

		request_mutex.lock()
		if not load_request_queue.is_empty():
			coord_to_load = load_request_queue.pop_front()
			task_found = true
		request_mutex.unlock()

		if task_found: # Prüfe, ob wir tatsächlich ein Element gepoppt haben
			# Aufgabe gefunden: Lade die Daten (dieser Teil ist identisch zu vorher)
			var mvt_tile: MvtTile = _query_and_parse_tile(DebugManager.TILE_ZOOM_LEVEL, coord_to_load)
			var raster_tile: Image = _query_raster_tile(DebugManager.TILE_ZOOM_LEVEL, coord_to_load)

			var result_data: Dictionary
			var success: bool

			if mvt_tile != null and raster_tile != null:
				result_data = {"mvt_tile": mvt_tile, "raster_tile": raster_tile}
				success = true
			else:
				result_data = {} # Leeres Dictionary für Fehler
				success = false

			# Ergebnis in die Postausgangs-Queue legen
			results_mutex.lock()
			results_queue.push_back({"coord": coord_to_load, "data": result_data, "success": success})
			results_mutex.unlock()
		else:
			# Keine Aufgabe, kurz warten
			OS.delay_msec(10)

# NEU: Die _process-Schleife holt fertige Ergebnisse ab und sendet die Signale
func _process(delta: float) -> void:
	results_mutex.lock()
	if results_queue.is_empty():
		results_mutex.unlock()
		return

	var finished_tasks = results_queue.duplicate()
	results_queue.clear()
	results_mutex.unlock()

	for task in finished_tasks:
		var coord = task.coord
		var data = task.data
		var success = task.success

		# Erst jetzt, im Hauptthread, werden Daten gecached und Signale gesendet
		if success:
			data_cache[coord] = data
			data_ready.emit(coord, data)
		else:
			data_cache[coord] = null # Fehler cachen, um wiederholte Anfragen zu vermeiden
			data_failed.emit(coord)


# Diese Funktionen werden nur noch von den Workern aufgerufen, nicht vom Hauptthread
func _query_and_parse_tile(zoom_level: int, tile_pos: Vector2i) -> MvtTile:
	# ... (Code ist identisch, keine Änderung nötig)
	var path: String = "res://db/languedoc-roussillon.mbtiles"
	var result: Array = _db_query(zoom_level, tile_pos, path)
	if result.is_empty(): return null
	var blob = result[0]["tile_data"]
	var bytes = blob.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if bytes == null or bytes.is_empty(): bytes = blob
	if bytes == null or bytes.is_empty(): return null
	return MvtTile.read(bytes)

func _query_raster_tile(zoom_level: int, tile_pos: Vector2i) -> Image:
	# ... (Code ist identisch, keine Änderung nötig)
	#var path: String = 'res://db/world-cover-raster.mbtiles'
	var path: String = 'res://db/senti.mbtiles'
	var result: Array = _db_query(zoom_level, tile_pos, path)
	if result.is_empty(): return null
	var raster_image: Image = Image.new()
	var err = raster_image.load_png_from_buffer(result[0]["tile_data"])
	if err != OK: return null
	return raster_image

func _db_query(zoom_level: int, tile_pos: Vector2i, path: String) -> Array:
	# ... (Code ist identisch, keine Änderung nötig)
	db_mutex.lock()
	var db = SQLite.new()
	db.verbosity_level = 0
	db.path = path
	var result = []
	if db.open_db():
		var col = DebugManager.start_x + tile_pos.x
		var row = DebugManager.start_y - tile_pos.y
		var sql = "SELECT tile_data FROM tiles WHERE zoom_level = %d AND tile_column = %d AND tile_row = %d" % [zoom_level, col, row]
		db.query(sql)
		result = db.query_result
		db.close_db()
	db_mutex.unlock()
	return result

# Aufräum-Logik
func _on_tile_no_longer_required(coord: Vector2i) -> void:
	# Entferne aus dem Cache
	if data_cache.has(coord):
		data_cache.erase(coord)

	# OPTIONAL, ABER EMPFOHLEN: Entferne auch aus der Request-Queue, wenn es noch nicht geladen wurde
	request_mutex.lock()
	if coord in load_request_queue:
		load_request_queue.erase(coord)
	request_mutex.unlock()
