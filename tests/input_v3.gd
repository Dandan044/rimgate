extends SceneTree

# Source-side runner shares the exact embedded exported-game input harness.
const Runner = preload("res://scripts/qa/input_v3_check.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
 var runner = Runner.new()
 root.add_child(runner)
 runner.setup()
