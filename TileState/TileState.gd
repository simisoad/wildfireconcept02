# TileState.gd
class_name TileState extends RefCounted

enum State {
	IDLE,               # Nichts zu tun
	DATA_REQUESTED,     # Rohdaten werden vom DataSourceManager geladen
	RASTERIZING,        # Daten werden im ChunkGenerator-Worker verarbeitet
	BUILDING,           # WorldBuilder erstellt die Godot-Nodes
	READY,              # Kachel ist fertig und sichtbar
	CANCELLED,           # Kachel wird nicht mehr benötigt, Abbruch angefordert
	#READY_TO_DRAW
}
var state_id: int = 0
var coord: Vector2i
var current_state: State = State.IDLE
var lod_package: Dictionary = {}

# Daten, die während des Prozesses gesammelt werden
var raw_data: Dictionary = {}              # Ergebnis von DataSourceManager
var build_data: TileBuildData = null      # Ergebnis von ChunkGenerator

# Tracking für asynchrone Jobs
var rasterizer_jobs_total: int = 0
var rasterizer_jobs_done: int = 0

# Verfolgt, welcher Sub-Chunk als nächstes gebaut werden soll
var build_progress_index: int = 0

# Key: Vector2i (Sub-Chunk-Koordinate), Value: Node3D (der Sub-Chunk-Node)
var managed_sub_chunk_nodes: Dictionary = {}
# Ein "Warteraum" für alte Nodes, die auf ihren Ersatz warten.
# Key: Vector2i (Sub-Chunk-Koordinate), Value: Node3D (der alte Node, der gelöscht werden soll)
var pending_replacements: Dictionary = {}


func _init(p_coord: Vector2i, p_lod_package: Dictionary):
	self.coord = p_coord
	self.lod_package = p_lod_package


func is_cancelled() -> bool:
	return self.current_state == State.CANCELLED
