extends Node

# Ordinary game scene and public commands, no damage/AI/map/balance overrides.
var screen
var elapsed := 0.0
var issued: Dictionary = {}
var failures: Array[String] = []
var label: Label
var initial_rng: int
var report_path := "res://build/pawn_art_evidence/report.json"

func setup(target) -> void:
	screen = target
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pawn-art-report="): report_path = argument.trim_prefix("--pawn-art-report=")
	process_mode = Node.PROCESS_MODE_ALWAYS
	screen.toast_label.hide()
	screen.selected.assign([5, 6])
	screen.camera.position = Vector2(36, 34.5) * 64
	screen.camera.zoom = Vector2.ONE * 1.1
	screen.camera.force_update_scroll()
	initial_rng = screen.world.rng.state
	if not screen.view.pawn_art.ready: failures.append("New pawn textures not loaded")
	screen.world.start_battle()
	screen._sync_pause()
	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(24, 110)
	label.add_theme_font_override("font", screen.ui_font)
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color("eef3dc"))
	layer.add_child(label)
	print("PAWN_ART_REVIEW_STARTED duration=60; ordinary scene/public commands")

func order(ids: Array, kind: String, data: Dictionary) -> void:
	var result: Dictionary = screen.world.submit(ids, kind, data)
	if not result.ok: failures.append(kind + ": " + String(result.reason))

func once(key: String, at: float) -> bool:
	if elapsed < at or issued.has(key): return false
	issued[key] = true
	return true

func _process(dt: float) -> void:
	if screen == null: return
	elapsed += dt
	if elapsed < 22:
		screen.camera.position = Vector2(screen.world.entity(6).pos) * 64 + Vector2(160, -20)
		screen.camera.force_update_scroll()
	label.text = "小人美术短测 · 普通指令回放 / %s" % ("四向移动" if elapsed < 12 else "站立、蹲伏、卧倒" if elapsed < 22 else "进入阵地与真实交火")
	if once("east", 0.2): order([6], "move", {"position": Vector2(42.5, 35.5)})
	if once("north", 3): order([6], "move", {"position": Vector2(42.5, 30.5)})
	if once("west", 6): order([6], "move", {"position": Vector2(36.5, 30.5)})
	if once("south", 9): order([6], "move", {"position": Vector2(36.5, 35.5)})
	if once("crouch", 12):
		order([5, 6], "posture", {"value": 1})
		order([6], "move", {"position": Vector2(38.5, 34.5)})
	if once("prone", 16):
		order([5, 6], "posture", {"value": 2})
		order([6], "move", {"position": Vector2(39.5, 34.5)})
	if once("stand", 20): order([5, 6], "posture", {"value": 0})
	if once("deploy", 22):
		order([1], "operate", {"target_id": 1022})
		order([2], "operate", {"target_id": 1023})
		order([3], "operate", {"target_id": 1024})
		order([4], "move", {"position": Vector2(34.5, 25.5)})
		order([5], "move", {"position": Vector2(27.5, 22.5)})
		order([6], "move", {"position": Vector2(34.5, 22.5)})
	if once("front", 30):
		screen.camera.position = Vector2(32, 22.5) * 64
		screen.camera.zoom = Vector2.ONE * 1.1
		screen.camera.force_update_scroll()
	if once("combat_postures", 43):
		order([5], "posture", {"value": 1})
		order([6], "posture", {"value": 2})
	if once("gunner_close", 40):
		screen.selected.assign([1])
		screen.camera.position = Vector2(22.5, 21.5) * 64
		screen.camera.zoom = Vector2.ONE * 1.2
		screen.camera.force_update_scroll()
	if once("legacy", 57):
		var rng_before: int = screen.world.rng.state
		var state_before: int = screen.world.step_index
		screen.view.use_legacy_pawns = true
		screen.view.queue_redraw()
		if screen.world.rng.state != rng_before or screen.world.step_index != state_before: failures.append("Appearance switch mutated simulation")
	if once("new", 58): screen.view.use_legacy_pawns = false
	if elapsed >= 60:
		if screen.view.pawn_art.observed_directions.size() != 4: failures.append("Not all four directions rendered")
		if screen.view.pawn_art.observed_postures.size() < 3: failures.append("Standing/crouch/prone not all rendered")
		var report := {"passed":failures.is_empty(),"purpose":"60-second visual smoke test; not stress or balance testing","source":"actual BattleScreen and public world.submit commands","elapsed_s":elapsed,"simulation_s":screen.world.time_s,"directions":screen.view.pawn_art.observed_directions.keys(),"postures":screen.view.pawn_art.observed_postures.keys(),"stats":screen.world.stats,"failures":failures}
		var file := FileAccess.open(report_path,FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report,"\t"))
		print("PAWN_ART_REVIEW_FINISHED ",JSON.stringify(report))
		get_tree().quit(0 if failures.is_empty() else 1)
