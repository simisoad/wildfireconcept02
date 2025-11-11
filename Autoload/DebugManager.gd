# debug_manager.gd
extends Node

# --- Globale Konfiguration ---
const TILE_ZOOM_LEVEL = 14
const SUB_CHUNK_RESOLUTION: int = 256 # Auflösung eines einzelnen Render-Chunks (MultiMesh)
const SUB_CHUNKS_PER_AXIS: int = 4 # 10->256m pro Kachel, 40->64m pro Kachel
const TILE_WORLD_SIZE: float = 2048.0 # Gesamtgrösse einer Vektor-Kachel in Metern
const start_x: int = 8400
const start_y: int = 10440
# --- Debug-Flags ---
var should_load_multimesh_vegetation: bool = false
var should_load_shader_terrain: bool = true
#var should_load_csg: bool = false # Vorerst deaktiviert
var should_load_raster_overlay: bool = true
var features_per_frame: int = 1 # Wie viele Sub-Chunks pro Frame gebaut werden

# --- Referenzen ---
var debug_label: Label
var debug_label2: Label
func _ready() -> void:
	await get_tree().process_frame
	debug_label = get_tree().root.get_node_or_null("Main/Debug/VBoxContainer/HBoxContainer/Label")
	debug_label2 = get_tree().root.get_node_or_null("Main/Debug//VBoxContainer/Label2")

func update_debug_text(text: String) -> void:
	if is_instance_valid(debug_label):
		debug_label.text = text
func update_debug_text2(text: String) -> void:
	if is_instance_valid(debug_label2):
		debug_label2.text = text
func get_debug_text() -> String:
	if is_instance_valid(debug_label):
		return debug_label.text
	return ""
