extends "res://tests/play_profiles.gd"

var variant: String = ""
var ducked: Dictionary = {}
var timed: Dictionary = {}
var lead_updated: int = -1
var replay_path: String = ""

func _run() -> void:
	var profiles: Array[String] = ["prone_crew", "rotation", "barrage", "solo_rear", "rear_line"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): profiles.assign([arg.trim_prefix("--profile=")])
		if arg.begins_with("--replay="): replay_path = arg.trim_prefix("--replay=")
	if not replay_path.is_empty(): _replay(); return
	var results: Array[Dictionary] = []
	for profile in profiles:
		variant = profile
		care.clear(); roles.clear(); guard_points.clear(); prepared.clear(); operations.clear(); move_allocations.clear(); ducked.clear(); timed.clear(); rejected = 0; lead_updated = -1
		var w = World.new()
		super._prepare(w, "siege")
		if variant == "solo_rear":
			roles.erase(3); guard_points[3] = Vector2(28.5, 34.5)
			_send(w, [3], "move", {"position": guard_points[3]})
		_send(w, [4] if variant == "solo_rear" else [3, 4], "posture", {"value": 2})
		w.start_battle()
		var damage_events: Array[Dictionary] = []; var last_serial := 0; var started := Time.get_ticks_msec()
		while w.phase == "running" and w.step_index < 28801:
			if w.step_index % 15 == 0: _command(w, "siege")
			w.step()
			for event in w.events:
				if int(event.serial) <= last_serial: continue
				last_serial = int(event.serial)
				if event.type == "damage" and int(event.get("target_team", -1)) == 0: damage_events.append(event.duplicate(true))
			if w.step_index % 3600 == 0: print("SEARCH_PROGRESS ", variant, " ", JSON.stringify(_brief(w)))
		var result := _snapshot(w)
		result.merge({"variant": variant, "seed": Config.SEED, "commands": operations.duplicate(true), "accepted_commands": operations.size(), "rejected_commands": rejected, "damage_events": damage_events, "wall_ms": Time.get_ticks_msec() - started})
		results.append(result)
		DirAccess.make_dir_recursive_absolute("res://build/reports")
		var file := FileAccess.open("res://build/reports/tactics_search_" + variant + ".json", FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(result, "\t")); file.close()
		print("SEARCH_RESULT ", variant, " ", JSON.stringify(_brief(w)), " rejected=", rejected, " commands=", operations.size())
		if w.phase == "won": break
	print("TACTICS_SEARCH_FINISHED")
	quit()

func _command(w, profile: String) -> void:
	if variant == "rotation" and w.time_s >= 200.0 and not timed.has("rotation"):
		var veteran: Dictionary = w.entity(1); var replacement: Dictionary = w.entity(5)
		if veteran.conscious and not veteran.dead and replacement.conscious and not replacement.dead and veteran.hp < 75.0:
			_send(w, [1], "move", {"position": Vector2(25.5, 34.5)})
			if _send(w, [5], "operate", {"target_id": w.stations()[0].id}):
				roles.erase(1); roles[5] = 0; guard_points.erase(5); guard_points[1] = Vector2(25.5, 34.5)
				_send(w, [5], "posture", {"value": 1}); _send(w, [1], "posture", {"value": 2}); timed.rotation = true
	if variant == "barrage":
		for wave in [150.0, 300.0]:
			var evacuate := "evacuate_" + str(wave); var return_key := "return_" + str(wave)
			if w.time_s >= wave - 10.0 and w.time_s < wave and not timed.has(evacuate):
				roles.erase(2); guard_points[2] = Vector2(57.5, 24.5); _send(w, [2], "move", {"position": guard_points[2]}); timed[evacuate] = true
			if w.time_s >= wave + 10.0 and not timed.has(return_key):
				roles[2] = 1; guard_points.erase(2); _send(w, [2], "operate", {"target_id": w.stations()[1].id}); timed[return_key] = true
	if variant == "rear_line" and w.time_s >= 299.0 and not timed.has("withdraw"):
		for id in [1, 2]:
			roles.erase(id); guard_points[id] = Vector2(25.5, 34.5) if id == 1 else Vector2(39.5, 34.5)
			_send(w, [id], "move", {"position": guard_points[id]}); _send(w, [id], "posture", {"value": 1})
		timed.withdraw = true
	super._command(w, profile)
	for id in roles:
		var u: Dictionary = w.entity(int(id))
		if u.dead or not u.conscious or u.job != "operate": continue
		if int(roles[id]) == 2:
			if u.posture_mode != 2: _send(w, [id], "posture", {"value": 2})
			continue
		if ducked.has(id):
			if w.time_s >= float(ducked[id]) and u.suppression < 20.0 and not u.forced_prone:
				_send(w, [id], "posture", {"value": 1}); ducked.erase(id)
		elif u.suppression >= 28.0 and not u.forced_prone:
			_send(w, [id], "posture", {"value": 2}); ducked[id] = w.time_s + 3.0
	# A healthy reserve guards west in the final attack instead of walking back
	# to the north-facing sandbag. No weapon/HP/ammunition changes are made.
	if w.time_s >= 275.0 and not timed.has("west_reserve"):
		guard_points[6] = Vector2(14.5, 27.5)
		if not w.entity(6).job in ["treat", "rescue", "resupply"]: _return(w, 6)
		timed.west_reserve = true

func _mortar(w) -> void:
	var b: Dictionary = w.stations()[2]
	if b.destroyed or b.crew.is_empty(): return
	var solo := variant == "solo_rear"
	for wave in [30.0, 150.0, 300.0]:
		if w.time_s >= wave - (17.0 if solo else 11.0) and w.time_s < wave and not prepared.has(wave):
			# All three north cohorts get an entry barrage. The original controller
			# spent its third preparatory shot on west, leaving four north rifles.
			if _send(w, [b.crew[0]], "fire", {"target_id": b.id, "position": Vector2(13.0, 0.6)}): prepared[wave] = true
	if b.fire_requested:
		# Update at most once, just as loading finishes: a fresh four-second aim
		# plus three-second flight stays in the forecast; never retarget each tick.
		if b.loaded > 0 and b.aim_progress < 0.25 and lead_updated != w.stats.mortar_shots:
			if w.time_s >= 150.0:
				var point := _lead_point(w, b, 7.0)
				if point != Vector2.INF and _send(w, [b.crew[0]], "fire", {"target_id": b.id, "position": point}): lead_updated = int(w.stats.mortar_shots)
		return
	var horizon: float = 3.0 + (4.0 if b.loaded > 0 else 4.0 + (10.0 - b.reload_progress) / (1.0 if solo else 2.5))
	var point := _lead_point(w, b, horizon)
	if point != Vector2.INF: _send(w, [b.crew[0]], "fire", {"target_id": b.id, "position": point})

func _lead_point(w, b: Dictionary, horizon: float) -> Vector2:
	var best := Vector2.INF; var best_score := -INF
	for enemy in w.units:
		if enemy.team != 1 or enemy.dead or not enemy.conscious: continue
		var point := _forecast(enemy, horizon)
		if point.distance_to(b.pos) < 8.0 or point.distance_to(b.pos) > 40.0: continue
		var safe := true; var score := 0.0
		for unit in w.units:
			if unit.dead: continue
			if unit.team == 0 and unit.pos.distance_to(point) < 12.75: safe = false; break
			if unit.team == 1 and unit.conscious:
				score += maxf(0.0, 1.0 - _forecast(unit, horizon).distance_to(point) / 4.0) * (1.5 if unit.kind == "heavy" else 1.0)
		if safe and score > best_score: best = point; best_score = score
	return best

func _forecast(u: Dictionary, horizon: float) -> Vector2:
	var position: Vector2 = u.pos
	var budget: float = horizon * u.move_speed * Config.POSTURE_SPEED[int(u.posture)]
	if u.forced_prone or u.job == "rout": budget = 0.0
	for index in range(int(u.path_index), u.path.size()):
		var point: Vector2 = u.path[index]; var distance := position.distance_to(point)
		if distance > budget: return position.move_toward(point, budget)
		position = point; budget -= distance
	return position

func _brief(w) -> Dictionary:
	var result := _snapshot(w); result.erase("people")
	return result

func _replay() -> void:
	var recorded: Dictionary
	if replay_path.ends_with(".gd"):
		var source = load(replay_path)
		if source == null: push_error("Cannot load tactical recording"); quit(1); return
		recorded = source.expected(); recorded["commands"] = source.commands()
	else:
		var file := FileAccess.open(replay_path, FileAccess.READ)
		if file == null: push_error("Cannot open tactical recording"); quit(1); return
		recorded = JSON.parse_string(file.get_as_text()); file.close()
	var commands: Array = recorded.commands
	var w = World.new(); var cursor := 0; var failures := 0
	while w.phase in ["preparing", "running"] and w.step_index < 28801:
		while cursor < commands.size() and int(commands[cursor].step) == w.step_index:
			var order: Dictionary = commands[cursor]; var payload: Dictionary = order.data.duplicate(true)
			if payload.get("position") is Array: payload.position = Vector2(payload.position[0], payload.position[1])
			if not w.submit(order.ids, order.kind, payload).ok: failures += 1
			cursor += 1
		if w.phase == "preparing": w.start_battle()
		w.step()
	var actual := _snapshot(w)
	var passed: bool = cursor == commands.size() and failures == 0 and int(actual.state_hash) == int(recorded.state_hash) and actual.phase == recorded.phase
	for key in ["time", "core_hp", "alive", "awake", "living_enemies"]:
		if recorded.has(key) and actual[key] != recorded[key]: passed = false
	for key in ["rifle_shots", "mg_shots", "mortar_shots", "enemy_spawned", "friendly_fire"]:
		if recorded.has(key) and int(actual.stats[key]) != int(recorded[key]): passed = false
	print("TACTICS_REPLAY ", JSON.stringify(_brief(w)), " commands=", cursor, " rejected=", failures, " exact=", passed)
	quit(0 if passed else 1)
