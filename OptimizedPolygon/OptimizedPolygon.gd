# Spatial Optimization: Vorverarbeitete Polygon-Daten für Ultra-Performance
class_name OptimizedPolygon

var polygon: PackedVector2Array
var bounds: Rect2
var grid_size: int = 2 # 8x8 Grid pro Polygon
var grid: Array[Array] # 2D-Array mit boolean values
var needs_precise_test: bool = false

func _init(poly: PackedVector2Array):
	polygon = poly
	bounds = _calculate_bounds(poly)
	_precompute_grid()

func _calculate_bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	
	var min_p = poly[0]
	var max_p = poly[0]
	
	for i in range(1, poly.size()):
		var p = poly[i]
		if p.x < min_p.x: min_p.x = p.x
		if p.y < min_p.y: min_p.y = p.y
		if p.x > max_p.x: max_p.x = p.x
		if p.y > max_p.y: max_p.y = p.y
	
	return Rect2(min_p, max_p - min_p)

func _precompute_grid():
	grid = []
	var cell_width = bounds.size.x / grid_size
	var cell_height = bounds.size.y / grid_size
	
	for y in range(grid_size):
		var row = []
		for x in range(grid_size):
			var cell_center = Vector2(
				bounds.position.x + (x + 0.5) * cell_width,
				bounds.position.y + (y + 0.5) * cell_height
			)
			
			var is_inside = Geometry2D.is_point_in_polygon(cell_center, polygon)
			row.append(is_inside)
			
			# Markiere Polygon als komplex wenn Nachbarzellen unterschiedlich sind
			if not needs_precise_test:
				if x > 0 and row[x] != row[x-1]:
					needs_precise_test = true
				if y > 0 and is_inside != grid[y-1][x]:
					needs_precise_test = true
		
		grid.append(row)

func test_point(point: Vector2) -> bool:
	# Schneller Bounding-Box-Test
	if not bounds.has_point(point):
		return false
	
	# Grid-Lookup für einfache Fälle
	var rel_x = (point.x - bounds.position.x) / bounds.size.x
	var rel_y = (point.y - bounds.position.y) / bounds.size.y
	
	var grid_x = int(rel_x * grid_size)
	var grid_y = int(rel_y * grid_size)
	
	# Clamp values
	grid_x = max(0, min(grid_size - 1, grid_x))
	grid_y = max(0, min(grid_size - 1, grid_y))
	
	var grid_result = grid[grid_y][grid_x]
	
	# Für einfache Polygone: verwende Grid-Ergebnis
	if not needs_precise_test:
		return grid_result
	
	# Für komplexe Polygone: Grid als Hint, präziser Test nur bei Grenzfällen
	var cell_width = bounds.size.x / grid_size
	var cell_height = bounds.size.y / grid_size
	
	var cell_center = Vector2(
		bounds.position.x + (grid_x + 0.5) * cell_width,
		bounds.position.y + (grid_y + 0.5) * cell_height
	)
	
	# Wenn Punkt nah am Zellzentrum ist, verwende Grid-Ergebnis
	if point.distance_to(cell_center) < min(cell_width, cell_height) * 0.3:
		return grid_result
	
	# Sonst: robuster Test
	return _robust_point_in_polygon_optimized(point)

func _robust_point_in_polygon_optimized(point: Vector2) -> bool:
	var inside = false
	var n = polygon.size()
	var j = n - 1
	
	for i in range(n):
		var pi = polygon[i]
		var pj = polygon[j]
		
		if ((pi.y > point.y) != (pj.y > point.y)) and \
			(point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x):
				inside = !inside
		
		j = i
	
	return inside
