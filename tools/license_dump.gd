extends SceneTree

func _initialize() -> void:
	var output_dir := "res://docs"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--license-output="): output_dir = arg.trim_prefix("--license-output=")
	var file := FileAccess.open(output_dir.path_join("GODOT_LICENSE.txt"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write Godot license notices"); quit(1); return
	file.store_string(Engine.get_license_text())
	file.close()
	file = FileAccess.open(output_dir.path_join("GODOT_THIRD_PARTY_NOTICES.txt"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write Godot third-party notices"); quit(1); return
	file.store_string("Godot Engine " + Engine.get_version_info().string + "\n")
	file.store_string("Generated from the engine binary's copyright and license information.\n\n")
	file.store_string("COPYRIGHTS AND COMPONENT LICENSE IDENTIFIERS\n")
	file.store_string(JSON.stringify(Engine.get_copyright_info(), "\t") + "\n\nLICENSE TEXTS\n")
	var licenses := Engine.get_license_info()
	var names := licenses.keys()
	names.sort()
	for name in names:
		file.store_string("\n=== " + str(name) + " ===\n" + str(licenses[name]) + "\n")
	file.close()
	print("LICENSE_NOTICES components=", Engine.get_copyright_info().size(), " licenses=", licenses.size())
	quit()
