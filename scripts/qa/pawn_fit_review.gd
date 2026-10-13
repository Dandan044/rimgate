extends Node

# Opt-in visual fixture. Real battle renderer/commands/projectiles, controlled
# positions and non-firing durable target; never a balance/performance claim.
const State = preload("res://scripts/sim/state.gd")
const Config = preload("res://scripts/sim/battle_config.gd")
var screen
var elapsed := 0.0
var issued: Dictionary = {}
var failures: Array[String] = []
var shots_by_pose: Dictionary = {}
var seen_shots: Dictionary = {}
var label: Label
var report_path := "res://build/pawn_art_evidence/fit-report.json"

func setup(target) -> void:
	screen = target
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pawn-art-report="): report_path = argument.trim_prefix("--pawn-art-report=")
	for unit in screen.world.units:
		unit.pos = Vector2(20.5 + int(unit.id) * 2, 44.5)
		unit.prev_pos = unit.pos; unit.goal = unit.pos
		if int(unit.id) != 6: unit.loaded = 0; unit.reserve = 0
	var shooter: Dictionary = screen.world.entity(6)
	shooter.pos = Vector2(36.5, 34.5)
	shooter.prev_pos = shooter.pos; shooter.goal = shooter.pos
	shooter.posture_mode = 0
	var foe: Dictionary = State.unit(901, 1, Vector2(40.5, 34.5))
	foe.hp = 5000.0; foe.max_hp = 5000.0; foe.loaded = 0; foe.reserve = 0
	foe.posture_mode = 0
	screen.world.units.append(foe)
	screen.world.next_wave = Config.WAVE_TIMES.size()
	screen.world.unit_system.setup(screen.world)
	foe.ai_next = 1000000.0; foe.ai_hold_until = 1000000.0
	screen.selected.assign([6]); screen.toast_label.hide()
	screen.camera.position = shooter.pos * 64 + Vector2(96, -12)
	screen.camera.zoom = Vector2.ONE * 2.0
	screen.camera.force_update_scroll()
	screen.view.reset_presentation()
	screen.world.start_battle()
	screen._sync_pause()
	order("attack", {"target_id": 901})
	var layer := CanvasLayer.new(); add_child(layer)
	label = Label.new(); label.position = Vector2(24, 110)
	label.add_theme_font_override("font", screen.ui_font)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("eef3dc"))
	layer.add_child(label)
	print("PAWN_FIT_REVIEW_STARTED controlled visual fixture; duration=42")

func order(kind: String, data: Dictionary) -> void:
	var result: Dictionary = screen.world.submit([6], kind, data)
	if not result.ok: failures.append(kind + ": " + String(result.reason))

func once(key: String, at: float) -> bool:
	if elapsed < at or issued.has(key): return false
	issued[key] = true; return true

func move_target(position: Vector2) -> void:
	var foe: Dictionary = screen.world.entity(901)
	foe.pos = position; foe.prev_pos = position; foe.goal = position
	screen.view.reset_presentation()
	order("attack", {"target_id": 901})

func outfit(top: String, legs: String, vest: String, helmet: bool = false, gear: String = "standard") -> void:
	var rng_before: int = screen.world.rng.state
	var hp_before: float = screen.world.entity(6).hp
	screen.view.pawn_art.visual_loadouts[6] = {"top": top, "legs": legs, "vest": vest, "helmet": helmet, "gear": gear}
	if screen.world.rng.state != rng_before or screen.world.entity(6).hp != hp_before:
		failures.append("Cosmetic garment swap changed battle state")
	screen.view.queue_redraw()

func _process(dt: float) -> void:
	if screen == null: return
	elapsed += dt
	# Keep an incidental desktop mouse wheel from changing the review framing.
	screen.camera.position = Vector2(36.5, 34.5) * 64 + Vector2(96, -12)
	screen.camera.zoom = Vector2.ONE * 2.0
	screen.camera.force_update_scroll()
	label.text = "受控美术短测 / %s\n真实游戏渲染与射击；固定目标血量和位置，仅检查动作与分层。" % ("站立与低蹲持枪" if elapsed < 25 else "卧倒持枪" if elapsed < 30 else "同一身体逐层换装（审阅覆盖，不代表配装UI）")
	for event in screen.world.events:
		if event.type != "weapon_fired" or int(event.get("holder_id", -1)) != 6: continue
		var key := int(event.step)
		if seen_shots.has(key): continue
		seen_shots[key] = true
		var posture: int = screen.world.entity(6).posture
		shots_by_pose[posture] = int(shots_by_pose.get(posture, 0)) + 1
	if once("crouch", 5): order("posture", {"value": 1})
	if once("north", 10): move_target(Vector2(36.5, 30.5))
	if once("west", 15): move_target(Vector2(32.5, 34.5))
	if once("south", 20): move_target(Vector2(36.5, 38.5))
	if once("prone", 25):
		order("posture", {"value": 2}); move_target(Vector2(40.5, 34.5))
	if once("wardrobe_pose", 29.0): order("posture", {"value": 1})
	if once("base", 30):
		screen.world.entity(6).target_id = -1
		screen.world.set_paused(true); screen._sync_pause()
		outfit("", "", "")
	if once("vest_only", 32): outfit("", "", "vest_standard")
	if once("uniform", 34): outfit("uniform_top", "uniform_legs", "vest_standard")
	if once("light", 36): outfit("uniform_top", "uniform_legs", "vest_light")
	if once("heavy", 38): outfit("uniform_top", "uniform_legs", "vest_heavy", true, "heavy")
	if once("legacy", 40): screen.view.use_legacy_pawns = true; screen.view.queue_redraw()
	if once("new", 41): screen.view.use_legacy_pawns = false; screen.view.queue_redraw()
	if elapsed >= 42:
		for posture in [0,1,2]:
			if int(shots_by_pose.get(posture, 0)) < 1: failures.append("No real firing for posture %d" % posture)
		var report := {"passed": failures.is_empty(), "fixture": true, "purpose": "Visual fitting and shared body independent garment proof; not balance/stress validation", "fixture_changes": ["unit 6 at (36.5,34.5), other units alive outside camera with no ammo", "durable target 901 with 5000 HP and no ammo; AI deferred; waves disabled", "target moved to four directions, ordinary attack/posture commands", "last 12 seconds paused, display-only outfit overrides"], "shots_by_pose": shots_by_pose, "garment_keys": screen.view.pawn_art.garments.keys(), "body_texture_count": screen.view.pawn_art.bodies.size(), "failures": failures}
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report, "\t"))
		print("PAWN_FIT_REVIEW_FINISHED ", JSON.stringify(report))
		get_tree().quit(0 if failures.is_empty() else 1)
