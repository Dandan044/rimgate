extends SceneTree

const World = preload("res://scripts/sim/world.gd")

func _initialize() -> void:
	call_deferred("_run")

func _make_world():
	return World.new()

func _run() -> void:
	var failures: Array[String] = []
	for path in ["res://tests/test_world.gd", "res://tests/test_units.gd", "res://tests/test_combat.gd", "res://tests/test_presentation.gd"]:
		if not ResourceLoader.exists(path):
			failures.append("Missing required suite: " + path)
			continue
		var script = load(path)
		if script == null or not script.can_instantiate():
			failures.append("Cannot load suite: " + path)
			continue
		var suite = script.new()
		var started := Time.get_ticks_msec()
		var result: Array[String] = suite.run(Callable(self, "_make_world"))
		for failure in result: failures.append(path.get_file() + ": " + failure)
		print("SUITE %s: %d failure(s), %d ms" % [path.get_file(), result.size(), Time.get_ticks_msec() - started])
	if failures.is_empty():
		print("RIMGATE_TESTS_PASSED")
	else:
		for failure in failures: push_error(failure)
		print("RIMGATE_TESTS_FAILED: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
