extends SceneTree

# Opt-in rendering fixture. No product balance, positions, or UI are changed.
const Screen = preload("res://scripts/ui/battle_screen.gd")
const State = preload("res://scripts/sim/state.gd")
const Config = preload("res://scripts/sim/battle_config.gd")
const Weapon = preload("res://scripts/sim/weapon_pose.gd")
var screen
var caption: Label
var output_dir := "res://build/v2_evidence"
var failures: Array[String] = []
var evidence: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var logical_positions: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--visual-output="): output_dir = arg.trim_prefix("--visual-output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	screen = Screen.new()
	root.add_child(screen)
	await process_frame
	# Drive the same simulation and render adapters at a controlled observation
	# cadence, so sub-100 ms feedback can be sampled reproducibly.
	screen.set_process(false)
	screen.set_physics_process(false)
	screen.toast_label.hide()
	screen.selected.assign([1])
	screen.camera.position = Vector2(32, 18.5) * Config.GRID
	screen.camera.zoom = Vector2.ONE * 1.15
	screen.camera.force_update_scroll()
	var shooter: Dictionary = screen.world.entity(1)
	shooter.pos = Vector2(29.5, 17.5)
	shooter.prev_pos = shooter.pos
	shooter.goal = shooter.pos
	shooter.posture_mode = 0
	for id in range(2, 7):
		var friendly: Dictionary = screen.world.entity(id)
		friendly.pos = Vector2(23.5 + id * 2, 44.5)
		friendly.prev_pos = friendly.pos
		friendly.goal = friendly.pos
	var target: Dictionary = State.unit(901, 1, Vector2(35.5, 17.5))
	target.hp = 1000.0
	target.max_hp = 1000.0
	target.loaded = 0
	target.reserve = 0
	target["ai_next"] = 1000000.0
	target.ai_hold_until = 1000000.0
	target.posture_mode = 0
	screen.world.units.append(target)
	screen.world.next_wave = Config.WAVE_TIMES.size()
	screen.world.unit_system.setup(screen.world)
	# setup initializes AI bookkeeping for newly added units.
	target.ai_next = 1000000.0
	target.ai_hold_until = 1000000.0
	for unit in screen.world.units: logical_positions[int(unit.id)] = Vector2(unit.pos)
	screen.view.reset_presentation()
	_add_fixture_caption()
	var command: Dictionary = screen.world.submit([1], "attack", {"target_id": 901})
	_check(command.get("ok", false), "Public attack command accepted")
	screen.world.start_battle()
	screen._sync_pause()
	var aim_seen := false
	var fired_seen := false
	var damage_seen := false
	for tick in range(1800):
		_step()
		if not aim_seen and shooter.get("weapon_state", "") == "aiming" and float(shooter.get("aim_fraction", 0)) >= 0.35:
			aim_seen = true
			await _capture("01_aim_cone.png", "AIM / 选中单位正在瞄准", {"unit_id": 1, "aim_fraction": shooter.aim_fraction, "stability": shooter.stability, "weapon_facing": shooter.weapon_facing})
		var fired: Dictionary = _latest_event("weapon_fired", 1)
		if not fired_seen and not fired.is_empty():
			fired_seen = true
			# Sample real animation 35 ms after the real event. Product feedback
			# is unchanged; only the QA observation clock is controlled.
			screen.view.advance_display(0.035)
			screen.view.motion.fraction = 1.0
			var pose: Dictionary = Weapon.rifle(shooter.pos, float(shooter.weapon_facing), int(shooter.posture))
			_check(Vector2(fired.pos).distance_to(Vector2(pose.muzzle)) < 0.0001, "Real projectile origin equals shared rendered muzzle")
			_check(screen.view._recoil(1) > 2.0, "Whole rifle recoil is visible at event sample")
			await _capture("02_muzzle_recoil.png", "FIRE / 真实开火事件 · 枪口与武器后座", {"event": _json_event(fired), "muzzle": _xy(pose.muzzle), "recoil_px": screen.view._recoil(1), "sample_offset_s": 0.035})
		var damage: Dictionary = _latest_event("damage", 901)
		if not damage_seen and not damage.is_empty():
			damage_seen = true
			_check(screen.view._damage_flash(901) > 0.8, "Real projectile damage produces immediate red tint")
			await _capture("03_damage_red_flash.png", "HIT / 真实伤害事件 · 透红与轻微抖动", {"event": _json_event(damage), "flash": screen.view._damage_flash(901), "logical_position": _xy(target.pos)})
		if aim_seen and fired_seen and damage_seen: break
	_check(aim_seen and fired_seen and damage_seen, "All three real combat phases captured within fixture limit")
	_check(_positions_unchanged(), "Rendering recoil and shake never modify authoritative unit positions")
	var report := {
		"fixture": true,
		"purpose": "Controlled actual rendering proof for aiming, firing, and damage feedback; not balance or victory proof.",
		"fixture_changes": ["Friendly 1 at (29.5,17.5), target 901 at (35.5,17.5)", "Other friendlies remain alive outside firing range", "Target HP/max HP 1000, ammunition 0, AI think deferred; scheduled waves disabled", "Normal attack command and world.step generate all combat events", "Display observation cadence controlled and snapshots paused"],
		"checks": checks,
		"evidence": evidence,
		"failures": failures,
		"passed": failures.is_empty()
	}
	var report_path := output_dir.path_join("visual_v2_report.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	else: failures.append("Cannot write visual evidence JSON")
	print("VISUAL_V2_CHECK passed=", failures.is_empty(), " captures=", evidence.size(), " failures=", failures, " report=", ProjectSettings.globalize_path(report_path))
	for player in screen.audio_players: player.stop()
	screen.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _step() -> void:
	screen.world.set_paused(false)
	screen.view.set_running(true)
	screen.world.step(Config.FIXED_DT)
	screen.view.tick(Config.FIXED_DT)
	screen._check_events()
	screen.view.advance_display(Config.FIXED_DT)
	screen.view.motion.fraction = 1.0
	screen._flush_sounds(Config.FIXED_DT)

func _latest_event(kind: String, entity_id: int) -> Dictionary:
	for event in screen.world.events:
		if int(event.step) != int(screen.world.step_index) or event.type != kind: continue
		var holder: int = int(event.get("holder_id", event.get("entity_id", -1)))
		if holder == entity_id: return event
	return {}

func _capture(name: String, title: String, detail: Dictionary) -> void:
	# AudioStreamPlayer2D starts voices on the next physics notification. Let the
	# genuine queued sounds start before exercising the ordinary pause command.
	screen._sync_pause()
	await physics_frame
	await process_frame
	screen.world.set_paused(true)
	screen._sync_pause()
	screen._refresh_hud()
	caption.text = "受控视觉夹具 / CONTROLLED VISUAL FIXTURE\n%s\n固定格位与血量，仅验证表现；不作为难度或平衡证明。" % title
	var before_fx: Array = screen.view.effects.duplicate(true)
	var before_time: float = screen.world.time_s
	var before_visual: float = screen.view.visual_time
	var before_position: Vector2 = screen.view.unit_position(screen.world.entity(1))
	screen.view.advance_display(0.25)
	await create_timer(0.12, true).timeout
	screen.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var destination: String = output_dir.path_join(name)
	var result: Error = image.save_png(ProjectSettings.globalize_path(destination))
	_check(result == OK, "Rendered screenshot saved: " + name)
	_check(screen.world.time_s == before_time and screen.view.visual_time == before_visual and screen.view.effects == before_fx and screen.view.unit_position(screen.world.entity(1)) == before_position, "Pause freezes simulation and feedback: " + name)
	_check(_positions_unchanged(), "Logical unit cells remain fixed: " + name)
	var paused_voices := true
	for index in range(screen.audio_players.size()):
		if screen.audio_players[index].playing and int(screen.voice_priority.get(index, 0)) < 5 and not screen.audio_players[index].stream_paused:
			paused_voices = false
			print("VISUAL_V2_UNPAUSED_VOICE index=", index, " priority=", screen.voice_priority.get(index, 0))
	_check(paused_voices, "Pause freezes active combat voices: " + name)
	detail["fixture"] = true
	detail["image"] = ProjectSettings.globalize_path(destination)
	detail["world_time_s"] = screen.world.time_s
	detail["world_step"] = screen.world.step_index
	evidence.append(detail)
	print("VISUAL_V2_FRAME ", name, " step=", screen.world.step_index)

func _positions_unchanged() -> bool:
	for unit in screen.world.units:
		if not Vector2(unit.pos).is_equal_approx(logical_positions.get(int(unit.id), Vector2.INF)): return false
	return true

func _check(condition: bool, label: String) -> void:
	checks.append({"label": label, "passed": condition})
	if not condition: failures.append(label); push_error(label)

func _add_fixture_caption() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	screen.add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(30, 122)
	panel.size = Vector2(760, 108)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172423ee")
	style.border_color = Color("d9b473")
	style.set_border_width_all(2)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	caption = Label.new()
	caption.add_theme_font_override("font", screen.ui_font)
	caption.add_theme_font_size_override("font_size", 21)
	caption.add_theme_color_override("font_color", Color("f0d8a6"))
	panel.add_child(caption)

func _xy(value: Vector2) -> Array:
	return [value.x, value.y]

func _json_event(event: Dictionary) -> Dictionary:
	var result := event.duplicate(true)
	for key in result:
		if result[key] is Vector2: result[key] = _xy(result[key])
	return result
