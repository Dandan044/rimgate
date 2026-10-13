extends SceneTree
const World = preload("res://scripts/sim/world.gd")
func make_world(): return World.new()
func _initialize():
 var suite = load("res://tests/test_units.gd").new()
 var errors: Array[String] = suite.run(Callable(self, "make_world"))
 for problem in errors: push_error(problem)
 print("V3_UNITS_FAILURES=", errors.size())
 quit(0 if errors.is_empty() else 1)
