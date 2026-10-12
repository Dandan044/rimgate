extends Node

# Exercises the real scene's input/GUI path. Commands are never submitted directly
# by this runner. The separate medical fixture is declared in the report and is
# not evidence of combat balance or victory.
const C = preload("res://scripts/sim/battle_config.gd")
var qa
var screen

func setup(owner_check, target) -> void:
	qa = owner_check
	screen = target
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _check(condition: bool, label: String) -> bool:
	qa.interaction_checks.append({"check": label, "passed": condition, "simulation_seconds": screen.world.time_s})
	print("INTERACTION_CHECK ", label, " = ", condition)
	if not condition: qa.failures.append(label)
	return condition

func _key(code: Key, shift: bool = false, viewport: Viewport = null) -> void:
	var target: Viewport = screen.get_viewport() if viewport == null else viewport
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code
		event.shift_pressed = shift; event.pressed = pressed
		target.push_input(event, true)

func _mouse(point: Vector2, button: MouseButton, pressed: bool, shift: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.position = point; event.global_position = point
	event.button_index = button; event.pressed = pressed; event.shift_pressed = shift
	screen.get_viewport().push_input(event, true)

func _move_mouse(point: Vector2, relative: Vector2 = Vector2.ZERO, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point; event.global_position = point
	event.relative = relative; event.button_mask = mask
	screen.get_viewport().push_input(event, true)

func _click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_move_mouse(point)
	_mouse(point, button, true)
	_mouse(point, button, false)

func _grid(point: Vector2) -> Vector2:
	return screen.get_viewport().get_canvas_transform() * (point * C.GRID)

func _button(button: Button) -> void:
	_click(button.get_global_rect().get_center())

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null: return found
	return null

func _popup_action(kind: String) -> bool:
	await get_tree().process_frame
	if not _check(screen.popup.visible, "context menu opens for " + kind): return false
	var item := -1
	for index in range(screen.popup.item_count):
		var id: int = screen.popup.get_item_id(index)
		if screen.popup_actions[id].kind == kind: item = index; break
	if not _check(item >= 0 and not screen.popup.is_item_disabled(item), "context action available: " + kind): return false
	screen.popup.set_focused_item(item)
	_key(KEY_ENTER)
	await get_tree().process_frame
	return _check(not screen.popup.visible, "keyboard activates context action: " + kind)

func _wait(condition: Callable, wall_seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(wall_seconds * 1000)
	while Time.get_ticks_msec() < end:
		if qa.finished: return false
		if condition.call(): return true
		await get_tree().process_frame
	return bool(condition.call())

func _frozen_signature() -> int:
	return hash(var_to_bytes([screen.world.time_s, screen.world.step_index,
		screen.world.units, screen.world.buildings, screen.world.supplies,
		screen.world.projectiles, screen.world.stats, screen.world.rng.state,
		screen.view.visual_time, screen.view.motion.fraction, screen.view.effects]))

func _end() -> void:
	qa.call_deferred("_finish")

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_check(screen.world.phase == "preparing", "initial deployment is paused")
	_check(screen.popup.is_embedded(), "context menu shares game viewport under window scaling")
	var first: Vector2 = _grid(screen.world.entity(1).pos)
	var last: Vector2 = _grid(screen.world.entity(6).pos)
	_mouse(first - Vector2(25, 25), MOUSE_BUTTON_LEFT, true)
	_move_mouse(last + Vector2(25, 25), last - first + Vector2(50, 50), MOUSE_BUTTON_MASK_LEFT)
	_mouse(last + Vector2(25, 25), MOUSE_BUTTON_LEFT, false)
	_check(screen.selected.size() == 6, "mouse drag selects six defenders")
	_key(KEY_1); _key(KEY_2, true)
	_check(screen.selected == [1, 2], "number keys and Shift add to selection")

	var stations: Array[Dictionary] = screen.world.stations()
	_key(KEY_1)
	_click(_grid(stations[0].pos), MOUSE_BUTTON_RIGHT)
	if not await _popup_action("operate"): _end(); return
	_check(screen.world.projected_crew(stations[0].id) == [1], "paused MG order reserves one slot without teleporting")
	_key(KEY_2)
	_click(_grid(stations[0].pos), MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	_check(screen.popup.is_item_disabled(0), "full MG has disabled operate action")
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	_click(_grid(stations[1].pos), MOUSE_BUTTON_RIGHT)
	if not await _popup_action("operate"): _end(); return
	_key(KEY_3); _key(KEY_4, true)
	_click(_grid(stations[2].pos), MOUSE_BUTTON_RIGHT)
	if not await _popup_action("operate"): _end(); return
	_check(screen.world.projected_crew(stations[2].id) == [3, 4], "two mortar crew reserved through context menu")
	_key(KEY_5)
	_click(_grid(stations[0].pos), MOUSE_BUTTON_RIGHT)
	if not await _popup_action("resupply"): _end(); return
	_check(screen.world.entity(5).crate_id < 0 and screen.world.pending_orders.size() == 4, "supply order queues without acting during preparation")

	# Pan through real mouse input so the prospective bombardment point is visible.
	var pan_start: Vector2 = screen.camera.position
	_mouse(Vector2(600, 400), MOUSE_BUTTON_MIDDLE, true)
	_move_mouse(Vector2(600, 560), Vector2(0, 160), MOUSE_BUTTON_MASK_MIDDLE)
	_mouse(Vector2(600, 560), MOUSE_BUTTON_MIDDLE, false)
	await get_tree().process_frame
	_check(screen.camera.position != pan_start, "middle drag pans while deployment is paused")
	_key(KEY_3); _key(KEY_F)
	_check(screen.aim_station == stations[2].id, "F enters bombardment using projected crew")
	_click(_grid(Vector2(31.5, 28.5)), MOUSE_BUTTON_RIGHT)
	_check(screen.aim_station < 0 and screen.world.pending_orders.back().kind == "move", "new right click cancels bombardment and immediately queues movement")
	# The replacement movement intentionally releases unit 3's projected post.
	# Reassign it through the same GUI before testing a fire subcommand.
	_click(_grid(stations[2].pos), MOUSE_BUTTON_RIGHT)
	if not await _popup_action("operate"): _end(); return
	_key(KEY_F)
	var before_orders: int = screen.world.pending_orders.size()
	_click(_grid(stations[2].pos))
	_check(screen.aim_station >= 0 and screen.world.pending_orders.size() == before_orders, "too-close bombardment is rejected with aim retained")
	_click(_grid(Vector2(32.5, 14.5)))
	_check(screen.aim_station < 0 and screen.world.pending_orders.back().kind == "fire", "valid bombardment click queues a station subcommand")
	_check(screen.world.projected_crew(stations[2].id) == [3, 4], "bombardment preserves both reserved operators")
	_button(screen.start_button)
	if not _check(screen.world.phase == "running", "start button runs simulation"): _end(); return
	var supply_ready: bool = await _wait(func(): return int(stations[0].ammo) >= 200 and int(screen.world.stats.mortar_shots) >= 1, 27)
	_check(supply_ready, "crew walk to posts, mortar fires, and carrier delivers 200 rounds in real time")

	_key(KEY_SPACE)
	await get_tree().process_frame
	if not _check(screen.world.phase == "paused", "Space pauses after GUI input"): _end(); return
	var frozen: int = _frozen_signature()
	var started := Time.get_ticks_msec()
	await get_tree().create_timer(10.0, true).timeout
	_check(_frozen_signature() == frozen and Time.get_ticks_msec() - started >= 9990, "ten real seconds preserve all combat, RNG, and presentation state")
	var zoom: float = screen.camera.zoom.x
	_click(Vector2(700, 380), MOUSE_BUTTON_WHEEL_UP)
	await get_tree().process_frame
	_check(screen.camera.zoom.x > zoom and _frozen_signature() == frozen, "wheel zoom works during pause without advancing state")
	_key(KEY_6)
	var previous: Vector2 = screen.world.entity(6).pos
	var destination: Vector2 = _grid(Vector2(35.5, 32.5))
	_check(not screen._over_hud(destination), "paused move destination is visible outside HUD")
	_click(destination, MOUSE_BUTTON_RIGHT)
	_check(screen.world.entity(6).pos == previous and not screen.world.pending_orders.is_empty(), "paused right-click movement queues without moving")
	_key(KEY_SPACE)
	var moved: bool = await _wait(func(): return screen.world.entity(6).pos.distance_to(previous) > 0.2, 2)
	_check(moved, "resume executes movement without a turn boundary")
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check(screen.pause_overlay.visible and screen.world.phase == "paused", "Escape opens paused command menu")
	_button(_find_button(screen.pause_overlay, "重新部署"))
	await get_tree().process_frame
	_check(screen.world.phase == "preparing" and screen.world.pending_orders.is_empty(), "restart button clears orders and reservations")

	# This isolated medical GUI fixture is separate from the unmodified combat above.
	qa.interaction_fixtures.append("Medical GUI case only: unit 6 begins unconscious at 20 HP with 0.1 HP/s bleeding. No spawned enemy, forced hit, or altered combat statistics is used as victory evidence.")
	var patient: Dictionary = screen.world.entity(6)
	patient.hp = 20.0; patient.conscious = false; patient.bleed_rate = 0.1
	screen.view.reset_presentation()
	_key(KEY_5)
	_click(_grid(patient.pos), MOUSE_BUTTON_RIGHT)
	if not await _popup_action("rescue"): _end(); return
	_button(screen.start_button)
	var carrying: bool = await _wait(func(): return int(patient.carrier_id) == 5, 5)
	_check(carrying, "rescue command approaches and picks up patient")
	var carried_hp: float = patient.hp
	await get_tree().create_timer(0.6, true).timeout
	_check(patient.hp < carried_hp and int(patient.carrier_id) == 5, "carried patient keeps bleeding while medic walks")
	var treated: bool = await _wait(func(): return float(patient.bleed_rate) == 0.0, 24)
	_check(treated and C.MEDICAL_RECT.has_point(patient.pos) and int(patient.carrier_id) < 0, "patient reaches medical zone and is treated after placement")
	_check(int(screen.world.entity(5).bandages) == 1 and float(patient.hp) < 20.0 and not patient.conscious, "treatment consumes one bandage and does not grant instant HP or awakening")
	_check(screen.world.medical_reservations.is_empty() and int(patient.get("rescue_owner", -1)) < 0, "finished rescue releases medical and patient reservations")
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	_button(_find_button(screen.pause_overlay, "重新部署"))
	await get_tree().process_frame
	_check(screen.world.time_s == 0.0 and screen.world.projectiles.is_empty() and screen.world.medical_reservations.is_empty(), "second GUI restart resets medical and projectile state")
	_end()
