# world_streamer.gd
extends Node3D
var debug: bool = false
# resolution = Auflösung Kachel nicht sub-chunk!
# 2048 -> 128m pro Kachel (128 * 16 = 2048) somit 1.25m Genauigkeit
# 2048 * 1.25 = 2560m, eine mbtile-Kachel deckt 2560m ab (Zoomlevel 14).
#const LOD_LEVELS = [
	#{"distance": 2500, "resolution": 2048},
	#{"distance": 4000, "resolution": 1024},
	#{"distance": 6000, "resolution": 512},
	#{"distance": 8000, "resolution": 256},
#
#]
# Neu von der Fläche abhängig:
const LOD_LEVELS = [
	{"screen_area": 600000, "resolution": 2048},
	{"screen_area": 250000, "resolution": 1024},
	{"screen_area": 100000,  "resolution": 128},
	{"screen_area": 50000,   "resolution": 64},
	{"screen_area": 0,     "resolution": 0}
]
signal tile_lod_update(coord: Vector2i, lod_package: Dictionary)
signal tile_no_longer_required(coord: Vector2i)

var managed_tiles: Dictionary = {}
var world_container: Node3D
var camera3d: Camera3D

var pending_lod_updates: Dictionary = {}
var pending_removals: Dictionary = {}

const UPDATE_DELAY = 0.15
const REMOVAL_DELAY = 2.0
const MAX_TILE_CHECK_RANGE = 1

func _ready() -> void:
	await get_tree().process_frame
	world_container = get_tree().root.get_node("Main/WorldContainer")
	camera3d = get_tree().root.get_node("Main/Player/Camera3D")



func _process(_delta: float) -> void:
	if not is_instance_valid(camera3d): return

	var player_pos: Vector3 = -world_container.position
	_debug_infos(player_pos)

	var player_tile_pos: Vector2i = _world_to_tile_coords(player_pos)
	var required_tiles: Dictionary = {}
	var tile_world_size: float = DebugManager.TILE_WORLD_SIZE
	var sub_chunk_world_size = tile_world_size / DebugManager.SUB_CHUNKS_PER_AXIS

	# Hole die globale Transformation des Containers EINMAL pro Frame.
	var container_transform: Transform3D = world_container.global_transform

	# Feste Schleife um den Spieler herum
	for y in range(player_tile_pos.y - MAX_TILE_CHECK_RANGE, player_tile_pos.y + MAX_TILE_CHECK_RANGE + 1):
		for x in range(player_tile_pos.x - MAX_TILE_CHECK_RANGE, player_tile_pos.x + MAX_TILE_CHECK_RANGE + 1):
			var coord = Vector2i(x, y)

			var sub_chunk_lod_data: Dictionary = {}
			var max_required_resolution: int = 0
			var is_any_sub_chunk_visible = false

			var sub_chunk_world_size_vec = Vector3(sub_chunk_world_size, sub_chunk_world_size, sub_chunk_world_size)

			for sub_y in DebugManager.SUB_CHUNKS_PER_AXIS:
				for sub_x in DebugManager.SUB_CHUNKS_PER_AXIS:
					var sub_chunk_coord = Vector2i(sub_x, sub_y)

					# 1. Berechne die LOKALE Position des Sub-Chunks (relativ zum Container)
					var sub_chunk_local_corner_pos = Vector3(
						(float(x) * tile_world_size) + (float(sub_x) * sub_chunk_world_size),
						0,
						(float(y) * tile_world_size) + (float(sub_y) * sub_chunk_world_size)
					)

					#var sub_chunk_local_center_pos = sub_chunk_local_corner_pos + sub_chunk_world_size_vec / 2.0

					# 2. Erstelle die LOKALE AABB
					var sub_chunk_local_aabb = AABB(sub_chunk_local_corner_pos, sub_chunk_world_size_vec)

					# 3. Transformiere die AABB in den GLOBALEN Raum
					var sub_chunk_global_aabb = container_transform * sub_chunk_local_aabb

					#if sub_chunk_local_corner_pos == Vector3.ZERO:
						#debug = true
						#print("sub_chunk_local_corner_pos: ", sub_chunk_local_corner_pos)
						#print("sub_chunk_world_size_vec: ",sub_chunk_world_size_vec)
						#print("sub_chunk_local_center_pos: ", sub_chunk_local_center_pos)
						#print("sub_chunk_local_aabb: ", sub_chunk_local_aabb)
						#print("sub_chunk_global_aabb: ", sub_chunk_global_aabb)
					#if sub_chunk_global_aabb != sub_chunk_local_aabb:
						#print("sub_chunk_local_aabb: ", sub_chunk_local_aabb)
						#print("sub_chunk_global_aabb: ", sub_chunk_global_aabb)
					# --- KORRIGIERTE KERNLOGIK ---
					if is_aabb_in_frustum(sub_chunk_global_aabb, camera3d):
						print("yo")
						is_any_sub_chunk_visible = true
						#print("is_any_sub_chunk_visible")
						var screen_area: float = _get_sub_chunk_screen_area(sub_chunk_global_aabb)
						var resolution: int = _get_resolution_for_screen_area(screen_area)

						sub_chunk_lod_data[sub_chunk_coord] = resolution
						max_required_resolution = max(max_required_resolution, resolution)
					else:
						sub_chunk_lod_data[sub_chunk_coord] = 0

			if is_any_sub_chunk_visible:
				required_tiles[coord] = {
					"max_resolution": max_required_resolution,
					"sub_chunk_resolutions": sub_chunk_lod_data
				}

	# --- Hysteresis-Logik (Phasen 1, 2, 3) ---
	# Dieser Teil war bereits korrekt und bleibt unverändert.
	var current_time = Time.get_ticks_msec() / 1000.0
	# ... (der gesamte Code für pending_lod_updates und pending_removals) ...
	# --- PHASE 1: Anforderungen sammeln und Verzögerungen managen ---
	for coord: Vector2i in required_tiles.keys():

		var new_lod_package = required_tiles[coord]
		if pending_removals.has(coord):
			pending_removals.erase(coord)
		var needs_request = false
		if not managed_tiles.has(coord) or managed_tiles[coord].sub_chunk_resolutions.hash() != new_lod_package.sub_chunk_resolutions.hash():
			needs_request = true
		if needs_request:
			pending_lod_updates[coord] = [current_time, new_lod_package]
		else:
			if pending_lod_updates.has(coord):
				pending_lod_updates.erase(coord)
	# --- PHASE 2: Veraltete Kacheln zum Löschen markieren ---
	if not managed_tiles.keys().is_empty():
		var tiles_to_check_for_removal: Array = managed_tiles.keys() as Array[Vector2i]
		for coord in tiles_to_check_for_removal:
			if not required_tiles.has(coord):
				if not pending_removals.has(coord):
					pending_removals[coord] = current_time
	# --- PHASE 3: Verzögerte Aktionen ausführen ---
	var updates_to_fire: Dictionary = {}
	for coord in pending_lod_updates.keys():
		var timestamp = pending_lod_updates[coord][0]
		if current_time - timestamp > UPDATE_DELAY:
			updates_to_fire[coord] = pending_lod_updates[coord][1]
	for coord in updates_to_fire.keys():
		var lod_package = updates_to_fire[coord]
		pending_lod_updates.erase(coord)
		managed_tiles[coord] = lod_package
		tile_lod_update.emit(coord, lod_package)
	var removals_to_fire: Array[Vector2i] = []
	for coord in pending_removals.keys():
		var timestamp = pending_removals[coord]
		if current_time - timestamp > REMOVAL_DELAY:
			removals_to_fire.append(coord)
	for coord in removals_to_fire:
		pending_removals.erase(coord)
		managed_tiles.erase(coord)
		tile_no_longer_required.emit(coord)

func _debug_infos(player_pos: Vector3):
	var cam_pos: Vector2i = _world_to_tile_coords(player_pos) # Behalten wir für das Debug-Label
	var cam_pos_chunk: Vector2i = _world_to_chunk_pos(player_pos)
	var fps: float = Engine.get_frames_per_second()
	DebugManager.update_debug_text(str("cam_pos: ", cam_pos, "chunk_pos: ", cam_pos_chunk, " FPS: ", fps, ", cam size: ", camera3d.size))

func _world_to_tile_coords(world_pos: Vector3) -> Vector2i:
	var size: float = DebugManager.TILE_WORLD_SIZE
	return Vector2i(floori(world_pos.x / size), floori(world_pos.z / size))

func _world_to_chunk_pos(world_pos: Vector3) -> Vector2i:
	#var w_tile_pos: Vector2i = _world_to_tile_coords(world_pos)
	var size: float = DebugManager.TILE_WORLD_SIZE / DebugManager.SUB_CHUNKS_PER_AXIS
	var x: int = floori(world_pos.x / size)
	var y: int = floori(world_pos.z / size)
	x %= DebugManager.SUB_CHUNKS_PER_AXIS
	y %= DebugManager.SUB_CHUNKS_PER_AXIS
	if x < 0:
		x += DebugManager.SUB_CHUNKS_PER_AXIS
	if y < 0:
		y += DebugManager.SUB_CHUNKS_PER_AXIS
	return Vector2i(x,y)


func _get_resolution_for_screen_area(screen_area: float) -> int:
	for level in LOD_LEVELS:
		#if distance < 900.0: print(distance)
		if screen_area > level.screen_area:
			return level.resolution
	return LOD_LEVELS[-1].resolution # Fallback

func _get_sub_chunk_screen_area(global_aabb: AABB) -> float:
	var camera = get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		return 0.0

	# Wir haben bereits die globale AABB, also verwenden wir sie direkt.
	var screen_points: Array[Vector2] = []
	for i in 8:
		var corner = global_aabb.get_endpoint(i)
		if camera.is_position_behind(corner):
			continue
		var projected = camera.unproject_position(corner)
		# Manchmal können projizierte Punkte riesige Werte haben, wenn sie nahe am Rand sind.
		# Wir klemmen sie an die Viewport-Größe, um unrealistische Flächen zu vermeiden.
		var viewport_rect = get_viewport().get_visible_rect()
		projected.x = clamp(projected.x, 0, viewport_rect.size.x)
		projected.y = clamp(projected.y, 0, viewport_rect.size.y)
		screen_points.append(projected)

	if screen_points.size() < 2: # Brauchen mindestens 2 Punkte für eine Fläche
		return 0.0

	var min_p = screen_points[0]
	var max_p = screen_points[0]
	for i in range(1, screen_points.size()):
		min_p.x = min(min_p.x, screen_points[i].x)
		min_p.y = min(min_p.y, screen_points[i].y)
		max_p.x = max(max_p.x, screen_points[i].x)
		max_p.y = max(max_p.y, screen_points[i].y)

	var size = max_p - min_p
	return size.x * size.y

func is_aabb_in_frustum(aabb: AABB, camera: Camera3D) -> bool:
	var frustum_planes = camera.get_frustum()

	for plane in frustum_planes:
		# Die Normalen der Frustum-Ebenen zeigen nach innen. Wir müssen prüfen, ob die
		# gesamte AABB auf der "äußeren" Seite der Ebene liegt.
		# Dafür finden wir den Eckpunkt der AABB, der am weitesten in Richtung
		# der Ebenen-Normale liegt (den "p-vertex" oder positiven Vertex).
		# Wenn selbst dieser Punkt auf der Außenseite ist, ist die gesamte Box draußen.

		var p_vertex = aabb.position
		if plane.normal.x > 0:
			p_vertex.x += aabb.size.x
		if plane.normal.y > 0:
			p_vertex.y += aabb.size.y
		if plane.normal.z > 0:
			p_vertex.z += aabb.size.z

		# Der n-vertex (negativer Vertex) ist derjenige, der am weitesten
		# von der Ebenen-Normale entfernt ist.
		var n_vertex = aabb.position
		if plane.normal.x < 0:
			n_vertex.x += aabb.size.x
		if plane.normal.y < 0:
			n_vertex.y += aabb.size.y
		if plane.normal.z < 0:
			n_vertex.z += aabb.size.z

		# Die Methode plane.distance_to(point) ist positiv, wenn der Punkt auf der
		# "inneren" Seite liegt. Wenn der p_vertex eine negative Distanz hat,
		# bedeutet das, dass der "innerste" Punkt der Box immer noch außerhalb ist.
		# Die Box ist also komplett draußen.
		if plane.distance_to(p_vertex) < 0:
			return false # Komplett außerhalb dieser Ebene -> unsichtbar

	# Wenn die Schleife für alle 6 Ebenen durchläuft, ohne dass die Box
	# komplett außerhalb einer davon war, muss sie sichtbar sein.
	return true
