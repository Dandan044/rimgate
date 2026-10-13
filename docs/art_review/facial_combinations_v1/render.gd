extends SceneTree

func save_svg(content: String, destination: String) -> bool:
	var art := Image.new()
	if art.load_svg_from_string(content) != OK:
		return false
	return art.save_png(destination) == OK

func _init() -> void:
	var root := "res://docs/art_review/facial_combinations_v1/"
	DirAccess.make_dir_recursive_absolute(root + "png")
	DirAccess.make_dir_recursive_absolute(root + "frames")
	for filename in DirAccess.get_files_at(root + "svg"):
		if filename.ends_with(".svg") and not save_svg(FileAccess.get_file_as_string(root + "svg/" + filename), root + "png/" + filename.get_basename() + ".png"):
			quit(1)
			return
	var animation: Array = JSON.parse_string(FileAccess.get_file_as_string(root + "animation.json"))
	for frame in range(animation.size()):
		for column in range(6):
			if not save_svg(String(animation[frame][column]), root + "frames/%02d-%d.png" % [frame,column]):
				quit(2)
				return
	print("FACE_COMBINATION_RENDER_OK: 46 SVGs and 216 portrait animation views")
	quit(0)
