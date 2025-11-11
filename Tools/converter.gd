extends Node2D



func _ready() -> void:
	var file: = FileAccess.open('res://Layer.txt',FileAccess.READ_WRITE)
	var text: String = file.get_as_text()
	text = text.replace(" ", "")
	var array: Array = text.split("\n")

	var new_text: String
	for string: String in array:
		var str: Array = string.split("=")

		new_text += "\"" + str[0] + "\" : {\"minzoom\": 0,\"maxzoom\": 14}"  + ",\n"

	print(new_text)
