extends SceneTree

const World = preload("res://scripts/sim/world.gd")
const Config = preload("res://scripts/sim/battle_config.gd")
var care: Dictionary = {}
var roles: Dictionary = {}
var guard_points: Dictionary = {}
var prepared: Dictionary = {}
var operations: Array[Dictionary] = []
var move_allocations: Dictionary = {}
var rejected: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _send(w, ids: Array, kind: String, data: Dictionary = {}) -> bool:
	var result: Dictionary = w.submit(ids, kind, data)
	if not result.ok: rejected += 1; return false
	if kind == "move":
		for id in ids:
			var allocation: Dictionary = w.pending_orders[-1].data.get("_allocations", {}).get(int(id), {})
			move_allocations[int(id)] = {"requested": data.position, "actual": allocation.get("goal", data.position)}
	var payload := data.duplicate(true)
	payload.erase("_allocations")
	if payload.get("position") is Vector2: payload.position = [payload.position.x, payload.position.y]
	operations.append({"step": w.step_index, "time": snappedf(w.time_s, 0.001), "ids": ids.duplicate(), "kind": kind, "data": payload})
	return true

func _run() -> void:
	var profiles: Array[String] = ["rifles", "dual_mg", "siege", "neglect_supply", "neglect_flank"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): profiles.assign([arg.trim_prefix("--profile=")])
	var summaries: Array[Dictionary] = []
	for profile in profiles:
		if not profile in ["rifles", "dual_mg", "siege", "neglect_supply", "neglect_flank"]:
			push_error("Unknown comparison profile: " + profile); quit(1); return
		var started := Time.get_ticks_msec()
		care.clear(); roles.clear(); guard_points.clear(); prepared.clear(); operations.clear(); move_allocations.clear(); rejected = 0
		var w = World.new()
		_prepare(w, profile)
		w.start_battle()
		var last_serial := 0; var max_projectiles := 0; var ally_hits := 0; var ally_damage := 0.0
		var flank_hits := 0; var flank_damage := 0.0; var manual_supplies := 0; var deliveries := 0
		var empty_seconds := 0.0; var away_seconds := 0.0
		var snapshots: Array[Dictionary] = []
		var damage_events: Array[Dictionary] = []
		while w.phase == "running" and w.step_index < 28801:
			if w.step_index % 15 == 0: _command(w, profile)
			w.step()
			for station in w.stations():
				if station.kind != "mg" or station.destroyed: continue
				if station.loaded <= 0 and station.ammo <= 0 and station.reload_reserved <= 0: empty_seconds += Config.FIXED_DT
				for id in station.crew:
					if w.entity(int(id)).stage in ["supply_pickup", "supply_deliver", "return_station"]: away_seconds += Config.FIXED_DT
			max_projectiles = maxi(max_projectiles, w.projectiles.size())
			for event in w.events:
				if int(event.serial) <= last_serial: continue
				last_serial = int(event.serial)
				if event.type == "supply_delivered": deliveries += 1
				if event.type != "damage": continue
				var victim: Dictionary = w.entity(int(event.get("entity_id", -1)))
				var shooter: Dictionary = w.entity(int(event.get("shooter_id", -1)))
				if victim.get("team", -1) == 0:
					damage_events.append(event.duplicate(true))
					if int(event.get("team", -1)) == 0: ally_hits += 1; ally_damage += float(event.amount)
					if shooter.get("kind", "") == "flanker": flank_hits += 1; flank_damage += float(event.amount)
			if w.step_index in [9000, 18000, 21600, 28800]: snapshots.append(_snapshot(w))
		for order in operations:
			if order.kind == "resupply": manual_supplies += 1
		var result := _snapshot(w)
		result.merge({"profile": profile, "seed": Config.SEED, "ai_contract": "strict_priority_dynamic_cover_melee_v2", "reason": w.result_reason, "max_projectiles": max_projectiles, "wall_ms": Time.get_ticks_msec() - started, "accepted_commands": operations.size(), "rejected_commands": rejected, "manual_supply_commands": manual_supplies, "supply_deliveries": deliveries, "mg_empty_station_seconds": snappedf(empty_seconds, 0.01), "mg_internal_supply_operator_seconds": snappedf(away_seconds, 0.01), "ally_friendly_fire_hits": ally_hits, "ally_friendly_fire_hp": ally_damage, "flanker_hits_on_defenders": flank_hits, "flanker_damage_on_defenders": flank_damage, "checkpoints": snapshots, "operations": operations.duplicate(true), "defender_damage_events": damage_events})
		summaries.append(result)
		var brief := result.duplicate(); brief.erase("operations"); brief.erase("defender_damage_events")
		print("PROFILE_RESULT ", JSON.stringify(brief))
		print("PROFILE_PROGRESS_FINISHED ", profile)
	DirAccess.make_dir_recursive_absolute("res://build/reports")
	var report_path := "res://build/reports/tactical_comparison_current.json" if profiles.size() > 1 else "res://build/reports/tactical_" + profiles[0] + "_current.json"
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(summaries, "\t")); file.close()
	print("PROFILE_RUN_FINISHED ", report_path)
	quit()

func _prepare(w, profile: String) -> void:
	_send(w, [1, 2, 3, 4, 5, 6], "posture", {"value": 1})
	_send(w, [1, 2, 3, 4, 5, 6], "style", {"value": 1})
	if profile == "rifles":
		guard_points = {1: Vector2(16.5, 21.5), 2: Vector2(20.5, 25.5), 3: Vector2(38.5, 21.5), 4: Vector2(44.5, 24.5), 5: Vector2(8.5, 25.5), 6: Vector2(10.5, 27.5)}
	else:
		roles = {1: 0, 2: 1}
		_send(w, [1, 2], "style", {"value": 0})
		if profile != "dual_mg": roles.merge({3: 2, 4: 2})
		else: guard_points.merge({3: Vector2(16.5, 21.5), 4: Vector2(39.5, 21.5)})
		guard_points.merge({5: Vector2(8.5, 25.5), 6: Vector2(10.5, 27.5)})
	if profile == "neglect_flank": guard_points.merge({5: Vector2(38.5, 21.5), 6: Vector2(44.5, 24.5)}, true)
	for id in roles: _send(w, [id], "operate", {"target_id": w.stations()[int(roles[id])].id})
	for id in guard_points: _send(w, [id], "move", {"position": guard_points[id]})
	_send(w, [5, 6], "style", {"value": 0})
	_send(w, [5, 6], "posture", {"value": 2})

func _command(w, profile: String) -> void:
	var active := false
	for enemy in w.units:
		if enemy.team == 1 and not enemy.dead and enemy.conscious: active = true; break
	var claimed: Array[int] = []
	for id in range(1, 7):
		var u: Dictionary = w.entity(id)
		if u.dead or not u.conscious or w.time_s < float(u.rout_until): continue
		if not u.drafted: _send(w, [id], "draft", {"value": true}); continue
		if care.has(id):
			if u.job == "idle" and u.bleed_rate <= 0:
				_send(w, [id], "posture", {"value": 2 if id >= 5 else 1})
				care.erase(id); _return(w, id)
			continue
		if u.bleed_rate > 0.05 and u.hp < (75.0 if active else 95.0) and u.bandages > 0 and not u.job in ["resupply", "rescue", "treat"]:
			if _send(w, [id], "treat", {"target_id": id}): _send(w, [id], "posture", {"value": 2}); care[id] = true; continue
		if roles.has(id):
			if u.job == "idle": _return(w, id)
			if id == 3 and not active and w.time_s > 60.0 and w.time_s < 130.0 and profile != "neglect_supply" and u.job == "operate": _try_supply(w, id, claimed)
			continue
		if u.job in ["resupply", "rescue", "treat"]: continue
		var patient: Dictionary = {}
		for other in w.units:
			if other.team != 0 or other.dead or other.conscious or other.bleed_rate <= 0.0 or other.rescue_owner >= 0: continue
			if patient.is_empty() or other.hp < patient.hp: patient = other
		if not patient.is_empty() and _send(w, [id], "rescue", {"target_id": patient.id}): continue
		if profile != "rifles" and profile != "neglect_supply" and not active and _try_supply(w, id, claimed): continue
		if u.job == "idle": _return(w, id)
	if profile != "neglect_flank" and w.time_s >= 36.0 and not prepared.has("right_guard"):
		prepared.right_guard = true; guard_points[6] = Vector2(38.5, 21.5)
		if not w.entity(6).job in ["resupply", "rescue", "treat"]: _return(w, 6)
	if profile != "neglect_flank" and w.time_s >= 72.0 and not prepared.has("left_guard"):
		prepared.left_guard = true; guard_points[5] = Vector2(16.5, 21.5)
		if not w.entity(5).job in ["resupply", "rescue", "treat"]: _return(w, 5)
	if profile not in ["rifles", "dual_mg"]: _mortar(w)

func _return(w, id: int) -> void:
	if roles.has(id):
		var station: Dictionary = w.stations()[int(roles[id])]
		if not station.destroyed: _send(w, [id], "operate", {"target_id": station.id})
	elif guard_points.has(id) and w.entity(id).pos.distance_to(guard_points[id]) > 0.1:
		# Formation allocation can shift an occupied requested centre. Treat the
		# accepted legal endpoint as arrival, instead of issuing a move every .25s.
		var allocated: Dictionary = move_allocations.get(id, {})
		if not allocated.is_empty() and allocated.requested == guard_points[id] and w.entity(id).pos.distance_to(allocated.actual) <= 0.1: return
		_send(w, [id], "move", {"position": guard_points[id]})

func _try_supply(w, id: int, claimed: Array[int]) -> bool:
	for station in w.stations():
		if station.kind != "mg" or station.destroyed or station.crew.is_empty() or claimed.has(int(station.id)): continue
		if station.loaded < 35 and station.ammo == 0 and station.supply_reserved == 0 and _send(w, [id], "resupply", {"target_id": station.id}): claimed.append(int(station.id)); return true
	return false

func _mortar(w) -> void:
	var mortar: Dictionary = w.stations()[2]
	if mortar.destroyed or mortar.crew.is_empty(): return
	for wave in [30.0, 150.0, 300.0]:
		if w.time_s >= wave - 11.0 and w.time_s < wave and not prepared.has(wave):
			var point := Vector2(0.6, 19.6) if wave == 300.0 else Vector2(13.6, 0.6)
			if _send(w, [mortar.crew[0]], "fire", {"target_id": mortar.id, "position": point}): prepared[wave] = true
	if mortar.fire_requested: return
	var best := Vector2.INF; var score := -INF
	for enemy in w.units:
		if enemy.team != 1 or enemy.dead or not enemy.conscious: continue
		var point: Vector2 = enemy.pos + enemy.velocity * 3.0
		point = point.clamp(Vector2(0.5, 0.5), Vector2(63.5, 47.5))
		if point.distance_to(mortar.pos) < 8.0 or point.distance_to(mortar.pos) > 40.0: continue
		var safe := true; var value := 0.0
		for u in w.units:
			if u.dead: continue
			if u.team == 0 and u.pos.distance_to(point) < 12.75: safe = false; break
			if u.team == 1: value += maxf(0.0, 1.0 - u.pos.distance_to(point) / 5.0)
		if safe and value > score: best = point; score = value
	if best != Vector2.INF: _send(w, [mortar.crew[0]], "fire", {"target_id": mortar.id, "position": best})

func _snapshot(w) -> Dictionary:
	var people: Array[Dictionary] = []; var alive := 0; var awake := 0; var enemies := 0
	for u in w.units:
		if u.team == 0:
			if not u.dead: alive += 1
			if not u.dead and u.conscious: awake += 1
			people.append({"id": u.id, "hp": snappedf(u.hp, 0.01), "dead": u.dead, "conscious": u.conscious, "job": u.job, "stage": u.stage, "pos": [u.pos.x, u.pos.y], "bleed": u.bleed_rate})
		elif not u.dead: enemies += 1
	return {"phase": w.phase, "time": snappedf(w.time_s, 0.01), "core_hp": w.core().hp, "alive": alive, "awake": awake, "living_enemies": enemies, "stats": w.stats.duplicate(true), "people": people, "state_hash": hash(var_to_bytes([w.time_s, w.units, w.buildings, w.supplies, w.projectiles, w.stats, w.rng.state]))}
