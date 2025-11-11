# tile_build_data.gd
class_name TileBuildData extends Resource

# Enthält alle aufbereiteten Daten für EINE grosse Vektor-Kachel

@export var parent_coord: Vector2i
@export var sub_chunks_to_build: Array[SubChunkBuildData]
@export var raster_tile: Image
