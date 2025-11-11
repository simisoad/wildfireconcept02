# chunk_generator.gd
extends Node
var next_state_id: int = 1
var NUM_RASTER_WORKERS = 6
var worker_threads: Array[Thread] = []
var rasterization_queue: Array = []
var queue_mutex = Mutex.new()
var results_queue: Array = []
var results_mutex = Mutex.new()

#var creation_queue: Array[TileBuildData] = []

#var current_sub_chunk_index: int = 0
var world_builder: WorldBuilder
var world_container: Node3D

var managed_tile_states: Dictionary = {} # Mapping von Vector2i -> TileState
var limbo: Node3D  # Dient als Zwischenlager fÃ¼r die Sub-Chunks, welche ausgewÃ¤chselt werden.

func _ready() -> void:
	await get_tree().process_frame
	world_builder = get_tree().root.get_node_or_null("Main/WorldContainer/WorldBuilder")
	if world_builder == null:
		push_error("ChunkGenerator konnte WorldBuilder nicht finden!")
		return
	world_container = get_tree().root.get_node_or_null("Main/WorldContainer")
	limbo = get_tree().root.get_node_or_null("Main/WorldContainer/Limbo")

	#print("Starte ", NUM_RASTER_WORKERS, " Rasterizer-Worker-Threads.")
	for i in NUM_RASTER_WORKERS:
		var new_thread = Thread.new()
		worker_threads.append(new_thread)
		new_thread.start(_raster_worker_loop)

	WorldStreamer.tile_lod_update.connect(_on_tile_lod_update)
	WorldStreamer.tile_no_longer_required.connect(_on_tile_no_longer_required)
	DataSourceManager.data_ready.connect(_on_data_ready)
	DataSourceManager.data_failed.connect(_on_data_failed)



# NEUE FUNKTION: Extrahiert alle Daten aus dem MvtTile im Hauptthread
func _extract_mvt_data_safely(mvt_tile: MvtTile) -> Dictionary:
	if mvt_tile == null:
		return {}

	var safe_data = {}
	var layers = mvt_tile.layers()

	if layers.is_empty():
		return {}

	# Extrahiere die tile_extent aus der ersten Schicht
	var first_layer = layers[0]
	safe_data["tile_extent"] = first_layer.extent()
	safe_data["layers"] = []

	# Extrahiere alle Layer-Daten
	for layer in layers:
		var layer_data = {}
		var features = layer.features()
		layer_data["features"] = []

		# Extrahiere alle Feature-Daten
		for feature in features:
			var feature_data = {}

			# Tags extrahieren
			feature_data["tags"] = feature.tags(layer)

			# Geometrie extrahieren
			feature_data["geometry"] = feature.geometry()

			layer_data["features"].append(feature_data)

		safe_data["layers"].append(layer_data)

	return safe_data

# Der Worker arbeitet nur noch mit primitiven Datentypen
func _raster_worker_loop():
	while true:
		queue_mutex.lock()
		var task = null
		if not rasterization_queue.is_empty():
			task = rasterization_queue.pop_front()
		queue_mutex.unlock()

		if task != null:
			var coord = task.coord
			var safe_mvt_data = task.safe_mvt_data  # Keine Godot-Objekte mehr!
			var total_pixel_dim: int = task.resolution
			var sub_chunk_resolution: int = total_pixel_dim / DebugManager.SUB_CHUNKS_PER_AXIS

			var type_map = {
				"water": 1, "grass": 2, "grassland": 3, "farmland": 4,
				"residential": 5, "vineyard": 6, "wood": 7, "forest": 7,
			}
			var render_order = ["water", "grass", "grassland", "farmland", "vineyard", "wood", "forest", "residential"]
			render_order.reverse()

			var sub_chunk_world_size: int = DebugManager.TILE_WORLD_SIZE / DebugManager.SUB_CHUNKS_PER_AXIS

			var config = {
				"sub_chunk_resolution": sub_chunk_resolution,
				"sub_chunks_per_axis": DebugManager.SUB_CHUNKS_PER_AXIS,
				"sub_chunk_world_size": sub_chunk_world_size,
				"type_map": type_map,
				"render_order": render_order,
				"sub_chunks_to_render": task.responsible_for_sub_chunks,
				"tile_state": task.tile_state,
			}

			# C++ erhÃ¤lt jetzt nur noch primitive Daten
			#var start_time = Time.get_ticks_usec()
			var serialized_bytes: String = RasterizerUtils.rasterize_tile_data_safe(safe_mvt_data, config)
			#print(Time.get_ticks_usec() - start_time)
			var cpp_result: Dictionary
			if not serialized_bytes.is_empty():
				cpp_result = Marshalls.base64_to_variant(serialized_bytes)
			else:
				cpp_result = {}

			var result_package = {
				"cpp_result": cpp_result,
				#"raster_tile": task.raster_tile_data,  # Auch das Raster-Tile wurde vorverarbeitet
				"sub_chunk_resolution": sub_chunk_resolution # <-- NEU HINZUGEFÃœGT
			}

			results_mutex.lock()
			results_queue.push_back({
					"coord": task.coord,
					"state_id": task.state_id,
					"package": result_package})
			results_mutex.unlock()
		else:
			OS.delay_msec(10)

func _process(_delta: float) -> void:
	#limbo.position = world_container.position
	_process_rasterization_results()

	var sub_chunks_built_this_frame = 0

	for state: TileState in managed_tile_states.values():

		if sub_chunks_built_this_frame >= DebugManager.features_per_frame:
			break
		if state.current_state == TileState.State.BUILDING:
			_process_tile_building(state)
			sub_chunks_built_this_frame += 1
# chunk_generator.gd


func _process_tile_building(state: TileState) -> void:
	if state.is_cancelled():
		return

	var sub_chunks_to_build = state.build_data.sub_chunks_to_build
	if sub_chunks_to_build.is_empty():
		state.current_state = TileState.State.READY
		return

	if state.build_progress_index >= sub_chunks_to_build.size():
		# Alle Sub-Chunks wurden verarbeitet
		state.current_state = TileState.State.READY
		world_builder.finish_tile_build(state.coord)
		return

	# Nimm den nächsten Sub-Chunk aus der Liste
	var sub_chunk_data: SubChunkBuildData = sub_chunks_to_build[state.build_progress_index]
	var parent_node: Node3D = world_builder.loaded_tile_nodes.get(state.coord)
	if not is_instance_valid(parent_node):
		# Parent wurde entfernt, Bau abbrechen
		state.build_progress_index += 1
		return

	# NEUE LOGIK: Prüfe, ob bereits ein Sub-Chunk mit dieser Koordinate existiert
	var sub_chunk_coord = sub_chunk_data.coord
	var existing_node = state.managed_sub_chunk_nodes.get(sub_chunk_coord)

	# Fall 1: Es gibt bereits einen aktiven Sub-Chunk mit dieser Koordinate
	if is_instance_valid(existing_node):
		# Prüfe die Auflösung des existierenden Sub-Chunks
		var existing_resolution = _extract_resolution_from_node_name(existing_node.name)
		var new_resolution = sub_chunk_data.resolution

		if existing_resolution == new_resolution:
			# Gleiche Auflösung -> Überspringe diesen Build-Vorgang
			#print("Sub-Chunk ", sub_chunk_coord, " mit Auflösung ", new_resolution, " existiert bereits. Überspringe.")
			state.build_progress_index += 1
			return
		else:
			# Verschiedene Auflösung -> Ersetze den alten
			_move_old_sub_chunk_to_limbo(state, existing_node, sub_chunk_coord)

	# Fall 2: Es gibt einen Sub-Chunk im Warteraum (pending_replacements)
	elif state.pending_replacements.has(sub_chunk_coord):
		var pending_node = state.pending_replacements[sub_chunk_coord]
		if is_instance_valid(pending_node):
			var pending_resolution = _extract_resolution_from_node_name(pending_node.name)
			var new_resolution = sub_chunk_data.resolution

			if pending_resolution == new_resolution:
				# Gleiche Auflösung -> Hole den Node aus dem Limbo zurück
				#print("Sub-Chunk ", sub_chunk_coord, " mit gewünschter Auflösung ", new_resolution, " ist bereits im Limbo. Stelle wieder her.")
				_restore_sub_chunk_from_limbo(state, pending_node, sub_chunk_coord, parent_node)
				state.build_progress_index += 1
				return

	# Erstelle einen neuen Sub-Chunk
	var new_sub_chunk_node: Node3D = world_builder.build_chunk_visuals(state.coord, sub_chunk_data)

	if is_instance_valid(new_sub_chunk_node):
		state.managed_sub_chunk_nodes[sub_chunk_coord] = new_sub_chunk_node

		# Lösche den alten Node aus dem Warteraum, falls vorhanden
		if state.pending_replacements.has(sub_chunk_coord):
			var old_node_to_delete: Node3D = state.pending_replacements[sub_chunk_coord]
			if is_instance_valid(old_node_to_delete):
				#print("Lösche veralteten Sub-Chunk ", sub_chunk_coord, " aus dem Limbo.")
				old_node_to_delete.free()
			state.pending_replacements.erase(sub_chunk_coord)

	# Fortschritt aktualisieren
	state.build_progress_index += 1

# HILFSFUNKTIONEN für die verbesserte Sub-Chunk-Verwaltung

func _extract_resolution_from_node_name(node_name: String) -> int:
	# Extrahiert die Auflösung aus Namen wie "SubChunk_Vector2i(1, 2)_Res256"
	var res_index = node_name.find("_Res")
	if res_index == -1:
		return 0

	var res_string = node_name.substr(res_index + 4)  # +4 für "_Res"
	return res_string.to_int()

func _move_old_sub_chunk_to_limbo(state: TileState, old_node: Node3D, sub_chunk_coord: Vector2i):
	# Verschiebe den alten Sub-Chunk in den Limbo
	var parent_pos: Vector3 = old_node.get_parent().position
	old_node.get_parent().remove_child(old_node)
	old_node.position += parent_pos
	limbo.add_child(old_node)

	state.pending_replacements[sub_chunk_coord] = old_node
	state.managed_sub_chunk_nodes.erase(sub_chunk_coord)
	#print("Sub-Chunk ", sub_chunk_coord, " in Limbo verschoben für Auflösungsänderung.")

func _restore_sub_chunk_from_limbo(state: TileState, node: Node3D, sub_chunk_coord: Vector2i, parent_node: Node3D):
	# Stelle einen Sub-Chunk aus dem Limbo wieder her
	var limbo_pos = node.position
	limbo.remove_child(node)
	node.position = limbo_pos - parent_node.position
	parent_node.add_child(node)

	state.managed_sub_chunk_nodes[sub_chunk_coord] = node
	state.pending_replacements.erase(sub_chunk_coord)

# VERBESSERTE JOB-VORBEREITUNG: Verhindere doppelte Jobs

func _prepare_rasterizer_jobs_for(state: TileState, sub_chunks_to_create: Dictionary = {}):

	if state.lod_package.max_resolution == 0:
		print("max_resolution = 0")
		# Dies ist eine reine Raster-Kachel
		state.build_data = TileBuildData.new()
		state.build_data.parent_coord = state.coord
		_prepare_raster_tile_for_build(state)
		world_builder.start_tile_build(state.build_data)
		state.current_state = TileState.State.READY
		return # Wichtig: Keine Jobs erstellen!


	# 1. Zustand auf RASTERIZING setzen
	state.current_state = TileState.State.RASTERIZING

	# Daten aus dem State-Objekt holen
	var coord = state.coord
	var raw_data: Dictionary = state.raw_data

	if !raw_data.has("mvt_tile"):
		_on_data_failed(coord)
		return
	var safe_mvt_data = _extract_mvt_data_safely(raw_data.mvt_tile)
	if safe_mvt_data.is_empty():
		_on_data_failed(coord)
		return

	# NEUE LOGIK: Filtere bereits vorhandene Sub-Chunks heraus
	var sub_chunks_by_res: Dictionary
	var is_delta_update = not sub_chunks_to_create.is_empty()

	if is_delta_update:
		# Delta-Update: Filtere Sub-Chunks, die bereits mit der gewünschten Auflösung existieren
		sub_chunks_by_res = _filter_existing_sub_chunks(state, sub_chunks_to_create)
	else:
		# Initialer Bau: Berechne alles aus dem LOD-Paket, aber filtere Existierende
		sub_chunks_by_res = {}
		var sub_chunk_resolutions = state.lod_package.sub_chunk_resolutions
		for sub_chunk_coord: Vector2i in sub_chunk_resolutions:
			var resolution = sub_chunk_resolutions.get(sub_chunk_coord, 0)
			if resolution > 0:
				# Prüfe, ob bereits ein Sub-Chunk mit dieser Auflösung existiert
				if _sub_chunk_already_exists_with_resolution(state, sub_chunk_coord, resolution):
					continue

				var res_array: Array[Vector2i] = []
				if not sub_chunks_by_res.has(resolution):
					sub_chunks_by_res[resolution] = res_array
				sub_chunks_by_res[resolution].append(sub_chunk_coord)

	if sub_chunks_by_res.is_empty():
		#print("Keine neuen Sub-Chunks zu erstellen für Tile ", coord)
		_check_if_tile_is_fully_processed(coord)
		return

	#print("Starte Jobs für ", sub_chunks_by_res.size(), " Auflösungsgruppen in Tile ", coord)

	# Job-Zählung (angepasst)
	var new_job_count = sub_chunks_by_res.size()
	if is_delta_update:
		state.rasterizer_jobs_total += new_job_count
	else:
		state.rasterizer_jobs_total = new_job_count
		state.rasterizer_jobs_done = 0

	# Job-Erstellung (unverändert)
	var tile_extent = safe_mvt_data.get("tile_extent", 4096.0)

	for target_resolution in sub_chunks_by_res:
		var sub_chunks_in_group: Array[Vector2i] = sub_chunks_by_res[target_resolution]
		var filtered_safe_mvt_data = _filter_features_for_sub_chunks(safe_mvt_data, sub_chunks_in_group, target_resolution, tile_extent)

		if filtered_safe_mvt_data.layers.is_empty():
			_check_if_tile_is_fully_processed(coord)
			continue

		queue_mutex.lock()
		rasterization_queue.push_back({
			"coord": coord,
			"state_id": state.state_id,
			"safe_mvt_data": filtered_safe_mvt_data,
			"resolution": target_resolution,
			"responsible_for_sub_chunks": sub_chunks_in_group,
			"tile_state": state
		})
		queue_mutex.unlock()

func _filter_existing_sub_chunks(state: TileState, sub_chunks_to_create: Dictionary) -> Dictionary:
	var filtered_dict: Dictionary = {}

	for resolution in sub_chunks_to_create:
		var sub_chunk_coords: Array[Vector2i] = sub_chunks_to_create[resolution]
		var filtered_coords: Array[Vector2i] = []

		for coord in sub_chunk_coords:
			if not _sub_chunk_already_exists_with_resolution(state, coord, resolution):
				filtered_coords.append(coord)

		if not filtered_coords.is_empty():
			filtered_dict[resolution] = filtered_coords

	return filtered_dict

func _sub_chunk_already_exists_with_resolution(state: TileState, sub_chunk_coord: Vector2i, target_resolution: int) -> bool:
	# Prüfe aktive Sub-Chunks
	if state.managed_sub_chunk_nodes.has(sub_chunk_coord):
		var existing_node = state.managed_sub_chunk_nodes[sub_chunk_coord]
		if is_instance_valid(existing_node):
			var existing_resolution = _extract_resolution_from_node_name(existing_node.name)
			if existing_resolution == target_resolution:
				return true

	# Prüfe Sub-Chunks im Warteraum
	if state.pending_replacements.has(sub_chunk_coord):
		var pending_node = state.pending_replacements[sub_chunk_coord]
		if is_instance_valid(pending_node):
			var pending_resolution = _extract_resolution_from_node_name(pending_node.name)
			if pending_resolution == target_resolution:
				return true

	return false



func _process_rasterization_results():
	results_mutex.lock()
	if results_queue.is_empty():
		results_mutex.unlock()
		return

	var finished_tasks = results_queue.duplicate()
	results_queue.clear()
	results_mutex.unlock()

	for task in finished_tasks:
		_on_rasterization_finished(task.coord, task.state_id ,task.package)

# Die alte _on_tile_required wird komplett ersetzt durch diese neue Funktion:
func _on_tile_lod_update(coord: Vector2i, new_lod_package: Dictionary) -> void:
	var state: TileState

	# Fall 1: Wir kennen diese Kachel noch gar nicht.
	if not managed_tile_states.has(coord):
		state = TileState.new(coord, new_lod_package)
		state.state_id = next_state_id
		next_state_id += 1
		managed_tile_states[coord] = state

		# Daten anfordern, der Rest des Prozesses wird von _on_data_ready Ã¼bernommen
		state.current_state = TileState.State.DATA_REQUESTED
		DataSourceManager.request_tile_data(coord)
		return # Wichtig: Hier aufhÃ¶ren fÃ¼r neue Kacheln

	# Fall 2: Wir kennen die Kachel, es ist ein LOD-Update.
	state = managed_tile_states[coord]
	var old_lod_package: Dictionary = state.lod_package


	# Nichts tun, wenn sich nichts geÃ¤ndert hat, wird hÃ¶chstwahrscheinlihc nie eintreffen,
	# weil WorldStreamer nur ein Update anfordert, wenn sich was geÃ¤ndert hat.
	if old_lod_package.sub_chunk_resolutions.hash() == new_lod_package.sub_chunk_resolutions.hash():
		return
	# --- HIER BEGINNT DIE NEUE "SWAP"-LOGIK ---
	var sub_chunks_to_destroy: Array[Vector2i] = []
	var sub_chunks_to_create: Dictionary = {}

	# 1. Delta berechnen (unverÃ¤ndert)
	for y in range(DebugManager.SUB_CHUNKS_PER_AXIS):
		for x in range(DebugManager.SUB_CHUNKS_PER_AXIS):
			var sc_coord = Vector2i(x, y)
			var old_res = old_lod_package.sub_chunk_resolutions.get(sc_coord, 0)
			var new_res = new_lod_package.sub_chunk_resolutions.get(sc_coord, 0)

			if old_res != new_res:
				if old_res > 0:
					sub_chunks_to_destroy.append(sc_coord)
				if new_res > 0:
					if not sub_chunks_to_create.has(new_res):
						sub_chunks_to_create[new_res] = [] as Array[Vector2i]
					sub_chunks_to_create[new_res].append(sc_coord)
	##print("sub_chunks_to_create: ", sub_chunks_to_create)
	# 2. Veraltete Sub-Chunks verwalten
	for sc_coord in sub_chunks_to_destroy:
		if state.managed_sub_chunk_nodes.has(sc_coord):
			var old_node: Node3D = state.managed_sub_chunk_nodes[sc_coord]
			if not is_instance_valid(old_node):
				state.managed_sub_chunk_nodes.erase(sc_coord)
				continue
			# Gibt es einen Ersatz fÃ¼r diesen Node?
			var has_replacement = false
			for res_group in sub_chunks_to_create.values():
				if sc_coord in res_group:
					has_replacement = true
					break

			if has_replacement:
				# Ja -> In den Warteraum verschieben
				state.pending_replacements[sc_coord] = old_node
				var parent_pos: Vector3 = old_node.get_parent().position
				old_node.get_parent().remove_child(old_node)
				old_node.position += parent_pos
				limbo.add_child(old_node)
			else:
				# Nein -> Sofort lÃ¶schen (wird nicht mehr gebraucht)
				if is_instance_valid(old_node):
					old_node.free()
					#old_node.queue_free()

			# In jedem Fall aus der Liste der aktiven Nodes entfernen
			state.managed_sub_chunk_nodes.erase(sc_coord)

	# 3. Neue Jobs starten
	if not sub_chunks_to_create.is_empty():
		# WICHTIG: Funktioniert fÃ¼r Kacheln in RASTERIZING und READY Zustand!
		# Die Daten sind ja bereits im state.raw_data vorhanden.
		_prepare_rasterizer_jobs_for(state, sub_chunks_to_create)

	# 4. LOD-Paket fÃ¼r zukÃ¼nftige Vergleiche aktualisieren
	state.lod_package = new_lod_package

		##print("has_replacement, but build_progress is already bigger as sub_chunks_to_build")

func _on_tile_no_longer_required(coord: Vector2i) -> void:
	if managed_tile_states.has(coord):
		var state: TileState = managed_tile_states[coord]
		state.current_state = TileState.State.CANCELLED
		_cancel_pending_rasterizer_jobs(coord)
		#Gehe durch alle gemanagten Sub-Chunk-Nodes und entferne sie.
		for node in state.managed_sub_chunk_nodes.values():
			if is_instance_valid(node):
				node.free()
		for node in state.pending_replacements.values():
			if is_instance_valid(node):
				node.free()
				#node.queue_free()
		# WICHTIG: Den State nicht sofort lÃ¶schen, die Worker mÃ¼ssen
		# erst darauf reagieren kÃ¶nnen. Ein AufrÃ¤umprozess kÃ¼mmert sich spÃ¤ter darum.
		world_builder.remove_tile(coord)
		# Entferne den State aus unserer Verwaltung
		managed_tile_states.erase(coord)

func _cancel_pending_rasterizer_jobs(coord_to_cancel: Vector2i):
	queue_mutex.lock()

	# Erstelle eine neue Liste mit allen Jobs, die NICHT abgebrochen werden sollen
	var new_queue: Array = []
	for job in rasterization_queue:
		if job.coord != coord_to_cancel:
			new_queue.append(job)

	# Ersetze die alte Queue durch die neue, gefilterte Queue
	rasterization_queue = new_queue

	queue_mutex.unlock()


# ENTSCHEIDENDE Ã„NDERUNG: Datenextraktion im Hauptthread
func _on_data_ready(coord: Vector2i, data: Dictionary) -> void:
	if not managed_tile_states.has(coord): return
	var state: TileState = managed_tile_states[coord]
	if state.is_cancelled(): return

	state.raw_data = data
	state.current_state = TileState.State.RASTERIZING
	_prepare_rasterizer_jobs_for(state)



func _filter_features_for_sub_chunks(source_data: Dictionary, sub_chunks: Array[Vector2i], target_res: int, tile_extent: float) -> Dictionary:
	var filtered_data = {"tile_extent": tile_extent, "layers": []}
	var total_pixel_dim = float(target_res) * DebugManager.SUB_CHUNKS_PER_AXIS
	var scale_vec_to_pixel = total_pixel_dim / tile_extent

	# Erstelle eine Bounding Box, die alle Sub-Chunks in dieser Gruppe umschlieÃŸt
	var group_bounds: Rect2
	for i in range(sub_chunks.size()):
		var sc_coord = sub_chunks[i]
		var rect = Rect2(sc_coord * target_res, Vector2(target_res, target_res))
		if i == 0:
			group_bounds = rect
		else:
			group_bounds = group_bounds.merge(rect)

	for layer in source_data.layers:
		var filtered_layer = {"features": []}
		for feature in layer.features:
			var feature_bounds_pixels = _calculate_feature_bounds(feature, scale_vec_to_pixel)
			if group_bounds.intersects(feature_bounds_pixels):
				filtered_layer.features.append(feature)

		if not filtered_layer.features.is_empty():
			filtered_data.layers.append(filtered_layer)

	return filtered_data

func _calculate_feature_bounds(feature: Dictionary, scale: float) -> Rect2:
	var geometry = feature.get("geometry", [])
	if geometry.is_empty(): return Rect2()

	var cursor = Vector2.ZERO
	var min_p: Vector2
	var max_p: Vector2
	var first_point = true

	for cmd_seq in geometry:
		var cmd_id = cmd_seq[0]
		if cmd_id == 1 or cmd_id == 2: # MoveTo or LineTo
			for i in range(1, cmd_seq.size(), 2):
				cursor += Vector2(cmd_seq[i], cmd_seq[i+1])
				var point = cursor * scale
				if first_point:
					min_p = point
					max_p = point
					first_point = false
				else:
					min_p.x = min(min_p.x, point.x)
					min_p.y = min(min_p.y, point.y)
					max_p.x = max(max_p.x, point.x)
					max_p.y = max(max_p.y, point.y)

	if first_point: return Rect2()
	return Rect2(min_p, max_p - min_p)

func _on_rasterization_finished(coord: Vector2i, job_state_id: int ,package: Dictionary):
	if not managed_tile_states.has(coord): return
	var current_state_for_coord: TileState = managed_tile_states[coord]

	# WICHTIG: Die entscheidende PrÃ¼fung!
	if current_state_for_coord.state_id != job_state_id:
		return
	var state: TileState = current_state_for_coord
	if state.is_cancelled(): return

	# HOLEN der bereits deserialisierten Daten. Kein teurer Parse-Vorgang mehr!
	var cpp_result = package.cpp_result

	if cpp_result.is_empty():
		_check_if_tile_is_fully_processed(coord) # Zähle auch fehlgeschlagene Jobs
		return

	if state.build_data == null:
		state.build_data = TileBuildData.new()
		state.build_data.parent_coord = coord
		_prepare_raster_tile_for_build(state)

	# Dieser Aufruf ist jetzt der einzige nennenswerte Aufwand im Hauptthread
	var source_sub_chunk_res: int = package.get("sub_chunk_resolution", 0)
	var sub_chunk_list_part: Array[SubChunkBuildData] = _convert_cpp_result_to_sub_chunk_list(cpp_result, source_sub_chunk_res)

	state.build_data.sub_chunks_to_build.append_array(sub_chunk_list_part)
	_check_if_tile_is_fully_processed(coord)

func _prepare_raster_tile_for_build(state: TileState):
	var raw_raster_tile = state.raw_data.get("raster_tile")
	if raw_raster_tile != null:
		var raster_tile_image = Image.create_from_data(
			raw_raster_tile.get_width(),
			raw_raster_tile.get_height(),
			false,
			raw_raster_tile.get_format(),
			raw_raster_tile.get_data()
		)
		state.build_data.raster_tile = raster_tile_image

func _check_if_tile_is_fully_processed(coord: Vector2i):
	if not managed_tile_states.has(coord): return

	var state: TileState = managed_tile_states[coord]

	state.rasterizer_jobs_done += 1

	if state.rasterizer_jobs_done >= state.rasterizer_jobs_total:
		# Alle Jobs fÃ¼r diese Kachel sind fertig!
		if state.build_data == null or state.build_data.sub_chunks_to_build.is_empty():
			_on_data_failed(coord)
			return
		world_builder.start_tile_build(state.build_data)
		# Zustand Ã¤ndern und in die Bau-Warteschlange legen
		state.current_state = TileState.State.BUILDING
		#creation_queue.push_back(state.build_data)

func _convert_cpp_result_to_sub_chunk_list(cpp_result: Dictionary, sub_chunk_res: int) -> Array[SubChunkBuildData]:
	if cpp_result.is_empty(): return []

	var sub_chunk_list: Array[SubChunkBuildData] = []
	var cpp_sub_chunks = cpp_result.get("sub_chunks", {})
	var type_map = cpp_result.get("type_map", {})

	for sub_chunk_coord in cpp_sub_chunks:
		var cpp_chunk_data = cpp_sub_chunks[sub_chunk_coord]
		var logic_map_bytes = cpp_chunk_data.get("logic_map_bytes")
		var veg_buffers = cpp_chunk_data.get("vegetation_buffers", {})

		if logic_map_bytes != null and not logic_map_bytes.is_empty():
			var sub_chunk_data = SubChunkBuildData.new()
			sub_chunk_data.coord = sub_chunk_coord
			sub_chunk_data.logic_map = Image.create_from_data(
				sub_chunk_res, sub_chunk_res, false, Image.FORMAT_R8, logic_map_bytes
			)
			sub_chunk_data.type_map = type_map
			sub_chunk_data.vegetation_buffers = veg_buffers
			sub_chunk_data.resolution = sub_chunk_res
			sub_chunk_list.append(sub_chunk_data)

	return sub_chunk_list


func _on_data_failed(coord: Vector2i) -> void:
	world_builder.build_empty_tile(coord)
