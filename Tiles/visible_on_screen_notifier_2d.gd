class_name ChunkTileVisible extends VisibleOnScreenNotifier2D

var my_node: Node2D

func _init(p_my_node: Node2D) -> void:
	self.screen_entered.connect(_on_screen_entered)
	self.screen_exited.connect(_on_screen_exited)
	self.my_node = p_my_node

	


func _on_screen_entered() -> void:
	pass
	#self.my_node.visible = true


func _on_screen_exited() -> void:
	pass
	#self.my_node.visible = false
