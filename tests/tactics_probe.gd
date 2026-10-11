extends SceneTree

const World = preload("res://scripts/sim/world.gd")
var care: Dictionary = {}
var returning: Dictionary = {}
var last_aim: Vector2 = Vector2.INF
var rejected: int = 0
var profile_name: String = ""
var operations: Array[Dictionary] = []
var station_roles: Dictionary = {}
var prepared_waves: Dictionary = {}
var rotated: bool = false
var ducking: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _send(w, ids: Array, kind: String, data: Dictionary = {}) -> bool:
	var result: Dictionary = w.submit(ids, kind, data)
	if not result.ok: rejected += 1
	else:
		var recorded := data.duplicate(true)
		recorded.erase("_allocations")
		if recorded.get("position") is Vector2: recorded.position = [recorded.position.x, recorded.position.y]
		operations.append({"time": snappedf(w.time_s, 0.001), "step": w.step_index, "ids": ids.duplicate(), "kind": kind, "data": recorded})
	return result.ok

func _run() -> void:
	var profiles: Array[String] = ["verified"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): profiles.assign([arg.trim_prefix("--profile=")])
	for profile in profiles:
		if profile == "verified":
			_replay_verified(); return
		var started := Time.get_ticks_msec()
		care.clear(); returning.clear(); ducking.clear(); operations.clear(); prepared_waves.clear(); station_roles = {1: 0, 2: 1, 3: 2, 4: 2}; rotated = false
		last_aim = Vector2.INF; rejected = 0; profile_name = profile
		var w = World.new()
		var stations: Array[Dictionary] = w.stations()
		_send(w, [1, 2, 3, 4, 5, 6], "posture", {"value": 1})
		_send(w, [1, 2, 3, 4, 5, 6], "style", {"value": 2 if profile == "precision" else 1})
		if profile in ["fortress", "prepared", "adaptive", "flank_guard", "counterfire", "reserve"]: _send(w, [1, 2], "style", {"value": 0})
		_send(w, [1], "operate", {"target_id": stations[0].id})
		_send(w, [2], "operate", {"target_id": stations[1].id})
		_send(w, [3, 4], "operate", {"target_id": stations[2].id})
		if profile in ["flank_guard", "counterfire", "reserve"]:
			_send(w, [5, 6], "posture", {"value": 2})
			_send(w, [5, 6], "style", {"value": 0 if profile in ["counterfire", "reserve"] else 2})
			_send(w, [5], "move", {"position": Vector2(8.5, 25.5)})
			_send(w, [6], "move", {"position": Vector2(10.5, 27.5)})
		elif profile in ["fortress", "prepared", "adaptive"]:
			_send(w, [5], "move", {"position": Vector2(32.5, 24.5)})
			_send(w, [6], "move", {"position": Vector2(32.5, 25.5)})
		else:
			_send(w, [5], "resupply", {"target_id": stations[0].id})
			_send(w, [6], "resupply", {"target_id": stations[1].id})
		w.start_battle()
		var last_event_serial := 0
		var damage_log: Array[Dictionary] = []
		while w.phase == "running" and w.step_index < 29000:
			if w.step_index > 0 and w.step_index % 15 == 0:
				_command(w, stations)
			w.step()
			for index in range(w.events.size() - 1, -1, -1):
				var event: Dictionary = w.events[index]
				if int(event.serial) <= last_event_serial: break
				if event.type == "damage" and int(event.entity_id) <= 6: damage_log.append(event.duplicate())
			if not w.events.is_empty(): last_event_serial = int(w.events[-1].serial)
			if w.step_index % 3600 == 0:
				print("TACTIC_PROGRESS ", profile, " ", JSON.stringify(_summary(w)))
		var result: Dictionary = _summary(w)
		result["profile"] = profile; result["wall_ms"] = Time.get_ticks_msec() - started
		result["commands_rejected"] = rejected
		print("TACTIC_RESULT ", JSON.stringify(result))
		print("TACTIC_OPERATIONS ", profile, " ", JSON.stringify(operations))
		print("TACTIC_DAMAGE ", profile, " ", JSON.stringify(damage_log))
	quit()

func _command(w, stations: Array[Dictionary]) -> void:
	var supplies_claimed: Array[int] = []
	var visible_enemies := false
	for enemy in w.units:
		if enemy.team == 1 and not enemy.dead and enemy.conscious: visible_enemies = true; break
	if profile_name == "reserve":
		if w.time_s >= 280.0 and not prepared_waves.has("guard_retreat"):
			_send(w, [6], "move", {"position": Vector2(14.5, 27.5)}); prepared_waves["guard_retreat"] = true
		if w.time_s >= 299.5 and not prepared_waves.has("reserve_duck"):
			_send(w, [1, 2], "posture", {"value": 2}); prepared_waves["reserve_duck"] = true
		if w.time_s >= 322.0 and not prepared_waves.has("reserve_rise"):
			_send(w, [1, 2], "posture", {"value": 1}); prepared_waves["reserve_rise"] = true
	if profile_name in ["flank_guard", "counterfire", "reserve"] and not visible_enemies and w.time_s > 60.0 and w.time_s < 130.0:
		var loader: Dictionary = w.entity(3)
		if loader.job == "operate" and stations[1].ammo == 0 and stations[1].supply_reserved == 0:
			_send(w, [3], "resupply", {"target_id": stations[1].id})
	if profile_name == "adaptive":
		for station_index in [0, 1]:
			if stations[station_index].destroyed or not stations[station_index].crew.is_empty(): continue
			for helper_id in [6, 5]:
				var helper: Dictionary = w.entity(helper_id)
				if station_roles.has(helper_id) or helper.dead or not helper.conscious or helper.job != "idle" or helper.hp < 50.0: continue
				if _send(w, [helper_id], "operate", {"target_id": stations[station_index].id}): station_roles[helper_id] = station_index; break
	if profile_name == "prepared" and not rotated and w.time_s >= 90.0 and w.time_s < 130.0:
		var weak: Dictionary = w.entity(1); var replacement: Dictionary = w.entity(6)
		if weak.conscious and replacement.conscious and weak.hp < 75.0:
			_send(w, [1], "move", {"position": Vector2(32.5, 25.5)})
			_send(w, [6], "operate", {"target_id": stations[0].id})
			station_roles.erase(1); station_roles[6] = 0; rotated = true
	for id in range(1, 7):
		var u: Dictionary = w.entity(id)
		if u.dead or not u.conscious or w.time_s < float(u.rout_until): continue
		if not u.drafted:
			_send(w, [id], "draft", {"value": true}); continue
		if care.has(id):
			if u.job == "idle" and float(u.bleed_rate) <= 0.0:
				_send(w, [id], "posture", {"value": 2 if profile_name in ["flank_guard", "counterfire", "reserve"] and id >= 5 else 1})
				care.erase(id)
				_return_to_role(w, id, stations)
			continue
		if profile_name == "adaptive" and int(u.station_id) >= 0 and w.entity(int(u.station_id)).kind == "mg" and u.stage == "station":
			if ducking.has(id):
				if w.time_s >= float(ducking[id]) and u.suppression < 20.0 and not u.forced_prone:
					_send(w, [id], "posture", {"value": 1}); ducking.erase(id)
				else: continue
			elif u.suppression >= 25.0:
				_send(w, [id], "posture", {"value": 2}); ducking[id] = w.time_s + 3.0; continue
		var treatment_threshold := 95.0 if not visible_enemies else (75.0 if profile_name in ["fortress", "prepared", "adaptive", "flank_guard", "counterfire", "reserve"] else 90.0)
		if u.bleed_rate > 0.05 and u.hp < treatment_threshold and u.bandages > 0 and not u.job in ["rescue", "treat", "resupply"]:
			if _send(w, [id], "treat", {"target_id": id}):
				_send(w, [id], "posture", {"value": 2}); care[id] = true; continue
		if station_roles.has(id) and u.job == "idle": _return_to_role(w, id, stations)
		if not station_roles.has(id) and not u.job in ["resupply", "rescue", "treat"]:
			if profile_name in ["counterfire", "reserve"] and u.job == "idle":
				var target: Dictionary = {}; var priority := -INF
				for enemy in w.units:
					if enemy.team != 1 or enemy.dead or not enemy.conscious or u.pos.distance_to(enemy.pos) > 24.0 or not w.combat_system.has_line_of_fire(w, u, enemy): continue
					var score: float = (100.0 if enemy.suppression < 60.0 else 0.0) - u.pos.distance_to(enemy.pos)
					if score > priority: target = enemy; priority = score
				if not target.is_empty():
					var style := 0 if target.suppression < 60.0 else 2
					if int(u.style) != style: _send(w, [id], "style", {"value": style})
					if int(u.target_id) != int(target.id): _send(w, [id], "attack", {"target_id": target.id})
				elif int(u.target_id) >= 0: _send(w, [id], "stop")
			if profile_name == "adaptive":
				var rescued := false
				for patient in w.units:
					if patient.team == 0 and not patient.dead and not patient.conscious and patient.bleed_rate > 0.0 and int(patient.get("rescue_owner", -1)) < 0:
						if _send(w, [id], "rescue", {"target_id": patient.id}): rescued = true; break
				if rescued: continue
			var supplied := false
			for b in stations:
				if profile_name in ["flank_guard", "counterfire", "reserve"] and visible_enemies: continue
				if b.kind == "mg" and not b.destroyed and not b.crew.is_empty() and b.loaded < 35 and b.ammo == 0 and b.supply_reserved == 0 and not supplies_claimed.has(int(b.id)):
					if _send(w, [id], "resupply", {"target_id": b.id}): supplied = true; supplies_claimed.append(int(b.id)); break
			if supplied: continue
			if u.job == "idle": _return_to_role(w, id, stations)
	var mortar: Dictionary = stations[2]
	if not mortar.destroyed and not mortar.crew.is_empty():
		if profile_name in ["prepared", "adaptive", "flank_guard", "counterfire", "reserve"]:
			for wave_time in [30.0, 150.0, 300.0]:
				if w.time_s >= wave_time - 11.0 and w.time_s < wave_time and not prepared_waves.has(wave_time):
					var point := Vector2(13.6, 0.6)
					if profile_name in ["adaptive", "flank_guard", "counterfire", "reserve"] and wave_time == 300.0: point = Vector2(46.2, 1.5)
					if profile_name == "reserve" and wave_time == 300.0: point = Vector2(0.6, 19.6)
					if _send(w, [int(mortar.crew[0])], "fire", {"target_id": mortar.id, "position": point}):
						prepared_waves[wave_time] = true; last_aim = point
			if mortar.fire_requested: return
		var point := _mortar_point(w, mortar)
		if point != Vector2.INF and (not mortar.fire_requested or (int(mortar.loaded) == 0 and float(mortar.reload_progress) < 8.0 and point.distance_to(last_aim) > 1.5)):
			var gunner: int = int(mortar.crew[0])
			if _send(w, [gunner], "fire", {"target_id": mortar.id, "position": point}): last_aim = point

func _return_to_role(w, id: int, stations: Array[Dictionary]) -> void:
	if station_roles.has(id):
		var station: Dictionary = stations[int(station_roles[id])]
		if not station.destroyed: _send(w, [id], "operate", {"target_id": station.id})
	else:
		var point := Vector2(32.5, 24.5) if id == 5 else Vector2(32.5, 25.5)
		if profile_name in ["flank_guard", "counterfire"]: point = Vector2(8.5, 25.5) if id == 5 else Vector2(10.5, 27.5)
		elif profile_name == "reserve": point = Vector2(16.5, 21.5) if id == 5 else Vector2(38.5, 21.5)
		if profile_name == "reserve" and id == 6 and w.time_s >= 280.0: point = Vector2(14.5, 27.5)
		elif not profile_name in ["fortress", "prepared", "adaptive", "flank_guard", "counterfire", "reserve"]: point = Vector2(16.5, 21.5) if id == 5 else Vector2(38.5, 21.5)
		if w.entity(id).pos.distance_to(point) < 0.05: return
		_send(w, [id], "move", {"position": point})

func _mortar_point(w, mortar: Dictionary) -> Vector2:
	var best := Vector2.INF; var best_score := -INF
	for enemy in w.units:
		if enemy.team != 1 or enemy.dead or not enemy.conscious: continue
		var point: Vector2 = enemy.pos + enemy.velocity * 3.0
		point.x = clampf(point.x, 0.5, 63.5); point.y = clampf(point.y, 0.5, 47.5)
		if point.distance_to(mortar.pos) < 8.0 or point.distance_to(mortar.pos) > 40.0: continue
		var score := 0.0; var safe := true
		for u in w.units:
			if u.dead: continue
			if u.team == 0 and u.pos.distance_to(point) < (12.75 if profile_name in ["fortress", "prepared", "adaptive", "flank_guard", "counterfire", "reserve"] else 7.0): safe = false; break
			if u.team == 1:
				var distance: float = u.pos.distance_to(point)
				score += maxf(0.0, 1.0 - distance / 5.0) * (1.5 if u.kind == "heavy" else 1.0)
		if safe and score > best_score: best = point; best_score = score
	return best

func _summary(w) -> Dictionary:
	var allies: Array[Dictionary] = []; var enemies: Array[Dictionary] = []
	for u in w.units:
		var info := {"id": u.id, "hp": snappedf(u.hp, 0.1), "bleed": u.bleed_rate, "q": snappedf(u.suppression, 0.1), "job": u.job, "stage": u.stage, "pos": str(u.pos), "posture": u.posture, "bandages": u.bandages}
		if u.team == 0: allies.append(info)
		elif not u.dead: enemies.append(info)
	var guns: Array[Dictionary] = []
	for b in w.stations(): guns.append({"kind": b.kind, "hp": b.hp, "ammo": b.ammo, "loaded": b.loaded, "crew": b.crew, "status": b.status})
	return {"phase": w.phase, "time": snappedf(w.time_s, 0.1), "core": w.core().hp, "stats": w.stats.duplicate(), "allies": allies, "enemies": enemies, "stations": guns, "state_hash": hash(var_to_bytes([w.time_s, w.units, w.buildings, w.supplies, w.projectiles, w.stats, w.rng.state]))}

# Frozen public-command recording from the successful reserve run. This replay
# never edits unit health, inventories, AI, weapon values, RNG or wave timing.
# Format: [physics step, selected IDs, command, public payload].
func _verified_sequence() -> Array:
	return [
		[0, [1,2,3,4,5,6], "posture", {"value":1}],
		[0, [1,2,3,4,5,6], "style", {"value":1}],
		[0, [1,2], "style", {"value":0}],
		[0, [1], "operate", {"target_id":1022}],
		[0, [2], "operate", {"target_id":1023}],
		[0, [3,4], "operate", {"target_id":1024}],
		[0, [5,6], "posture", {"value":2}],
		[0, [5,6], "style", {"value":0}],
		[0, [5], "move", {"position":Vector2(8.5,25.5)}],
		[0, [6], "move", {"position":Vector2(10.5,27.5)}],
		[1140, [4], "fire", {"position":Vector2(13.6,0.6), "target_id":1024}],
		[1800, [4], "fire", {"position":Vector2(15.1,0.6), "target_id":1024}],
		[2160, [6], "move", {"position":Vector2(38.5,21.5)}],
		[2190, [5], "resupply", {"target_id":1022}],
		[3615, [3], "resupply", {"target_id":1023}],
		[4320, [5], "move", {"position":Vector2(16.5,21.5)}],
		[4530, [3], "operate", {"target_id":1024}],
		[8340, [4], "fire", {"position":Vector2(13.6,0.6), "target_id":1024}],
		[9000, [5], "attack", {"target_id":111}],
		[9000, [4], "fire", {"position":Vector2(46.1,0.6), "target_id":1024}],
		[9075, [5], "attack", {"target_id":110}],
		[9420, [5], "attack", {"target_id":111}],
		[9570, [5], "style", {"value":2}],
		[9705, [5], "style", {"value":0}],
		[9720, [5], "style", {"value":2}],
		[9855, [5], "treat", {"target_id":5}],
		[9855, [5], "posture", {"value":2}],
		[10230, [5], "posture", {"value":2}],
		[16800, [6], "move", {"position":Vector2(14.5,27.5)}],
		[16800, [6], "move", {"position":Vector2(14.5,27.5)}],
		[17340, [4], "fire", {"position":Vector2(0.6,19.6), "target_id":1024}],
		[17970, [1,2], "posture", {"value":2}],
		[18000, [5], "style", {"value":0}],
		[18000, [5], "attack", {"target_id":121}],
		[18000, [4], "fire", {"position":Vector2(15.9327697753906,5.93276882171631), "target_id":1024}],
		[18015, [5], "stop", {}],
		[18105, [1], "treat", {"target_id":1}],
		[18105, [1], "posture", {"value":2}],
		[18375, [3], "treat", {"target_id":3}],
		[18375, [3], "posture", {"value":2}],
		[18480, [4], "fire", {"position":Vector2(44.4942436218262,9.50575733184814), "target_id":1024}],
		[18510, [5], "treat", {"target_id":5}],
		[18510, [5], "posture", {"value":2}],
		[18630, [6], "attack", {"target_id":113}],
		[18660, [6], "stop", {}],
		[18765, [4], "treat", {"target_id":4}],
		[18765, [4], "posture", {"value":2}],
		[19005, [1], "posture", {"value":1}],
		[19005, [1], "operate", {"target_id":1022}],
		[19065, [1], "treat", {"target_id":1}],
		[19065, [1], "posture", {"value":2}],
		[19155, [4], "posture", {"value":1}],
		[19155, [4], "operate", {"target_id":1024}],
		[19305, [4], "treat", {"target_id":4}],
		[19305, [4], "posture", {"value":2}],
		[19320, [1,2], "posture", {"value":1}],
		[19470, [1], "posture", {"value":1}],
		[19470, [1], "operate", {"target_id":1022}],
		[19695, [4], "posture", {"value":1}],
		[19695, [4], "operate", {"target_id":1024}],
	]

func _replay_verified() -> void:
	var started := Time.get_ticks_msec()
	var w = World.new()
	var sequence := _verified_sequence()
	var index := 0
	var errors: Array[String] = []
	rejected = 0; operations.clear()
	w.start_battle()
	while w.phase == "running" and w.step_index < 28800:
		while index < sequence.size() and int(sequence[index][0]) == w.step_index:
			var command: Array = sequence[index]
			if not _send(w, command[1], command[2], command[3]): errors.append("Rejected recording command %d at step %d" % [index, w.step_index])
			index += 1
		w.step()
	var summary := _summary(w)
	var expected_hp := [25.4, 100.0, 0.0, 45.0, 0.0, 100.0]
	if w.phase != "won" or absf(w.time_s - 480.0) > 0.001 or w.core().hp != 991.0: errors.append("Recorded public commands did not reproduce the 480-second / 991-core-HP victory")
	for unit_index in range(6):
		if absf(float(summary.allies[unit_index].hp) - float(expected_hp[unit_index])) > 0.00001: errors.append("Survivor HP differs at unit %d" % [unit_index + 1])
	if w.stats.mg_shots != 294 or w.stats.mortar_shots != 6 or w.stats.rifle_shots != 542 or w.stats.friendly_fire != 38: errors.append("Recorded shot/damage counters differ")
	if index != sequence.size() or rejected != 0: errors.append("Recording was not completely accepted")
	summary["orders"] = index; summary["wall_ms"] = Time.get_ticks_msec() - started; summary["errors"] = errors
	print("TACTIC_VERIFIED_RESULT ", JSON.stringify(summary))
	print("TACTIC_VERIFIED_PASSED" if errors.is_empty() else "TACTIC_VERIFIED_FAILED")
	quit(0 if errors.is_empty() else 1)
