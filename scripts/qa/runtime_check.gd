extends Node

# Opt-in checks run against the same scene/export as normal play.
const Config = preload("res://scripts/sim/battle_config.gd")
var screen
var mode := ""
var started_usec := 0
var previous_usec := 0
var duration := 1800.0
var report_path := ""
var samples: Array[float] = []
var memory_samples: Array[Dictionary] = []
var restarts := 0
var next_restart := 350.0
var next_memory := 60.0
var next_health := 1.0
var ammo_baseline := 0
var progress_watch: Dictionary = {}
var peak_wave := 0
var failures: Array[String] = []
var peak_projectiles := 0
var peak_nodes := 0
var benchmark_ready := false
var display_elapsed := 0.0
var display_orders: Dictionary = {}
var offline_capture := false
var interaction_checks: Array[Dictionary] = []
var interaction_fixtures: Array[String] = []
var finished := false
var scenario_details: Dictionary = {}

func setup(target) -> void:
	screen = target
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-mode="): mode = arg.trim_prefix("--qa-mode=")
		elif arg.begins_with("--qa-duration="): duration = float(arg.trim_prefix("--qa-duration="))
		elif arg.begins_with("--qa-report="): report_path = arg.trim_prefix("--qa-report=")
		elif arg == "--qa-offline-movie": offline_capture = true
	started_usec = Time.get_ticks_usec(); previous_usec = started_usec
	if mode == "benchmark":
		duration = 65.0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		_prepare_stress()
	elif mode == "soak":
		screen.apply_review_orders()
		ammo_baseline = _ammo_total()
	elif mode == "input":
		call_deferred("_input_check")
	elif mode == "input_v3":
		# Release templates forbid external --script/--main-pack overrides.
		# Keep the actual Viewport input harness opt-in inside this tested PCK.
		var runner = load("res://scripts/qa/input_v3_check.gd").new()
		get_tree().root.add_child(runner)
		runner.setup(screen)
	elif mode == "interaction":
		duration = 180.0
		var runner = load("res://scripts/qa/interaction_check.gd").new()
		add_child(runner)
		runner.setup(self, screen)
	elif mode == "victory":
		duration = 540.0
		var runner = load("res://scripts/qa/victory_check.gd").new()
		add_child(runner)
		runner.setup(self, screen)
	elif mode in ["normal", "motion", "short"]:
		duration = 150.0 if mode == "short" else (35.0 if mode == "normal" else 26.0)
		_prepare_display_review()
	else:
		failures.append("Unknown QA mode: " + mode); _finish()
	print("QA_STARTED mode=", mode, " duration=", duration)

func _prepare_display_review() -> void:
	screen.apply_review_orders()
	# Skip the quiet initial countdown using the unchanged real simulation.
	for _i in range(29 * 60): screen.world.step()
	screen.last_event_serial = int(screen.world.events.back().serial)
	screen.view.reset_presentation()
	screen.view.set_running(true)
	screen.camera.zoom = Vector2.ONE * 0.35
	screen.camera.position = Vector2(36, 15) * Config.GRID
	screen.camera.force_update_scroll()
	screen.selected.assign([5, 6])
	screen._refresh_hud()

func _review_send(ids: Array, kind: String, data: Dictionary) -> void:
	var result: Dictionary = screen.world.submit(ids, kind, data)
	if not result.ok: failures.append("Motion review command rejected: " + kind + " / " + String(result.reason))

func _display_review(elapsed: float) -> void:
	if elapsed >= 3.0 and not display_orders.has("move"):
		display_orders["move"] = true
		_review_send([5], "move", {"position": Vector2(29.5, 22.5)})
		_review_send([6], "posture", {"value": 1})
		_review_send([6], "move", {"position": Vector2(34.5, 23.5)})
	if elapsed >= 9.0 and not display_orders.has("turn"):
		display_orders["turn"] = true
		_review_send([5], "move", {"position": Vector2(25.5, 23.5)})
		_review_send([6], "posture", {"value": 2})
		_review_send([6], "move", {"position": Vector2(36.5, 22.5)})
	if elapsed >= 5.0 and not display_orders.has("front"):
		display_orders["front"] = true
		screen.camera.zoom = Vector2.ONE * 0.68
		screen.camera.position = Vector2(28, 24) * Config.GRID
		screen.camera.force_update_scroll()
	if elapsed >= 14.0 and not display_orders.has("pause"):
		display_orders["pause"] = true
		screen.world.set_paused(true); screen._sync_pause()
		screen._refresh_hud()
		display_orders["paused_time"] = screen.world.time_s
	if elapsed >= 16.0 and not display_orders.has("resume"):
		display_orders["resume"] = true
		if screen.world.time_s != float(display_orders.paused_time): failures.append("Motion recording advanced while paused")
		screen.world.set_paused(false); screen._sync_pause()
		screen._refresh_hud()
	if elapsed >= 18.0 and not display_orders.has("close"):
		display_orders["close"] = true
		screen.camera.zoom = Vector2.ONE * 0.68
		screen.camera.position = Vector2(28, 26) * Config.GRID
		screen.camera.force_update_scroll()

func _prepare_stress() -> void:
	var w = screen.world
	w.reset(); w.spawn_wave(0); w.spawn_wave(1); w.spawn_wave(2); w.next_wave = 3
	screen.apply_review_orders()
	benchmark_ready = true
	_fill_stress()

func _fill_stress() -> void:
	var w = screen.world
	# A controlled performance fixture; these HP changes are never a victory test.
	for u in w.units:
		u.hp = u.max_hp; u.bleed_rate = 0.0; u.dead = false; u.conscious = true
	for b in w.buildings: b.hp = b.max_hp
	var weapon: Dictionary = Config.rifle()
	weapon.damage = 0.0; weapon.range = 40.0
	while w.projectiles.size() < 256:
		var shooter: Dictionary = w.units[w.projectiles.size() % w.units.size()]
		var target: Dictionary = w.units[(w.projectiles.size() + 7) % w.units.size()]
		w.combat_system.spawn_direct_projectile(w, shooter, target, weapon, 1.0)
	if w.projectiles.size() > 256: w.projectiles.resize(256)

func _physics_process(_dt: float) -> void:
	if screen == null: return
	if mode == "benchmark" and benchmark_ready: _fill_stress()

func _process(_dt: float) -> void:
	if screen == null or mode in ["input", "input_v3"]: return
	var now := Time.get_ticks_usec()
	var elapsed := (now - started_usec) / 1000000.0
	if mode == "interaction":
		if elapsed >= duration:
			failures.append("Interaction check timed out before completing")
			_finish()
		return
	if mode == "motion":
		display_elapsed += _dt
		elapsed = display_elapsed
	if mode in ["benchmark", "normal"] and elapsed >= 5.0: samples.append((now - previous_usec) / 1000.0)
	if mode in ["motion", "short"]: _display_review(elapsed)
	previous_usec = now
	peak_projectiles = maxi(peak_projectiles, screen.world.projectiles.size())
	peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	if mode == "soak":
		peak_wave = maxi(peak_wave, int(screen.world.next_wave))
		if elapsed >= next_restart or screen.world.phase in ["won", "lost"]:
			screen._restart(); screen.apply_review_orders(); restarts += 1
			progress_watch.clear()
			if elapsed >= next_restart: next_restart += 350.0
		if elapsed >= next_health:
			next_health = elapsed + 1.0
			_validate_reservations()
			_validate_progress(elapsed)
			var enemy = preload("res://scripts/sim/state.gd").unit(-1, 1, Vector2.ZERO)
			var expected: int = ammo_baseline + int(screen.world.stats.enemy_spawned) * (int(enemy.loaded) + int(enemy.reserve))
			if _ammo_total() != expected: _fail_once("Whole-scene ammunition total changed: remaining + fired + destroyed")
		if elapsed >= next_memory:
			memory_samples.append({"seconds": elapsed, "memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "voices": screen.audio_players.size(), "projectiles": screen.world.projectiles.size()})
			next_memory += 60.0
	if elapsed >= duration: _finish()

func _validate_reservations() -> void:
	var w = screen.world
	var cells: Dictionary = {}
	for unit in w.units:
		if unit.dead or not unit.conscious or unit.hp <= 0 or unit.carrier_id >= 0: continue
		var cell := Vector2i(Vector2(unit.pos).floor())
		if cells.has(cell): _fail_once("Active units %d/%d share cell %s" % [cells[cell], unit.id, cell])
		cells[cell] = int(unit.id)
	for b in w.stations():
		if b.crew.size() > b.capacity: _fail_once("Station overbooked")
		for id in b.crew:
			var u: Dictionary = w.entity(int(id))
			if u.is_empty() or u.station_id != b.id: _fail_once("Orphaned crew reservation")
	for u in w.units:
		if int(u.station_id) >= 0 and not w.entity(int(u.station_id)).crew.has(int(u.id)): _fail_once("Unit station missing reverse crew reservation")
	for box in w.supplies:
		if box.carried_by >= 0 and box.reserved_by != box.carried_by: _fail_once("Orphaned supply reservation")
		if int(box.reserved_by) >= 0:
			var carrier: Dictionary = w.entity(int(box.reserved_by))
			if carrier.is_empty() or int(carrier.crate_id) != int(box.id): _fail_once("Supply missing reverse carrier reservation")
	for slot in w.medical_reservations:
		var medic: Dictionary = w.entity(int(w.medical_reservations[slot]))
		if medic.is_empty() or int(medic.medical_slot) != int(slot): _fail_once("Orphaned medical slot")
	for projectile in w.projectiles:
		if float(projectile.get("age", 0.0)) > 5.0: _fail_once("Projectile survived beyond configured maximum flight lifetime")
	if screen.audio_players.size() != 24: _fail_once("Audio pool grew")
	if screen.view.effects.size() > 160 or w.events.size() > 256: _fail_once("Effects/events exceeded bounds")

func _ammo_total() -> int:
	var w = screen.world
	var total: int = int(w.stats.rifle_shots) + int(w.stats.mg_shots) + int(w.stats.mortar_shots) + int(w.stats.ammo_destroyed)
	for u in w.units: total += int(u.loaded) + int(u.reserve)
	for b in w.buildings: total += int(b.loaded) + int(b.ammo)
	for box in w.supplies:
		if not box.delivered: total += int(box.amount)
	# Reload reservations refer to rounds still in reserve/stock, not extra rounds.
	return total

func _validate_progress(elapsed: float) -> void:
	for u in screen.world.units:
		var id: int = int(u.id)
		if u.dead or not u.conscious or int(u.carrier_id) >= 0 or u.path.is_empty() or bool(u.get("cower", false)) or float(u.posture_timer) > 0.0:
			progress_watch.erase(id); continue
		if not progress_watch.has(id) or progress_watch[id].pos.distance_to(u.pos) > 0.15 or progress_watch[id].goal.distance_to(u.goal) > 0.15:
			progress_watch[id] = {"pos": Vector2(u.pos), "goal": Vector2(u.goal), "since": elapsed}
		elif elapsed - float(progress_watch[id].since) > 10.0:
			_fail_once("Unit %d retained a movement path without progress for ten seconds" % id)

func _fail_once(message: String) -> void:
	if not failures.has(message): failures.append(message)

func _click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = point; screen.get_viewport().push_input(motion, true)
	var down := InputEventMouseButton.new(); down.position = point; down.button_index = button; down.pressed = true; screen.get_viewport().push_input(down, true)
	var up := InputEventMouseButton.new(); up.position = point; up.button_index = button; up.pressed = false; screen.get_viewport().push_input(up, true)

func _input_check() -> void:
	await get_tree().process_frame
	var point: Vector2 = screen.get_viewport().get_canvas_transform() * (screen.world.entity(1).pos * Config.GRID)
	_click(point)
	await get_tree().process_frame
	if not screen.selected.has(1): failures.append("Mouse click failed to select friendly")
	var before: Vector2 = screen.world.entity(1).pos
	var destination := Vector2(25.5, 32.5)
	_click(screen.get_viewport().get_canvas_transform() * (destination * Config.GRID), MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	if screen.world.pending_orders.is_empty(): failures.append("Right-click failed to submit move while paused")
	if screen.world.entity(1).pos != before: failures.append("Paused UI command moved unit")
	screen._start()
	await get_tree().create_timer(1.0, true).timeout
	if screen.world.entity(1).pos == before: failures.append("Start did not execute pending movement")
	var key := InputEventKey.new(); key.keycode = KEY_SPACE; key.pressed = true; Input.parse_input_event(key)
	await get_tree().process_frame
	if screen.world.phase != "paused": failures.append("Space did not pause")
	var paused_time: float = screen.world.time_s
	await get_tree().create_timer(0.3, true).timeout
	if screen.world.time_s != paused_time: failures.append("Paused UI continued simulation")
	screen._restart()
	if screen.world.phase != "preparing" or screen.world.time_s != 0.0: failures.append("Restart failed")
	_finish()

func _finish() -> void:
	if finished: return
	finished = true
	set_process(false); set_physics_process(false)
	var elapsed := (Time.get_ticks_usec() - started_usec) / 1000000.0
	samples.sort()
	var sum_ms := 0.0
	for value in samples: sum_ms += value
	var average := sum_ms / maxf(1.0, samples.size())
	var p95 := samples[mini(samples.size() - 1, int(samples.size() * 0.95))] if not samples.is_empty() else 0.0
	if mode in ["benchmark", "normal"] and (average > 1000.0 / 60.0 or p95 > 33.3): failures.append("Frame-time target missed")
	if mode == "soak" and (elapsed < 1800.0 or restarts < 5): failures.append("Required soak duration/restarts not reached")
	var static_memory_available: bool = not memory_samples.is_empty() and float(memory_samples[0].memory_bytes) > 0
	if mode == "soak" and static_memory_available and memory_samples.size() >= 10:
		# Compare equally sized windows after warm-up; allow allocator/UI cache noise.
		var early := 0.0; var late := 0.0
		for index in range(5):
			early += float(memory_samples[index + 4].memory_bytes) / 5.0
			late += float(memory_samples[memory_samples.size() - 5 + index].memory_bytes) / 5.0
		if late - early > maxf(8 * 1024 * 1024, early * 0.25): _fail_once("Static memory grew beyond warm-up allowance")
	var result := {"mode": mode, "elapsed_seconds": elapsed, "frames": samples.size(), "mean_ms": average, "average_fps": 1000.0 / average if average > 0 else 0.0, "p95_ms": p95, "restarts": restarts, "peak_projectiles": peak_projectiles, "peak_nodes": peak_nodes, "memory_samples": memory_samples, "cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(), "os": OS.get_name(), "logical_resolution": str(screen.get_viewport().get_visible_rect().size), "window_resolution": str(screen.get_window().size), "render_resolution": str(screen.get_viewport().get_texture().get_size()), "engine": Engine.get_version_info().string, "failures": failures}
	var actual_pck: String = OS.get_executable_path().get_basename() + ".pck"
	if FileAccess.file_exists(actual_pck):
		result["pck_sha256"] = FileAccess.get_sha256(actual_pck).to_upper()
		result["executable"] = OS.get_executable_path()
		result["pck_path"] = actual_pck
	result["version"] = str(ProjectSettings.get_setting("application/config/version", "unknown"))
	if mode == "motion":
		result["recorded_seconds"] = display_elapsed
		result["offline_movie_capture"] = offline_capture
		result["simulation_seconds"] = screen.world.time_s
	if mode == "interaction":
		result["input_method"] = "automated Viewport input events in the rendered game; not manual GUI testing"
		result["checks"] = interaction_checks
		result["controlled_fixtures"] = interaction_fixtures
	if mode == "soak":
		result["peak_wave"] = peak_wave
		result["static_memory_available"] = static_memory_available
		result["checks"] = ["one-second bidirectional crew/supply/medical reservations", "one-second whole-scene ammo conservation", "movement paths with no progress for ten seconds", "projectile flight lifetime", "bounded voices/effects/events"]
		if static_memory_available:
			result["checks"].append("static memory: last five samples versus samples 5-9, allowance max(8MiB,25%)")
		else:
			result["memory_note"] = "Release engine returned zero for static memory; use tools/soak.ps1 process memory evidence. Zero is not evidence of zero allocation."
	if mode == "victory":
		result["scenario"] = scenario_details
		if not bool(scenario_details.get("completed", false)): _fail_once("Real-time victory scenario did not complete")
	if report_path != "":
		DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(result, "\t")); file.close()
	print("QA_RESULT ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
