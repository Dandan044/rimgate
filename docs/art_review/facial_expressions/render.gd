extends SceneTree

func render_svg(content: String, destination: String) -> bool:
	var picture := Image.new()
	if picture.load_svg_from_string(content) != OK:
		return false
	return picture.save_png(destination) == OK

func _init() -> void:
	var root := "res://docs/art_review/facial_expressions/"
	DirAccess.make_dir_recursive_absolute(root + "png")
	DirAccess.make_dir_recursive_absolute(root + "frames")
	for filename in DirAccess.get_files_at(root + "svg"):
		if filename.ends_with(".svg"):
			if not render_svg(FileAccess.get_file_as_string(root + "svg/" + filename), root + "png/" + filename.get_basename() + ".png"):
				push_error(filename)
				quit(1)
				return
	var animation: Array = JSON.parse_string(FileAccess.get_file_as_string(root + "animation.json"))
	for frame in range(animation.size()):
		for style in range(3):
			if not render_svg(String(animation[frame][style]), root + "frames/%d-%02d.png" % [style, frame]):
				quit(2)
				return
	print("FACE_RENDER_OK: 25 SVG assets and 144 animated frames")
	quit(0)
