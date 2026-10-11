extends SceneTree

func _initialize() -> void:
	var file := FileAccess.open("res://docs/GODOT_LICENSE.txt", FileAccess.WRITE)
	file.store_string(Engine.get_license_text())
	file.close()
	quit()
