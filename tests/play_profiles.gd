extends SceneTree

const World = preload("res://scripts/sim/world.gd")
const Config = preload("res://scripts/sim/battle_config.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var profiles: Array[String] = ["rifles", "dual_mg", "siege", "neglect"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): profiles.assign([arg.trim_prefix("--profile=")])
	var summaries: Array[Dictionary] = []
	for profile in profiles:
		var started := Time.get_ticks_msec()
		var w = World.new()
		var stations: Array[Dictionary] = w.stations()
		var mg1: int = int(stations[0].id); var mg2: int = int(stations[1].id); var mortar: int = int(stations[2].id)
		w.submit([1, 2, 3, 4, 5, 6], "style", {"value": 0})
		w.submit([1, 2, 3, 4, 5, 6], "posture", {"value": 1})
		if profile == "rifles":
			var positions := [Vector2(15.5, 21.5), Vector2(20.5, 21.5), Vector2(38.5, 21.5), Vector2(44.5, 21.5), Vector2(12.5, 24.5), Vector2(26.5, 26.5)]
			for i in range(6): w.submit([i + 1], "move", {"position": positions[i]})
		else:
			w.submit([1], "operate", {"target_id": mg1}); w.submit([2], "operate", {"target_id": mg2})
			if profile == "siege":
				w.submit([3, 4], "operate", {"target_id": mortar})
			else:
				w.submit([3], "move", {"position": Vector2(16.5, 21.5)})
				w.submit([4], "move", {"position": Vector2(40.5, 21.5)})
			w.submit([5], "move", {"position": Vector2(16.5, 21.5)})
			w.submit([6], "move", {"position": Vector2(38.5, 21.5)})
		w.start_battle()
		var last_decision := -1
		var event_counts: Dictionary = {}
		var last_serial := 0
		var max_projectiles := 0
		while w.phase == "running" and w.step_index < 29000:
			var second := int(w.time_s)
			if second != last_decision:
				last_decision = second
				if profile != "neglect": _support_orders(w, profile)
				if profile == "siege" and second % 8 == 0: _mortar_order(w, mortar)
			w.step()
			max_projectiles = maxi(max_projectiles, w.projectiles.size())
			for event in w.events:
				if int(event.serial) <= last_serial: continue
				last_serial = int(event.serial)
				event_counts[event.type] = int(event_counts.get(event.type, 0)) + 1
		var people: Array[Dictionary] = []
		for u in w.units:
			if u.team == 0: people.append({"id": u.id, "hp": u.hp, "conscious": u.conscious, "dead": u.dead, "job": u.job, "pos": str(u.pos), "bleeding": u.bleed_rate})
		var result := {"profile": profile, "seed": Config.SEED, "phase": w.phase, "time": w.time_s, "core_hp": w.core().hp, "reason": w.result_reason, "stats": w.stats.duplicate(true), "people": people, "events": event_counts, "max_projectiles": max_projectiles, "wall_ms": Time.get_ticks_msec() - started}
		summaries.append(result)
		print("PROFILE_RESULT ", JSON.stringify(result))
	DirAccess.make_dir_recursive_absolute("res://build/reports")
	var file := FileAccess.open("res://build/reports/profiles.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(summaries, "\t")); file.close()
	print("PROFILE_RUN_FINISHED")
	quit()

func _support_orders(w, profile: String) -> void:
	# A reproducible commander using only legal public commands and visible state.
	for u in w.units:
		if u.team != 0 or u.dead or not u.conscious or w.time_s < float(u.rout_until): continue
		if bool(u.get("profile_care", false)):
			if u.job == "idle" and float(u.bleed_rate) <= 0.0:
				w.submit([u.id], "posture", {"value": 1})
				var previous: int = int(u.get("profile_station", -1))
				if previous >= 0: w.submit([u.id], "operate", {"target_id": previous})
				u.profile_care = false
			continue
		if u.bleed_rate > 0.0 and u.hp < 85.0 and u.bandages > 0 and not u.job in ["rescue", "treat", "resupply"]:
			u["profile_station"] = u.station_id
			if w.submit([u.id], "treat", {"target_id": u.id}).get("ok", false):
				w.submit([u.id], "posture", {"value": 2}); u["profile_care"] = true
	var helpers: Array = [5, 6] if profile == "siege" else ([3, 4, 5, 6] if profile == "dual_mg" else [5, 6])
	for id in helpers:
		var u: Dictionary = w.entity(id)
		if u.dead or not u.conscious or w.time_s < float(u.rout_until): continue
		if not u.drafted: w.submit([id], "draft", {"value": true}); continue
		if u.job in ["resupply", "rescue", "treat"]: continue
		var patient: Dictionary = {}
		for p in w.units:
			if p.team != 0 or p.dead or p.bleed_rate <= 0.0 or int(p.carrier_id) >= 0 or int(p.get("rescue_owner", -1)) >= 0: continue
			if p.hp > 70.0: continue
			var being_treated := false
			for medic in w.units:
				if medic.job in ["rescue", "treat"] and int(medic.rescued_id) == int(p.id): being_treated = true
			if being_treated: continue
			if patient.is_empty() or p.hp < patient.hp: patient = p
		if not patient.is_empty():
			var command := "treat" if patient.conscious else "rescue"
			if w.submit([id], command, {"target_id": patient.id}).get("ok", false): continue
		if profile in ["dual_mg", "siege"]:
			for b in w.stations():
				if b.kind == "mg" and b.loaded < 40 and b.ammo <= 100 and b.supply_reserved == 0:
					if w.submit([id], "resupply", {"target_id": b.id}).get("ok", false): break

func _mortar_order(w, mortar_id: int) -> void:
	var b: Dictionary = w.entity(mortar_id)
	if b.destroyed or b.fire_requested: return
	var best: Dictionary = {}; var best_score := -1
	for enemy in w.units:
		if enemy.team != 1 or enemy.dead or not enemy.conscious: continue
		var distance: float = enemy.pos.distance_to(b.pos)
		if distance < 8.0 or distance > 40.0: continue
		var safe := true; var score := 0
		for u in w.units:
			if u.dead: continue
			if u.team == 0 and u.pos.distance_to(enemy.pos) < 6.5: safe = false
			if u.team == 1 and not u.dead and u.pos.distance_to(enemy.pos) < 4.0: score += 1
		if safe and score > best_score: best = enemy; best_score = score
	if not best.is_empty(): w.submit([3], "fire", {"target_id": mortar_id, "position": best.pos})
