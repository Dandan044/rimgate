extends SceneTree

func _init():
	var base := "D:/Dandan/rimgate/docs/art_review/pawn_refined_v1/"
	DirAccess.make_dir_recursive_absolute(base + "png")
	var files := DirAccess.get_files_at(base + "svg")
	for name in files:
		if not name.ends_with(".svg"):
			continue
		var content := FileAccess.get_file_as_string(base + "svg/" + name)
		var art := Image.new()
		var result := art.load_svg_from_string(content)
		if result != OK:
			push_error(name + ": " + str(result))
			quit(1)
			return
		art.save_png(base + "png/" + name.get_basename() + ".png")
	print("REFINED_RENDER_OK: ", files.size(), " assets")
	quit()
