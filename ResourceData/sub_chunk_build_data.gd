# sub_chunk_build_data.gd
class_name SubChunkBuildData extends Resource

# Enthält die aufbereitete logic_map für EINEN Sub-Chunk

@export var coord: Vector2i
@export var logic_map: Image
@export var type_map: Dictionary
@export var vegetation_buffers: Dictionary
@export var resolution: int 
