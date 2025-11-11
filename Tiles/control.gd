extends CanvasLayer


func _process(delta: float) -> void:
	$Label.text = "FPS: " + str(Engine.get_frames_per_second())
	$Label.text += ", zoom level: " + str(%Camera2D.zoom.x)
	$Label.text += ", Camera_Pos: " + str(%Camera2D.offset)
