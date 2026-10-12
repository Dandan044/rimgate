extends Node

# No fast-forward or state overrides: the real screen advances all 28,800 steps.
# This automated commander uses the same public commands as normal play.
const Recording = preload("res://scripts/qa/verified_tactic_v2.gd")
const C = preload("res://scripts/sim/battle_config.gd")
var qa
var screen
var orders: Array = []
var cursor := 0
var ended := false
var last_serial := 0
var last_minute := -1
var allied_hits := 0
var allied_damage := 0.0

func setup(owner_check, target) -> void:
	qa = owner_check; screen = target
	process_mode = Node.PROCESS_MODE_ALWAYS
	orders = Recording.commands()
	get_tree().physics_frame.connect(_feed_orders)
	screen.camera.zoom = Vector2.ONE * 0.24
	screen.camera.position = Vector2(32, 24) * C.GRID
	screen.selected.assign([1, 2, 3, 4, 5, 6])
	screen.world.start_battle()
	screen._sync_pause()
	screen._refresh_hud()
	qa.scenario_details = {"completed": false, "method": "fixed public commands in the real-time Windows scene; no state overrides, fast-forward or manual input claim", "expected": Recording.expected()}

func _feed_orders() -> void:
	if ended or screen.world.phase != "running": return
	while cursor < orders.size() and int(orders[cursor].step) <= screen.world.step_index:
		var order: Dictionary = orders[cursor]
		if int(order.step) != screen.world.step_index: qa._fail_once("Victory recording missed an exact command step")
		var accepted: Dictionary = screen.world.submit(order.ids, order.kind, order.data.duplicate(true))
		if not accepted.ok: qa._fail_once("Victory command rejected: " + str(cursor) + " / " + String(accepted.reason))
		cursor += 1

func _process(_delta: float) -> void:
	if ended: return
	for event in screen.world.events:
		if int(event.serial) <= last_serial: continue
		last_serial = int(event.serial)
		var victim: Dictionary = screen.world.entity(int(event.get("entity_id", -1)))
		if event.type == "damage" and int(event.get("team", -1)) == 0 and int(event.get("target_team", -1)) == 0 and victim.has("team"):
			allied_hits += 1; allied_damage += float(event.amount)
	var minute := int(screen.world.time_s / 60.0)
	if minute != last_minute:
		last_minute = minute
		print("VICTORY_PROGRESS minute=", minute, " core=", screen.world.core().hp, " commands=", cursor)
	if screen.world.phase in ["won", "lost"]:
		ended = true
		get_tree().physics_frame.disconnect(_feed_orders)
		call_deferred("_verify_result")

func _check(condition: bool, label: String) -> void:
	print("VICTORY_CHECK ", label, " = ", condition)
	if not condition: qa._fail_once(label)

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null: return found
	return null

func _verify_result() -> void:
	var w = screen.world
	var expected: Dictionary = Recording.expected()
	var alive := 0; var awake := 0; var enemies := 0
	for u in w.units:
		if u.team == 0:
			if not u.dead: alive += 1
			if not u.dead and u.conscious: awake += 1
		elif not u.dead: enemies += 1
	var fingerprint: int = hash(var_to_bytes([w.time_s, w.units, w.buildings, w.supplies, w.projectiles, w.stats, w.rng.state]))
	qa.scenario_details["actual"] = {"phase": w.phase, "time": w.time_s, "step": w.step_index, "core_hp": w.core().hp, "alive": alive, "awake": awake, "living_enemies": enemies, "commands": cursor, "stats": w.stats.duplicate(true), "snapshot_hash": fingerprint, "allied_friendly_fire_hits": allied_hits, "allied_friendly_fire_hp": allied_damage, "medical_stock": w.medical_stock}
	qa.scenario_details["hash_scope"] = "time, units, buildings, supplies, projectiles, stats, RNG state; excludes events, order history, medical stock/reservations, phase and view"
	_check(w.phase == "won" and w.step_index == 28800 and absf(w.time_s - 480.0) < 0.00001, "real scene wins at step 28,800")
	_check(cursor == orders.size() and fingerprint == int(expected.state_hash), "all recorded v0.2 commands reproduce the gameplay snapshot")
	_check(w.core().hp == expected.core_hp and alive == expected.alive and awake == expected.awake and enemies == expected.living_enemies, "core and personnel match verified result")
	_check(w.stats.rifle_shots == expected.rifle_shots and w.stats.mg_shots == expected.mg_shots and w.stats.mortar_shots == expected.mortar_shots, "ammunition consumption matches recorded result")
	_check(allied_hits == expected.ally_friendly_fire_hits and absf(allied_damage - expected.ally_friendly_fire_hp) < 0.001, "actual allied friendly fire is reported separately")
	qa._validate_reservations()
	await get_tree().create_timer(0.2, true).timeout
	_check(screen.result_overlay.visible and screen.result_label.text.contains("守卫成功"), "victory result page is visible in the actual window")
	_check(screen.timer_label.text == "08:00 / 08:00" and screen.result_label.text.contains("守卫时间  08:00"), "actual result and HUD both display the complete eight minutes")
	var capture_path: String = qa.report_path.get_base_dir().path_join("victory_result.png")
	await screen.capture_review_frame(capture_path)
	qa.scenario_details["result_capture"] = capture_path
	await get_tree().create_timer(1.0, true).timeout
	_check(w.step_index == 28800 and hash(var_to_bytes([w.time_s, w.units, w.buildings, w.supplies, w.projectiles, w.stats, w.rng.state])) == fingerprint, "victory state stays frozen before restart")
	var restart := _find_button(screen.result_overlay, "重新部署")
	_check(restart != null, "result page provides a restart button")
	if restart != null:
		var point := restart.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new(); motion.position = point
		screen.get_viewport().push_input(motion, true)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
			screen.get_viewport().push_input(event, true)
		await get_tree().process_frame
		_check(w.phase == "preparing" and w.step_index == 0 and w.projectiles.is_empty() and w.pending_orders.is_empty() and w.medical_reservations.is_empty() and not screen.result_overlay.visible, "result-page mouse click resets battle and returns to deployment")
	qa.scenario_details["completed"] = true
	qa.call_deferred("_finish")
