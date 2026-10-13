extends SceneTree
const World = preload("res://scripts/sim/world.gd")
func make_world(): return World.new()
func _initialize():
 var suite = load("res://tests/test_units.gd").new()
 print("START_FOCUSED")
 suite._test_v3_pressure_and_formation(Callable(self,"make_world"))
 for problem in suite.failures: push_error(problem)
 print("FOCUSED_FAILURES=",suite.failures.size())
 quit(0 if suite.failures.is_empty() else 1)
