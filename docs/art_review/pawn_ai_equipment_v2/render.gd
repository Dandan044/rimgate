extends SceneTree
func _init() -> void:
	var root := "res://docs/art_review/pawn_ai_equipment_v2/"
	DirAccess.make_dir_recursive_absolute(root + "png")
	for filename in DirAccess.get_files_at(root + "svg"):
		if filename.ends_with(".svg"):
			var art := Image.new()
			if art.load_svg_from_string(FileAccess.get_file_as_string(root + "svg/" + filename)) != OK:
				quit(1)
				return
			if art.save_png(root + "png/" + filename.get_basename() + ".png") != OK:
				quit(2)
				return
	print("EQUIPMENT_PNG_OK")
	quit(0)
