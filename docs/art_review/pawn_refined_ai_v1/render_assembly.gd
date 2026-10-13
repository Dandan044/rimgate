extends SceneTree
func _init() -> void:
	var root := "res://docs/art_review/pawn_refined_ai_v1/"
	DirAccess.make_dir_recursive_absolute(root + "assembly-png")
	for filename in DirAccess.get_files_at(root + "assembly-svg"):
		if filename.ends_with(".svg"):
			var art := Image.new()
			if art.load_svg_from_string(FileAccess.get_file_as_string(root + "assembly-svg/" + filename)) != OK:
				quit(1)
				return
			if art.save_png(root + "assembly-png/" + filename.get_basename() + ".png") != OK:
				quit(2)
				return
	print("AI_ASSEMBLY_RENDER_OK")
	quit(0)
