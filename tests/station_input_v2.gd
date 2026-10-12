extends SceneTree

# Run with --main-pack against the shipped PCK to exercise its compiled UI.
const Screen = preload("res://scripts/ui/battle_screen.gd")
const State = preload("res://scripts/sim/state.gd")
var screen
var checks: Array[Dictionary] = []
var report_path := ""

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks.append({"check": label, "passed": value})
	print("STATION_INPUT ", label, " = ", value)

func _click(point: Vector2, button: MouseButton) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.global_position = point
		event.button_index = button; event.pressed = pressed
		root.push_input(event, true)
	await process_frame
	await process_frame

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new(); event.keycode = code; event.pressed = pressed
		root.push_input(event, true)
	await process_frame

func _point(position: Vector2) -> Vector2:
	return root.get_canvas_transform() * (position * 64.0)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	screen = Screen.new(); root.add_child(screen)
	await process_frame
	screen.camera.position = Vector2(26, 23) * 64.0
	screen.camera.zoom = Vector2.ONE * 0.5; screen.camera.force_update_scroll()
	var station: Dictionary = screen.world.stations()[0]
	var enemy: Dictionary = State.unit(901, 1, Vector2(20.5, 17.5))
	screen.world.units.append(enemy); screen.world.unit_system._ensure_unit(enemy)
	enemy.ai_next = INF
	await _key(KEY_1)
	await _click(_point(station.pos), MOUSE_BUTTON_RIGHT)
	_check(screen.popup.visible, "actual right click opens station menu")
	screen.popup.set_focused_item(0)
	await _key(KEY_ENTER)
	_check(screen.world.projected_crew(int(station.id)) == [1], "menu input reserves operator")
	await _click(_point(station.pos), MOUSE_BUTTON_LEFT)
	_check(screen.selected_building == int(station.id) and screen.selected.is_empty(), "actual left click selects station without pawn selection")
	await _click(_point(enemy.pos), MOUSE_BUTTON_RIGHT)
	_check(not screen.world.pending_orders.is_empty() and screen.world.pending_orders.back().kind == "station_attack", "actual right click on enemy queues station attack")
	await _click(screen.start_button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	await create_timer(0.15, true).timeout
	_check(int(station.target_id) == int(enemy.id) and int(screen.world.entity(1).station_id) == int(station.id), "running command sets station target and preserves operator")
	var passed := true
	for check in checks: passed = passed and bool(check.passed)
	var result := {"passed": passed, "checks": checks, "fixture": "Only an enemy target is inserted at a visible fixed cell for UI routing; this is not balance or victory evidence.", "method": "Actual Viewport mouse and keyboard events; UI/simulation loaded from the release PCK via --main-pack."}
	if report_path != "":
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t")); file.close()
	screen.queue_free(); await process_frame
	quit(0 if passed else 1)
