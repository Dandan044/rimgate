extends SceneTree

const World = preload("res://scripts/sim/world.gd")
const Suite = preload("res://tests/test_combat.gd")

func _initialize() -> void:
	call_deferred("_run")

func _make_world():
	return World.new()

func _run() -> void:
	var failures: Array[String] = Suite.new().run(Callable(self,"_make_world"))
	for failure in failures: push_error(failure)
	print("RIMGATE_COMBAT_V3_PASSED" if failures.is_empty() else "RIMGATE_COMBAT_V3_FAILED: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
