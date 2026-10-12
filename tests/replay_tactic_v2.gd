extends SceneTree

const World = preload("res://scripts/sim/world.gd")
# Loaded at runtime so the regular suite does not depend on a generated record.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var recording = load("res://scripts/qa/verified_tactic_v2.gd")
	var expected: Dictionary = recording.expected()
	var orders: Array = recording.commands()
	var w = World.new()
	var cursor := 0
	w.start_battle()
	while w.phase == "running":
		while cursor < orders.size() and int(orders[cursor].step) == w.step_index:
			var order: Dictionary = orders[cursor]
			var accepted: Dictionary = w.submit(order.ids, order.kind, order.data.duplicate(true))
			if not accepted.ok:
				push_error("Recorded command rejected at %d: %s" % [cursor, accepted.reason]); quit(1); return
			cursor += 1
		w.step()
	var fingerprint: int = hash(var_to_bytes([w.time_s, w.units, w.buildings, w.supplies, w.projectiles, w.stats, w.rng.state]))
	var passed: bool = w.phase == "won" and w.step_index == 28800 and cursor == orders.size() and fingerprint == int(expected.state_hash)
	print("V2_REPLAY phase=", w.phase, " step=", w.step_index, " commands=", cursor, " hash=", fingerprint, " expected=", expected.state_hash)
	if not passed: push_error("Frozen public-command replay differs from recorded v2 result")
	quit(0 if passed else 1)
