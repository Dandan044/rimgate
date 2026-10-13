extends "res://tests/play_profiles.gd"

# Commander-only search. A fresh unmodified World is constructed per profile.
# Every decision is submitted through the same validated public orders as UI.
var variant: String = "normal"

func _run() -> void:
	var variants: Array[String] = ["normal", "cautious_mg", "conservative"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): variants.assign([arg.trim_prefix("--profile=")])
	for selected in variants:
		variant=selected
		care.clear(); roles.clear(); guard_points.clear(); prepared.clear(); operations.clear(); move_allocations.clear(); rejected=0
		var world=World.new()
		_prepare_v3(world)
		world.start_battle()
		var started: int = Time.get_ticks_msec()
		var serial: int = 0
		var friendly_hits: int = 0
		var friendly_hp: float = 0.0
		var violations: int = 0
		var checkpoints: Array[Dictionary] = []
		while world.phase=="running" and world.step_index<28801:
			if world.step_index%15==0: _command(world,"siege")
			world.step()
			var occupied: Dictionary = {}
			for unit in world.units:
				if bool(unit.dead) or not bool(unit.conscious) or int(unit.carrier_id)>=0: continue
				var cell: Vector2i = Vector2i(Vector2(unit.pos).floor())
				if occupied.has(cell): violations+=1
				occupied[cell]=int(unit.id)
			for event in world.events:
				if int(event.serial)<=serial: continue
				serial=int(event.serial)
				if event.type=="damage" and int(event.get("team",-1))==0 and int(event.get("target_team",-1))==0 and world.entity(int(event.get("entity_id",-1))).has("team"):
					friendly_hits+=1; friendly_hp+=float(event.amount)
			if world.step_index%3600==0:
				var point: Dictionary = _snapshot(world); point.erase("people")
				checkpoints.append(point)
				print("V3_SEARCH_PROGRESS ",variant," ",JSON.stringify(point)," elapsed_ms=",Time.get_ticks_msec()-started)
		var report: Dictionary = _snapshot(world)
		report.merge({"profile":variant,"seed":Config.SEED,"ai_contract":"demo_v0.3_cover_intervals_pressure_reload","reason":world.result_reason,"operations":operations.duplicate(true),"accepted_commands":operations.size(),"rejected_commands":rejected,"occupancy_violations":violations,"ally_friendly_fire_hits":friendly_hits,"ally_friendly_fire_hp":friendly_hp,"checkpoints":checkpoints,"wall_ms":Time.get_ticks_msec()-started,"fixture":"fresh standard World; public commands only; no HP/inventory/damage/AI overrides"})
		DirAccess.make_dir_recursive_absolute("res://build/reports")
		var file:=FileAccess.open("res://build/reports/tactics_v3_"+variant+".json",FileAccess.WRITE)
		if file: file.store_string(JSON.stringify([report],"\t")); file.close()
		var summary: Dictionary = report.duplicate(); summary.erase("operations"); summary.erase("people"); summary.erase("checkpoints")
		print("V3_SEARCH_RESULT ",JSON.stringify(summary))
		if world.phase=="won" and rejected==0 and violations==0: break
	quit()

func _prepare_v3(world) -> void:
	if variant.begins_with("baseline_"):
		super._prepare(world,"siege")
		if variant=="baseline_normal": _send(world,[1,2],"style",{"value":1})
		if variant=="baseline_cautious": _send(world,[1,2],"style",{"value":2})
		return
	_send(world,[1,2,3,4,5,6],"posture",{"value":-1})
	_send(world,[1,2,3,4,5,6],"style",{"value":1})
	_send(world,[1,2,3,4,5,6],"target_policy",{"value":"priority"})
	roles={1:0,2:1,3:2,4:2}
	guard_points={5:Vector2(8.5,25.5),6:Vector2(10.5,27.5)}
	if variant=="cautious_mg": _send(world,[1,2],"style",{"value":2})
	if variant=="conservative": _send(world,[1,2,5,6],"style",{"value":2})
	for id in roles: _send(world,[id],"operate",{"target_id":world.stations()[int(roles[id])].id})
	for id in guard_points: _send(world,[id],"move",{"position":guard_points[id]})

func _mortar(world) -> void:
	if variant.begins_with("baseline_"):
		super._mortar(world); return
	var mortar: Dictionary = world.stations()[2]
	if mortar.destroyed or mortar.crew.is_empty(): return
	for wave in [30.0,150.0,300.0]:
		if world.time_s>=wave-7.0 and world.time_s<wave and not prepared.has(wave):
			if _send(world,[mortar.crew[0]],"fire",{"target_id":mortar.id,"position":Vector2(13.6,.6)}): prepared[wave]=true
	if mortar.fire_requested: return
	var delay: float = 7.0
	if int(mortar.loaded)<=0:
		var workers: int = 0
		for id in mortar.crew:
			var crew: Dictionary = world.entity(int(id))
			if String(crew.stage)=="station" and world.unit_system.can_act(world,crew,"operate").ok: workers+=1
		delay+=(10.0-float(mortar.reload_progress))/(2.5 if workers>=2 else 1.0)
	var point: Vector2 = _v3_lead(world,mortar,delay)
	if point!=Vector2.INF: _send(world,[mortar.crew[0]],"fire",{"target_id":mortar.id,"position":point})

func _v3_lead(world, mortar: Dictionary, delay: float) -> Vector2:
	var best: Vector2 = Vector2.INF
	var highest: float = .1
	for enemy in world.units:
		if enemy.team!=1 or enemy.dead or not enemy.conscious: continue
		var point: Vector2 = _forecast_v3(enemy,delay)
		if point.distance_to(mortar.pos)<8.0 or point.distance_to(mortar.pos)>40.0: continue
		var safe: bool = true
		var value: float = 0.0
		for unit in world.units:
			if unit.dead: continue
			if unit.team==0 and Vector2(unit.pos).distance_to(point)<12.75: safe=false; break
			if unit.team==1 and unit.conscious: value+=maxf(0.0,1.0-_forecast_v3(unit,delay).distance_to(point)/4.0)*(1.5 if unit.kind=="heavy" else 1.0)
		if safe and value>highest: best=point; highest=value
	return best

func _forecast_v3(unit: Dictionary, horizon: float) -> Vector2:
	var position: Vector2 = unit.pos
	if bool(unit.get("cower",false)) or float(unit.posture_timer)>0.0: return position
	var budget: float = horizon*float(unit.move_speed)*float(Config.POSTURE_SPEED[int(unit.posture)])
	for index in range(int(unit.path_index),unit.path.size()):
		var point: Vector2 = unit.path[index]
		var distance: float = position.distance_to(point)
		if distance>budget: return position.move_toward(point,budget)
		position=point; budget-=distance
	return position
