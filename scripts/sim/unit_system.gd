extends RefCounted

const C = preload("res://scripts/sim/battle_config.gd")
var navigation := AStarGrid2D.new()
var nav_revision: int = 0
var arrival_serial: int = 0
const SETTINGS := ["posture", "style"]
const ACTIONS := ["move", "attack", "stop", "draft", "operate", "resupply", "fire", "rescue", "treat"]

func setup(world) -> void:
	arrival_serial = 0
	for u in world.units: _init_unit(u)
	rebuild_navigation(world)

func _init_unit(u: Dictionary) -> void:
	if u.has("nav_revision"): return
	u["nav_revision"] = -1; u["arrival_order"] = 2147483647
	u["supply_target"] = -1; u["internal_supply"] = false; u["rescue_owner"] = -1
	u["treatment_reserved"] = false; u["treatment_source"] = ""; u["ai_next"] = 0.0
	u["blocked_time"] = 0.0; u["rout_latched"] = false; u["flank_done"] = false
	u["progress_point"] = Vector2.INF; u["progress_distance"] = INF
	u["ai_destination"] = Vector2(-1, -1)

func rebuild_navigation(world) -> void:
	navigation.region = Rect2i(Vector2i.ZERO, C.MAP_SIZE)
	navigation.cell_size = Vector2.ONE; navigation.offset = Vector2(0.5, 0.5)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.jumping_enabled = false; navigation.update()
	for b in world.buildings:
		if b.destroyed or float(b.hp) <= 0: continue
		for y in range(b.rect.position.y, b.rect.end.y):
			for x in range(b.rect.position.x, b.rect.end.x):
				if b.high: navigation.set_point_solid(Vector2i(x, y), true)
				else: navigation.set_point_weight_scale(Vector2i(x, y), 3.0)
	nav_revision += 1

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))

func _inside(p: Vector2) -> bool:
	return p.x >= 0.25 and p.y >= 0.25 and p.x < C.MAP_SIZE.x - 0.25 and p.y < C.MAP_SIZE.y - 0.25

func _can_stand(world, p: Vector2) -> bool:
	if not _inside(p): return false
	return world.building_at(_cell(p)).is_empty()

func _can_walk(world, p: Vector2) -> bool:
	if not _inside(p): return false
	for b in world.buildings:
		if b.destroyed or float(b.hp) <= 0 or not b.high: continue
		var rect := Rect2(Vector2(b.rect.position), Vector2(b.rect.size)).grow(0.18)
		if rect.has_point(p): return false
	return true

func _reachable(from: Vector2, to: Vector2) -> bool:
	var a: Vector2i = _cell(from); var b: Vector2i = _cell(to)
	if not navigation.region.has_point(a) or not navigation.region.has_point(b): return false
	if navigation.is_point_solid(a) or navigation.is_point_solid(b): return false
	return not navigation.get_id_path(a, b).is_empty()

func _projection(world) -> Dictionary:
	var p := {"tasks": {}, "crates": {}, "med": {}, "patients": {}}
	for u in world.units:
		p.tasks[int(u.id)] = {"station": int(u.station_id), "crate": int(u.crate_id), "medical": int(u.medical_slot), "patient": int(u.rescued_id), "drafted": bool(u.drafted), "supply_target": int(u.get("supply_target", -1))}
	for s in world.supplies:
		if not s.delivered: p.crates[int(s.id)] = int(s.carried_by) if int(s.carried_by) >= 0 else int(s.reserved_by)
	for key in world.medical_reservations: p.med[int(key)] = int(world.medical_reservations[key])
	for u in world.units:
		if int(u.get("rescue_owner", -1)) >= 0: p.patients[int(u.id)] = int(u.rescue_owner)
	for order in world.pending_orders:
		var kind: String = order.kind
		if kind in SETTINGS or kind == "fire": continue
		for id in order.ids:
			if not p.tasks.has(int(id)): continue
			if kind == "attack" and int(p.tasks[int(id)].station) >= 0: continue
			if kind == "draft" and bool(order.data.get("value", true)):
				p.tasks[int(id)].drafted = true; continue
			_project_release(p, int(id))
			if kind == "draft": p.tasks[int(id)].drafted = bool(order.data.get("value", true))
			var alloc: Dictionary = order.data.get("_allocations", {}).get(int(id), {})
			if kind == "operate": p.tasks[int(id)].station = int(order.data.target_id)
			if kind == "resupply" and not alloc.is_empty():
				p.tasks[int(id)].crate = int(alloc.get("crate", -1)); p.tasks[int(id)].supply_target = int(order.data.target_id)
				p.crates[int(alloc.get("crate", -1))] = int(id)
			if kind == "rescue" and not alloc.is_empty():
				p.tasks[int(id)].medical = int(alloc.get("medical", -1)); p.tasks[int(id)].patient = int(order.data.target_id)
				p.med[int(alloc.get("medical", -1))] = int(id); p.patients[int(order.data.target_id)] = int(id)
	return p

func _project_release(p: Dictionary, id: int) -> void:
	if not p.tasks.has(id): return
	for key in p.crates.keys():
		if int(p.crates[key]) == id: p.crates[key] = -1
	for key in p.med.keys():
		if int(p.med[key]) == id: p.med.erase(key)
	for key in p.patients.keys():
		if int(p.patients[key]) == id: p.patients.erase(key)
	p.tasks[id].station = -1; p.tasks[id].crate = -1; p.tasks[id].medical = -1; p.tasks[id].patient = -1; p.tasks[id].supply_target = -1

func validate_order(world, ids: Array, kind: String, data: Dictionary) -> Dictionary:
	if not kind in ACTIONS and not kind in SETTINGS: return _bad("未知命令")
	if ids.is_empty(): return _bad("请先选择可控制人员")
	var projection: Dictionary = _projection(world)
	var allocations: Dictionary = {}; var selected: Array[int] = []
	for raw_id in ids:
		var id := int(raw_id); var u: Dictionary = world.entity(id)
		if u.is_empty() or not u.has("team") or u.team != 0: return _bad("只能指挥己方人员")
		if u.dead or not u.conscious or int(u.carrier_id) >= 0: return _bad("该人员无法行动")
		if selected.has(id): continue
		selected.append(id)
		if kind == "draft":
			if bool(data.get("value", true)) and float(u.rout_until) > world.time_s: return _bad("溃逃冷却期间无法征召")
		elif not bool(projection.tasks[id].drafted): return _bad("需要先征召人员")
	selected.sort()
	if kind == "posture" and not int(data.get("value", -2)) in [-1, 0, 1, 2]: return _bad("姿态无效")
	if kind == "style" and not int(data.get("value", -1)) in [0, 1, 2]: return _bad("作战风格无效")
	if kind in SETTINGS or kind in ["stop", "draft"]: return {"ok": true, "reason": ""}
	if kind == "move":
		if not data.get("position") is Vector2: return _bad("缺少移动位置")
		var goals: Array[Vector2] = _group_goals(world, selected, data.position)
		if goals.size() != selected.size(): return _bad("落点无法通行或没有足够空间")
		for i in range(selected.size()):
			if not _reachable(world.entity(selected[i]).pos, goals[i]): return _bad("没有可达路径")
			allocations[selected[i]] = {"goal": goals[i]}
	elif kind == "attack":
		var target: Dictionary = world.entity(int(data.get("target_id", -1)))
		if target.is_empty() or bool(target.get("dead", false)) or bool(target.get("destroyed", false)): return _bad("攻击目标无效")
		for id in selected:
			var shooter: Dictionary = world.entity(id).duplicate()
			if int(shooter.posture_mode) < 0: shooter.posture = 0
			if int(projection.tasks[id].station) >= 0:
				var station: Dictionary = world.entity(int(projection.tasks[id].station))
				if station.kind == "mortar": return _bad("迫击炮请使用地面轰击")
				var delta: Vector2 = target.pos - station.pos
				if delta.length() > 32.0 or absf(wrapf(delta.angle() - float(station.facing), -PI, PI)) > float(station.arc) * 0.5: return _bad("目标在机枪射程或射界之外")
				shooter.pos = station.crew_points[0]
			elif shooter.pos.distance_to(target.pos) > 24.0: return _bad("目标在步枪射程之外")
			if not world.combat_system.has_line_of_fire(world, shooter, target): return _bad("目标被墙体或当前姿态遮挡")
	elif kind == "operate":
		var b: Dictionary = world.entity(int(data.get("target_id", -1)))
		if b.is_empty() or not b.has("capacity") or int(b.capacity) < 1 or b.destroyed or b.hp <= 0: return _bad("该设施不能操作")
		for id in selected: _project_release(projection, id)
		var count := 0
		for task in projection.tasks.values():
			if int(task.station) == int(b.id): count += 1
		if count + selected.size() > int(b.capacity): return _bad("工事岗位已满")
		for id in selected:
			var point: Vector2 = b.crew_points[mini(count, b.crew_points.size() - 1)]
			if not _reachable(world.entity(id).pos, point): return _bad("无法到达操作点")
			allocations[id] = {"goal": point}; projection.tasks[id].station = int(b.id); count += 1
	elif kind == "resupply":
		var b: Dictionary = world.entity(int(data.get("target_id", -1)))
		if b.is_empty() or not b.has("capacity") or int(b.capacity) < 1 or b.destroyed or b.hp <= 0: return _bad("无效补给目标")
		for id in selected: _project_release(projection, id)
		var reserved := _project_supply_amount(world, projection, int(b.id))
		for id in selected:
			var crate: Dictionary = _available_crate(world, world.entity(id).pos, b, projection.crates)
			if crate.is_empty(): return _bad("没有可达弹药箱")
			if int(b.ammo) + reserved + int(crate.amount) > int(b.ammo_capacity): return _bad("没有完整一箱的剩余容量")
			var delivery: Vector2 = _approach_position(world, world.entity(id).pos, b)
			if delivery.x < 0 or not _reachable(crate.pos, delivery): return _bad("无法到达交付点")
			allocations[id] = {"crate": int(crate.id), "delivery": delivery}
			projection.crates[int(crate.id)] = id; projection.tasks[id].crate = int(crate.id); projection.tasks[id].supply_target = int(b.id)
			reserved += int(crate.amount)
	elif kind == "fire":
		var b: Dictionary = world.entity(int(data.get("target_id", -1)))
		if b.is_empty() or b.get("kind", "") != "mortar" or b.destroyed or b.hp <= 0: return _bad("请选择可用迫击炮")
		if not data.get("position") is Vector2 or not _inside(data.position): return _bad("炮击位置超出地图")
		var distance: float = b.pos.distance_to(data.position)
		if distance < 8.0 or distance > 40.0: return _bad("炮击位置必须在8至40格之间")
		var has_crew := false
		for id in selected:
			if int(projection.tasks[id].station) == int(b.id): has_crew = true
		if not has_crew: return _bad("需要先安排迫击炮操作员")
	elif kind in ["rescue", "treat"]:
		if selected.size() != 1: return _bad("一次请选择一名救护人员")
		var id: int = selected[0]; var u: Dictionary = world.entity(id)
		var patient: Dictionary = world.entity(int(data.get("target_id", -1)))
		if patient.is_empty() or not patient.has("team") or patient.team != 0 or patient.dead: return _bad("救护目标无效")
		if int(patient.carrier_id) >= 0: return _bad("伤员正在被搬运")
		_project_release(projection, id)
		if kind == "rescue":
			if patient.conscious or int(patient.id) == id: return _bad("只能救援昏迷伤员")
			if int(projection.patients.get(int(patient.id), -1)) >= 0: return _bad("伤员已被其他人预约")
			var slot := _available_medical_slot(world, u.pos, projection.med, id)
			if slot < 0: return _bad("没有可达救护位置")
			var approach := _near_unit_position(world, u.pos, patient)
			if approach.x < 0 or not _reachable(u.pos, approach): return _bad("无法接近伤员")
			allocations[id] = {"medical": slot, "goal": approach}
		else:
			if float(patient.bleed_rate) <= 0: return _bad("目标不需要止血")
			if int(u.bandages) <= 0 and (not C.MEDICAL_RECT.has_point(patient.pos) or world.medical_stock <= 0): return _bad("没有可用绷带")
			var approach := _near_unit_position(world, u.pos, patient)
			if approach.x < 0 or not _reachable(u.pos, approach): return _bad("无法接近伤员")
			allocations[id] = {"goal": approach}
	data["_allocations"] = allocations
	return {"ok": true, "reason": ""}

func _bad(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

func _project_supply_amount(world, p: Dictionary, station: int) -> int:
	var count := 0
	for task in p.tasks.values():
		if int(task.get("crate", -1)) >= 0 and int(task.get("supply_target", -1)) == station:
			var crate := _crate(world, int(task.crate))
			if not crate.is_empty(): count += int(crate.amount)
	return count

func _group_goals(world, ids: Array[int], clicked: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not _can_stand(world, clicked): return result
	var candidates: Array[Vector2] = [clicked]
	for ring in range(1, 9):
		for i in range(ring * 8): candidates.append(clicked + Vector2.from_angle(TAU * i / float(ring * 8)) * ring * 0.7)
	for point in candidates:
		if not _can_stand(world, point): continue
		var free := true
		for taken in result:
			if taken.distance_to(point) < 0.52: free = false; break
		for u in world.units:
			if not ids.has(int(u.id)) and u.conscious and not u.dead and u.pos.distance_to(point) < 0.48: free = false; break
		if free: result.append(point)
		if result.size() >= ids.size(): break
	return result

func apply_order(world, ids: Array, kind: String, data: Dictionary) -> void:
	var sorted_ids := ids.duplicate(); sorted_ids.sort()
	for raw_id in sorted_ids:
		var u: Dictionary = world.entity(int(raw_id))
		if u.is_empty() or u.dead or not u.conscious: continue
		_init_unit(u)
		var alloc: Dictionary = data.get("_allocations", {}).get(int(u.id), {})
		if kind == "posture":
			u.posture_mode = int(data.value)
			if u.posture_mode >= 0 and not u.forced_prone: _change_posture(u, int(u.posture_mode))
			continue
		if kind == "style": u.style = int(data.value); continue
		if kind == "fire":
			var b: Dictionary = world.entity(int(data.target_id))
			if not b.is_empty() and int(u.station_id) == int(b.id): b.fire_point = data.position; b.fire_requested = true
			continue
		if kind == "attack" and int(u.station_id) >= 0:
			var b: Dictionary = world.entity(int(u.station_id))
			if not b.is_empty() and b.kind == "mg": b.target_id = int(data.target_id)
			continue
		if kind == "draft" and bool(data.get("value", true)):
			if world.time_s >= float(u.rout_until):
				u.drafted = true
				if u.job in ["rout", "flee"]: _cancel_job(world, u)
			continue
		var keep_reload: bool = kind in ["move", "attack"] and not String(u.job) in ["operate", "resupply", "rescue", "treat", "rout"] and u.drafted
		var saved_reload: float = float(u.reload_progress)
		var saved_reservation: int = int(u.reload_reserved)
		_cancel_job(world, u)
		if keep_reload: u.reload_progress = saved_reload; u.reload_reserved = saved_reservation
		match kind:
			"draft": u.drafted = false; u.status = "未征召"
			"move":
				u.job = "move"; u.status = "移动"
				_start_path(world, u, alloc.get("goal", data.position))
			"attack": u.target_id = int(data.target_id); u.status = "指定攻击"
			"operate":
				var b: Dictionary = world.entity(int(data.target_id))
				if b.is_empty() or b.destroyed or b.crew.size() >= int(b.capacity): _reject(world, u, "岗位已不可用"); continue
				u.job = "operate"; u.stage = "approach_station"; u.station_id = int(b.id); u.arrival_order = 2147483647
				b.crew.append(int(u.id)); u.status = "前往岗位"
				var point: Vector2 = alloc.get("goal", b.crew_points[mini(b.crew.size() - 1, b.crew_points.size() - 1)])
				_start_path(world, u, point)
				world.emit_event("station_changed", {"entity_id": b.id, "unit_id": u.id})
			"resupply":
				u.job = "resupply"
				if not _begin_supply(world, u, world.entity(int(data.target_id)), false, int(alloc.get("crate", -1)), alloc.get("delivery", Vector2(-1, -1))): _reject(world, u, "补给预约已失效")
			"rescue":
				var patient: Dictionary = world.entity(int(data.target_id)); var slot := int(alloc.get("medical", -1))
				if patient.is_empty() or slot < 0 or world.medical_reservations.has(slot) or int(patient.get("rescue_owner", -1)) >= 0: _reject(world, u, "救护预约已失效"); continue
				u.job = "rescue"; u.stage = "approach_patient"; u.rescued_id = int(patient.id); u.medical_slot = slot
				patient.rescue_owner = int(u.id); world.medical_reservations[slot] = int(u.id)
				u.status = "接近伤员"; _start_path(world, u, alloc.get("goal", patient.pos))
			"treat":
				u.job = "treat"; u.stage = "approach_patient"; u.rescued_id = int(data.target_id)
				u.status = "准备急救"; _start_path(world, u, alloc.get("goal", world.entity(int(data.target_id)).pos))
			"stop": u.status = "待命"

func _cancel_job(world, u: Dictionary) -> void:
	release_station(world, u); _release_supply(world, u); _drop_patient(world, u); _release_medical(world, u)
	u.job = "idle"; u.stage = ""; u.path = PackedVector2Array(); u.path_index = 0; u.goal = u.pos
	u.target_id = -1; u.rescued_id = -1; u.job_timer = 0.0; u.velocity = Vector2.ZERO
	u.reload_progress = 0.0; u.reload_reserved = 0; u.burst_left = 0; u.treatment_reserved = false; u.treatment_source = ""
	u.status = "待命" if u.drafted or u.team == 1 else "未征召"

func release_station(world, u: Dictionary) -> void:
	var id: int = int(u.station_id)
	if id < 0: return
	var b: Dictionary = world.entity(id)
	if not b.is_empty():
		var was_gunner: bool = not b.crew.is_empty() and int(b.crew[0]) == int(u.id)
		b.crew.erase(int(u.id))
		if b.kind == "mg": b.reload_progress = 0.0; b.reload_reserved = 0; b.burst_left = 0
		if was_gunner: b.aim_progress = 0.0
		if b.crew.is_empty(): b.reload_progress = 0.0; b.reload_reserved = 0; b.aim_progress = 0.0; b.fire_requested = false; b.target_id = -1
		world.emit_event("station_changed", {"entity_id": b.id, "unit_id": u.id})
		if was_gunner and not b.crew.is_empty(): _reposition_station_crew(world, b)
	u.station_id = -1; u.arrival_order = 2147483647

func _reposition_station_crew(world, b: Dictionary) -> void:
	# Only changed roles move. Stable gunner/loader positions keep their work intact.
	var crew: Array = b.crew.duplicate()
	for index in range(crew.size()):
		var member: Dictionary = world.entity(int(crew[index]))
		if member.is_empty() or not String(member.stage) in ["station", "approach_station", "return_station"]: continue
		var point: Vector2 = b.crew_points[mini(index, b.crew_points.size() - 1)]
		if member.goal.distance_to(point) < 0.02 and (not member.path.is_empty() or member.pos.distance_to(point) < 0.05): continue
		if not _reachable(member.pos, point): _reject(world, member, "操作点无法到达"); continue
		member.stage = "approach_station"; member.status = "调整操作岗位"
		_start_path(world, member, point)

func _crate(world, id: int) -> Dictionary:
	for s in world.supplies:
		if int(s.id) == id: return s
	return {}

func _available_crate(world, from: Vector2, b: Dictionary, owners: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}; var distance := INF
	var kind: String = "mg_ammo" if b.kind == "mg" else "mortar_ammo"
	for s in world.supplies:
		var owner: int = int(owners.get(int(s.id), s.reserved_by))
		# A projected cancellation can release a currently carried box before pickup.
		if s.delivered or s.kind != kind or owner >= 0: continue
		if int(s.carried_by) >= 0 and not owners.has(int(s.id)): continue
		var d: float = from.distance_squared_to(s.pos)
		if d < distance and _reachable(from, s.pos): result = s; distance = d
	return result

func _begin_supply(world, u: Dictionary, b: Dictionary, internal: bool, crate_id: int = -1, delivery: Vector2 = Vector2(-1, -1)) -> bool:
	if b.is_empty() or b.destroyed or b.hp <= 0: return false
	var s: Dictionary = _crate(world, crate_id) if crate_id >= 0 else _available_crate(world, u.pos, b)
	if s.is_empty() or s.delivered or int(s.carried_by) >= 0 or int(s.reserved_by) >= 0: return false
	if int(b.ammo) + int(b.supply_reserved) + int(s.amount) > int(b.ammo_capacity): return false
	if delivery.x < 0: delivery = _approach_position(world, s.pos, b)
	if delivery.x < 0 or not _reachable(s.pos, delivery): return false
	s.reserved_by = int(u.id); b.supply_reserved += int(s.amount)
	u.crate_id = int(s.id); u.supply_target = int(b.id); u.internal_supply = internal; u["delivery_point"] = delivery
	u.stage = "supply_pickup"; u.status = "取弹药箱"
	if not internal: u.job = "resupply"
	return _start_path(world, u, s.pos)

func _release_supply(world, u: Dictionary) -> void:
	var s: Dictionary = _crate(world, int(u.crate_id))
	if not s.is_empty():
		var b: Dictionary = world.entity(int(u.get("supply_target", -1)))
		if not b.is_empty(): b.supply_reserved = maxi(0, int(b.supply_reserved) - int(s.amount))
		if int(s.carried_by) == int(u.id): s.pos = _nearest_stand(world, u.pos); s.carried_by = -1
		if int(s.reserved_by) == int(u.id): s.reserved_by = -1
	u.crate_id = -1; u.supply_target = -1; u.internal_supply = false

func _available_medical_slot(world, from: Vector2, reservations: Dictionary, ignore_id: int = -1) -> int:
	var result := -1; var best := INF
	for i in range(world.medical_slots.size()):
		if reservations.has(i): continue
		var point: Vector2 = world.medical_slots[i]; var occupied := false
		for patient in world.units:
			if int(patient.id) != ignore_id and not patient.dead and int(patient.carrier_id) < 0 and patient.pos.distance_to(point) < 0.45: occupied = true; break
		var d: float = point.distance_squared_to(from)
		if not occupied and d < best and _reachable(from, point): result = i; best = d
	return result

func _release_medical(world, u: Dictionary) -> void:
	if int(u.medical_slot) >= 0 and int(world.medical_reservations.get(int(u.medical_slot), -1)) == int(u.id): world.medical_reservations.erase(int(u.medical_slot))
	u.medical_slot = -1
	var patient: Dictionary = world.entity(int(u.rescued_id))
	if not patient.is_empty() and int(patient.get("rescue_owner", -1)) == int(u.id): patient.rescue_owner = -1

func _drop_patient(world, u: Dictionary) -> void:
	var patient: Dictionary = world.entity(int(u.rescued_id))
	if not patient.is_empty() and int(patient.get("carrier_id", -1)) == int(u.id): patient.pos = _nearest_stand(world, u.pos); patient.prev_pos = patient.pos; patient.carrier_id = -1

func _near_unit_position(world, from: Vector2, patient: Dictionary) -> Vector2:
	if from.distance_to(patient.pos) < 0.75 and _can_stand(world, from): return from
	var best := Vector2(-1, -1); var distance := INF
	for i in range(12):
		var p: Vector2 = patient.pos + Vector2.from_angle(i * TAU / 12.0) * 0.58
		var d: float = p.distance_squared_to(from)
		if _can_stand(world, p) and d < distance and _reachable(from, p): best = p; distance = d
	return best

func _approach_position(world, from: Vector2, b: Dictionary) -> Vector2:
	var best := Vector2(-1, -1); var distance := INF
	for y in range(b.rect.position.y - 1, b.rect.end.y + 1):
		for x in range(b.rect.position.x - 1, b.rect.end.x + 1):
			var p := Vector2(x + 0.5, y + 0.5); var d: float = p.distance_squared_to(from)
			if _can_stand(world, p) and d < distance and _reachable(from, p): best = p; distance = d
	return best

func _nearest_stand(world, position: Vector2) -> Vector2:
	var base := Vector2(clampf(position.x, 0.3, 63.7), clampf(position.y, 0.3, 47.7))
	if _can_stand(world, base): return base
	for ring in range(1, 12):
		for i in range(ring * 8):
			var p := base + Vector2.from_angle(i * TAU / float(ring * 8)) * ring * 0.35
			if _can_stand(world, p): return p
	return base

func _start_path(world, u: Dictionary, goal: Vector2) -> bool:
	if not _can_stand(world, goal) or not _reachable(u.pos, goal): _reject(world, u, "没有可达路径"); return false
	u.goal = goal; u.path = navigation.get_point_path(_cell(u.pos), _cell(goal))
	# The first grid point is the current cell, not a required waypoint. Walking
	# back to its centre can deadlock against a stationary operator in that cell.
	u.path_index = 1 if u.path.size() > 1 else 0; u.nav_revision = nav_revision; u.blocked_time = 0.0
	u.progress_point = Vector2.INF; u.progress_distance = INF
	if not u.path.is_empty(): u.path[u.path.size() - 1] = goal
	return true

func _reject(world, u: Dictionary, reason: String) -> void:
	_cancel_job(world, u); u.status = reason
	world.emit_event("order_rejected", {"unit_id": u.id, "reason": reason})

func _finish_job(world, u: Dictionary, text: String = "待命") -> void:
	var old_job: String = u.job
	var reload_progress: float = float(u.reload_progress)
	var reload_reserved: int = int(u.reload_reserved)
	_cancel_job(world, u); u.status = text
	if old_job == "move": u.reload_progress = reload_progress; u.reload_reserved = reload_reserved
	world.emit_event("order_completed", {"unit_id": u.id, "job": old_job})

func _change_posture(u: Dictionary, value: int) -> void:
	if int(u.posture) == value: return
	u.posture_timer = absf(float(u.posture) - value) * 0.35
	u.posture = value; u.stability = 0.0

func _ensure_unit(u: Dictionary) -> void:
	_init_unit(u)

func update(world, dt: float) -> void:
	for u in world.units:
		_init_unit(u)
		u.prev_pos = u.pos; u.velocity = Vector2.ZERO
		if u.dead: continue
		# A terminal HP value must be observed before natural recovery can run.
		if float(u.hp) <= 0.0:
			_update_life(world, u)
			continue
		if float(u.bleed_rate) > 0: u.hp = maxf(0.0, float(u.hp) - float(u.bleed_rate) * dt)
		else: u.hp = minf(float(u.max_hp), float(u.hp) + 0.001 * dt)
		_update_life(world, u)
		if u.dead or not u.conscious: continue
		u.posture_timer = maxf(0.0, float(u.posture_timer) - dt)
		if world.time_s - float(u.last_threat) >= 2.0: u.suppression = maxf(0.0, float(u.suppression) - 10.0 * dt)
		_update_pressure(world, u)
	for u in world.units:
		if u.dead or not u.conscious or int(u.carrier_id) >= 0: continue
		if u.job == "rout":
			if world.time_s >= float(u.rout_until) and (u.team == 0 or float(u.suppression) < 40.0):
				u.job = "idle"; u.path = PackedVector2Array(); u.status = "未征召" if u.team == 0 else "重新推进"
				u.ai_next = 0.0
		elif u.team == 1 and world.time_s >= float(u.ai_next):
			u.ai_next = world.time_s + 0.25; _enemy_ai(world, u)
		elif u.team == 0 and not u.drafted and world.time_s >= float(u.ai_next):
			u.ai_next = world.time_s + 0.25; _standby_ai(world, u)
		if not u.forced_prone:
			_move(world, u, dt)
			if float(u.posture_timer) <= 0.0: _work(world, u, dt)
		_auto_posture(world, u)
		var q: float = float(u.suppression) / 100.0
		var cap: float = (1.0 - 0.5 * q) * (0.2 if u.velocity.length_squared() > 0.0001 else 1.0)
		var rate: float = 0.5 * float(C.STYLE_RECOVERY[int(u.style)]) * (1.0 - 0.65 * q)
		u.stability = minf(cap, float(u.stability) + rate * dt)
		if u.forced_prone or float(u.posture_timer) > 0.0: u.stability = 0.0
	for s in world.supplies:
		if int(s.carried_by) >= 0:
			var carrier: Dictionary = world.entity(int(s.carried_by))
			if not carrier.is_empty(): s.pos = carrier.pos
	for u in world.units:
		if int(u.carrier_id) >= 0:
			var carrier: Dictionary = world.entity(int(u.carrier_id))
			if not carrier.is_empty(): u.pos = carrier.pos; u.velocity = carrier.velocity

func finalize(world) -> void:
	for u in world.units:
		_init_unit(u)
		_update_life(world, u)
		if not u.dead and u.conscious: _update_pressure(world, u)
		if int(u.station_id) >= 0:
			var b: Dictionary = world.entity(int(u.station_id))
			if b.is_empty() or b.destroyed or b.hp <= 0: _cancel_job(world, u)

func _update_life(world, u: Dictionary) -> void:
	if u.dead: return
	if float(u.hp) <= 0.0:
		u.hp = 0.0; u.dead = true; u.conscious = false
		_cancel_job(world, u); u.status = "阵亡"; u.posture = 2
		if int(u.carrier_id) >= 0:
			var carrier: Dictionary = world.entity(int(u.carrier_id))
			if not carrier.is_empty(): _cancel_job(world, carrier)
			u.carrier_id = -1
		world.emit_event("unit_state_changed", {"unit_id": u.id, "state": "dead", "pos": u.pos})
	elif u.conscious and float(u.hp) < float(u.max_hp) * 0.25:
		u.conscious = false; _cancel_job(world, u); u.posture = 2; u.status = "昏迷"; u.stability = 0.0
		world.emit_event("unit_state_changed", {"unit_id": u.id, "state": "unconscious", "pos": u.pos})
	elif not u.conscious and float(u.hp) > float(u.max_hp) * 0.35:
		u.conscious = true; u.status = "已苏醒"; u.drafted = false; u.ai_next = 0.0
		world.emit_event("unit_state_changed", {"unit_id": u.id, "state": "awake", "pos": u.pos})

func _update_pressure(world, u: Dictionary) -> void:
	u.suppression = clampf(float(u.suppression), 0.0, 100.0)
	if float(u.suppression) < 60.0: u.rout_latched = false
	if float(u.suppression) >= 100.0 and not u.rout_latched:
		u.rout_latched = true; _start_rout(world, u); return
	if u.job == "rout": return
	if float(u.suppression) >= 60.0 and not u.forced_prone:
		u.forced_prone = true; u.forced_until = world.time_s + 1.5
		_change_posture(u, 2); u.stability = 0.0; u.status = "受压制伏低"
		world.emit_event("unit_state_changed", {"unit_id": u.id, "state": "suppressed"})
	elif u.forced_prone and world.time_s >= float(u.forced_until) and float(u.suppression) < 40.0:
		u.forced_prone = false
		if int(u.posture_mode) >= 0: _change_posture(u, int(u.posture_mode))

func _start_rout(world, u: Dictionary) -> void:
	_cancel_job(world, u)
	u.drafted = false; u.rout_until = world.time_s + 10.0; u.forced_prone = false; u.forced_until = 0.0
	u.job = "rout"; u.status = "溃逃"; _change_posture(u, 0)
	var destination := _escape_goal(world, u)
	if destination.x >= 0: _start_path(world, u, destination)
	world.emit_event("unit_state_changed", {"unit_id": u.id, "state": "routed", "until": u.rout_until})

func _escape_goal(world, u: Dictionary) -> Vector2:
	var choices: Array[Vector2] = []
	if u.team == 0:
		for point in world.medical_slots: choices.append(point)
	else:
		var home := Vector2(clampf(u.spawn_entry.x, 0.5, 63.5), clampf(u.spawn_entry.y, 0.5, 47.5))
		if _can_stand(world, home) and _reachable(u.pos, home): return home
		choices.append(Vector2(12.5, 0.5)); choices.append(Vector2(47.5, 0.5)); choices.append(Vector2(0.5, 21.5))
	var best := Vector2(-1, -1); var distance := INF
	for point in choices:
		var d: float = u.pos.distance_squared_to(point)
		if _can_stand(world, point) and d < distance and _reachable(u.pos, point): best = point; distance = d
	if best.x >= 0: return best
	var threat := _nearest_opponent(world, u)
	var away: Vector2 = (u.pos - threat.pos).normalized() if not threat.is_empty() else Vector2.UP
	for radius in [8.0, 5.0, 2.0]:
		for i in range(16):
			var candidate: Vector2 = u.pos + away.rotated((i / 2 + 1) * (1.0 if i % 2 == 0 else -1.0) * 0.2) * radius
			if _can_stand(world, candidate) and _reachable(u.pos, candidate): return candidate
	return _nearest_stand(world, u.pos)

func _standby_ai(world, u: Dictionary) -> void:
	if world.time_s < float(u.rout_until): return
	var threat := _nearest_opponent(world, u)
	if not threat.is_empty() and (u.pos.distance_to(threat.pos) < 16.0 or world.time_s - float(u.last_threat) < 2.0):
		if u.job != "flee":
			u.job = "flee"; u.status = "退向后方"; _start_path(world, u, _escape_goal(world, u))
	elif u.job == "flee" and u.path.is_empty(): u.job = "idle"; u.status = "未征召"

func _move(world, u: Dictionary, dt: float) -> void:
	if u.path.is_empty(): return
	if int(u.nav_revision) != nav_revision:
		if not _start_path(world, u, u.goal): return
	var origin: Vector2 = u.pos
	var remaining: float = dt
	# Consume time across waypoints. A short final segment must not discard the
	# rest of this physics step, and snapping must not add unearned distance.
	while remaining > 0.000001 and int(u.path_index) < u.path.size():
		var point: Vector2 = u.path[int(u.path_index)]
		if u.pos.distance_to(point) < 0.000001:
			u.pos = point; u.path_index += 1; continue
		# A stationary operator may occupy a grid centre without blocking the
		# continuous corridor. Only skip it when the full next segment is clear.
		if int(u.path_index) + 1 < u.path.size():
			for other in world.units:
				if int(other.id) == int(u.id) or other.dead or not other.conscious: continue
				if other.pos.distance_to(point) < 0.44 and _clear_segment(world, u, u.path[int(u.path_index) + 1]):
					u.path_index += 1; point = u.path[int(u.path_index)]; break
		if u.progress_point != point:
			u.progress_point = point; u.progress_distance = u.pos.distance_to(point); u.blocked_time = 0.0
		var speed := _movement_speed(world, u)
		var delta: Vector2 = point - u.pos
		var travel: float = minf(delta.length(), speed * remaining)
		var motion: Vector2 = delta.normalized() * travel
		var next: Vector2 = u.pos + motion
		var avoided := false
		if not _clear_motion(world, u, next):
			var sign_value: float = 1.0 if int(u.id) % 2 == 0 else -1.0
			var side: Vector2 = motion.orthogonal().normalized() * travel
			var alternatives: Array[Vector2] = [u.pos + motion.rotated(sign_value * 0.9), u.pos + motion.rotated(-sign_value * 0.9), u.pos + side * sign_value, u.pos - side * sign_value]
			var found := false
			for alternative in alternatives:
				if _clear_motion(world, u, alternative): next = alternative; found = true; break
			if not found: next = u.pos
			avoided = true
		var consumed: float = remaining if avoided else travel / maxf(speed, 0.000001)
		remaining = maxf(0.0, remaining - consumed)
		u.pos = next
		var distance: float = u.pos.distance_to(point)
		if distance < float(u.progress_distance) - 0.025:
			u.progress_distance = distance; u.blocked_time = 0.0
		else: u.blocked_time += consumed
		if distance < 0.000001: u.pos = point; u.path_index += 1
		if float(u.blocked_time) > 2.0:
			if u.team == 1: u.ai_hold_until = 0.0; u.ai_next = 0.0; u.path = PackedVector2Array()
			else: _reject(world, u, "路径被人员阻挡，请调整落点")
			break
	if int(u.path_index) >= u.path.size(): u.path = PackedVector2Array()
	u.velocity = (u.pos - origin) / dt
	if u.velocity.length_squared() > 0.0001: u.facing = u.velocity.angle()

func _movement_speed(world, u: Dictionary) -> float:
	var speed: float = float(u.move_speed) * float(C.POSTURE_SPEED[int(u.posture)])
	var ratio: float = float(u.hp) / float(u.max_hp)
	if ratio < 0.5: speed *= 0.65
	elif ratio < 0.75: speed *= 0.85
	if int(u.crate_id) >= 0:
		var box := _crate(world, int(u.crate_id))
		if not box.is_empty() and int(box.carried_by) == int(u.id): speed *= 0.75
	var patient: Dictionary = world.entity(int(u.rescued_id))
	if not patient.is_empty() and int(patient.get("carrier_id", -1)) == int(u.id): speed *= 0.65
	var obstacle: Dictionary = world.building_at(_cell(u.pos))
	if not obstacle.is_empty() and obstacle.vaultable: speed *= 0.5
	return speed

func _clear_motion(world, u: Dictionary, target: Vector2) -> bool:
	if not _can_walk(world, target): return false
	for other in world.units:
		if int(other.id) == int(u.id) or other.dead or not other.conscious or int(other.carrier_id) >= 0: continue
		if target.distance_squared_to(other.pos) < 0.42 * 0.42: return false
	return true

func _clear_segment(world, u: Dictionary, target: Vector2) -> bool:
	var distance: float = u.pos.distance_to(target)
	for index in range(1, ceili(distance * 8.0) + 1):
		var sample: Vector2 = u.pos.lerp(target, minf(1.0, index / maxf(1.0, distance * 8.0)))
		if not _can_walk(world, sample): return false
	for other in world.units:
		if int(other.id) == int(u.id) or other.dead or not other.conscious or int(other.carrier_id) >= 0: continue
		if other.pos.distance_to(Geometry2D.get_closest_point_to_segment(other.pos, u.pos, target)) < 0.42: return false
	return true

func _auto_posture(world, u: Dictionary) -> void:
	if int(u.posture_mode) >= 0 or u.forced_prone or float(u.posture_timer) > 0 or u.job == "rout": return
	if u.job in ["rescue", "treat", "resupply"] or int(u.crate_id) >= 0: return
	var target: Dictionary = world.entity(int(u.target_id))
	if int(u.station_id) >= 0:
		var b: Dictionary = world.entity(int(u.station_id))
		if b.kind == "mortar":
			if int(u.posture) == 2: _change_posture(u, 1)
			return
		if int(b.target_id) >= 0: target = world.entity(int(b.target_id))
	if target.is_empty(): target = _nearest_opponent(world, u)
	if target.is_empty() or u.pos.distance_to(target.pos) > 32.0: return
	if world.combat_system.has_line_of_fire(world, u, target): return
	for posture in [2, 1, 0]:
		var candidate := u.duplicate(); candidate.posture = posture
		if world.combat_system.has_line_of_fire(world, candidate, target): _change_posture(u, posture); return

func _work(world, u: Dictionary, dt: float) -> void:
	if u.job == "move" and u.path.is_empty(): _finish_job(world, u); return
	if u.job == "operate":
		var b: Dictionary = world.entity(int(u.station_id))
		if b.is_empty() or b.destroyed or b.hp <= 0: _reject(world, u, "工事已损毁"); return
		if u.stage in ["approach_station", "return_station"] and u.path.is_empty():
			u.stage = "station"; u.status = "操作" + str(b.name)
			if int(u.arrival_order) == 2147483647:
				arrival_serial += 1; u.arrival_order = arrival_serial
				b.crew.sort_custom(func(a, z): return int(world.entity(int(a)).get("arrival_order", 2147483647)) < int(world.entity(int(z)).get("arrival_order", 2147483647)))
				_reposition_station_crew(world, b)
				world.emit_event("station_changed", {"entity_id": b.id, "unit_id": u.id})
		if u.stage == "station":
			var loader: bool = b.kind == "mortar" and b.crew.size() > 1 and int(b.crew[1]) == int(u.id)
			var needs_ammo: bool = (int(b.ammo) <= 4 and int(b.ammo) + int(b.supply_reserved) + 4 <= 8) if loader else (int(b.ammo) <= 0 and int(b.loaded) <= 0 and int(b.reload_reserved) <= 0)
			if needs_ammo:
				if not _begin_supply(world, u, b, true): u.status = "缺少弹药" if int(b.ammo) <= 0 and int(b.loaded) <= 0 else "操作" + str(b.name)
	if u.stage in ["supply_pickup", "supply_deliver"]: _supply_work(world, u); return
	if u.job in ["rescue", "treat"]: _medical_work(world, u, dt)

func _supply_work(world, u: Dictionary) -> void:
	var s := _crate(world, int(u.crate_id)); var b: Dictionary = world.entity(int(u.supply_target))
	if s.is_empty() or b.is_empty() or b.destroyed or b.hp <= 0: _reject(world, u, "补给目标失效"); return
	if not u.path.is_empty(): return
	if u.stage == "supply_pickup":
		if int(s.reserved_by) != int(u.id) or int(s.carried_by) >= 0: _reject(world, u, "弹箱预约失效"); return
		s.carried_by = int(u.id); s.pos = u.pos; u.stage = "supply_deliver"; u.status = "搬运弹药"
		_start_path(world, u, u.delivery_point)
	else:
		if int(b.ammo) + int(s.amount) > int(b.ammo_capacity): _reject(world, u, "弹药位置已满"); return
		b.ammo += int(s.amount); b.supply_reserved = maxi(0, int(b.supply_reserved) - int(s.amount))
		s.delivered = true; s.carried_by = -1; s.reserved_by = -1
		u.crate_id = -1; u.supply_target = -1
		world.emit_event("supply_delivered", {"unit_id": u.id, "entity_id": b.id, "amount": s.amount})
		if u.internal_supply and int(u.station_id) >= 0:
			u.internal_supply = false; u.stage = "return_station"; u.status = "返回岗位"
			var role: int = maxi(0, b.crew.find(int(u.id)))
			_start_path(world, u, b.crew_points[mini(role, b.crew_points.size() - 1)])
		else: _finish_job(world, u)

func _medical_work(world, u: Dictionary, dt: float) -> void:
	var patient: Dictionary = world.entity(int(u.rescued_id))
	if patient.is_empty() or patient.dead: _finish_job(world, u, "救护目标已死亡"); return
	if not u.path.is_empty(): return
	if u.stage == "approach_patient":
		if u.pos.distance_to(patient.pos) > 0.85:
			var point := _near_unit_position(world, u.pos, patient)
			if point.x < 0: _reject(world, u, "伤员无法接近")
			else: _start_path(world, u, point)
			return
		if u.job == "rescue": u.stage = "pickup_patient"; u.job_timer = 0.0; u.status = "抱起伤员"
		else: _start_treatment(world, u, patient)
	elif u.stage == "pickup_patient":
		u.job_timer += dt
		if float(u.job_timer) + 0.000001 >= 1.0:
			patient.carrier_id = int(u.id); u.stage = "carry_patient"; u.job_timer = 0.0; u.status = "搬运伤员"
			_start_path(world, u, world.medical_slots[int(u.medical_slot)])
	elif u.stage == "carry_patient": u.stage = "drop_patient"; u.job_timer = 0.0; u.status = "安置伤员"
	elif u.stage == "drop_patient":
		u.job_timer += dt
		if float(u.job_timer) + 0.000001 >= 1.0:
			patient.carrier_id = -1; patient.pos = world.medical_slots[int(u.medical_slot)]; patient.prev_pos = patient.pos
			_start_treatment(world, u, patient)
	elif u.stage == "treatment":
		if float(patient.bleed_rate) <= 0: _finish_job(world, u, "已稳定"); return
		if u.pos.distance_to(patient.pos) > 0.85: _reject(world, u, "急救目标已离开"); return
		u.job_timer += dt
		if float(u.job_timer) + 0.000001 >= 6.0:
			var used := false
			if u.treatment_source == "personal" and int(u.bandages) > 0: u.bandages -= 1; used = true
			elif u.treatment_source == "medical" and world.medical_stock > 0: world.medical_stock -= 1; used = true
			if used:
				patient.bleed_rate = 0.0
				world.emit_event("unit_treated", {"unit_id": patient.id, "medic_id": u.id})
			_finish_job(world, u, "止血完成" if used else "缺药，尚未止血")

func _start_treatment(world, u: Dictionary, patient: Dictionary) -> void:
	if float(patient.bleed_rate) <= 0: _finish_job(world, u, "已安置，伤势稳定"); return
	var personal_reserved := 0; var stock_reserved := 0
	for medic in world.units:
		if not medic.get("treatment_reserved", false): continue
		if medic.get("treatment_source", "") == "medical": stock_reserved += 1
		elif int(medic.id) == int(u.id): personal_reserved += 1
	if int(u.bandages) > personal_reserved: u.treatment_source = "personal"
	elif C.MEDICAL_RECT.has_point(patient.pos) and world.medical_stock > stock_reserved: u.treatment_source = "medical"
	else: _finish_job(world, u, "已安置，缺药尚未止血"); return
	u.stage = "treatment"; u.job_timer = 0.0; u.treatment_reserved = true; u.status = "现场急救"

func _nearest_opponent(world, u: Dictionary) -> Dictionary:
	var result: Dictionary = {}; var best := INF
	for target in world.units:
		if target.team == u.team or target.dead or not target.conscious: continue
		var d: float = u.pos.distance_squared_to(target.pos)
		if d < best: result = target; best = d
	return result

func _enemy_ai(world, u: Dictionary) -> void:
	if u.forced_prone or world.time_s < float(u.rout_until): return
	if u.kind == "flanker" and not u.flank_done:
		var flank := Vector2(10.5, 31.5)
		if u.pos.distance_to(flank) < 1.5: u.flank_done = true
		else:
			u.target_id = -1
			var nearby := _nearest_opponent(world, u)
			if not nearby.is_empty() and u.pos.distance_to(nearby.pos) < 10.0 and _standing_line(world, u, nearby): u.target_id = int(nearby.id)
			_ai_move(world, u, flank); u.status = "侧翼推进"; return
	var target: Dictionary = {}; var best := -INF
	for candidate in world.units:
		if candidate.team == u.team or candidate.dead: continue
		var distance: float = u.pos.distance_to(candidate.pos)
		if distance > 24.0 or not _standing_line(world, u, candidate): continue
		var score: float = (100.0 if candidate.conscious else -100.0) - distance
		if int(candidate.station_id) >= 0: score += 8.0
		if u.kind == "heavy" and distance < 8.0: score += 100.0
		if score > best: best = score; target = candidate
	var core: Dictionary = world.core()
	var core_distance: float = u.pos.distance_to(core.pos)
	var desired_range: float = 12.0 if u.kind == "heavy" else 24.0
	if core.hp > 0 and core_distance <= desired_range and _standing_line(world, u, core):
		var score: float = (150.0 if u.kind == "heavy" else 35.0) - core_distance
		if score > best: target = core
	if not target.is_empty():
		u.target_id = int(target.id)
		if u.kind == "heavy":
			u.path = PackedVector2Array(); u.job = "advance"; u.status = "重装攻击"; return
		if world.time_s >= float(u.ai_hold_until):
			var covered: Vector2 = _cover_destination(world, u, target)
			if covered.distance_to(u.pos) > 0.65: _ai_move(world, u, covered)
			else: u.path = PackedVector2Array()
			u.ai_hold_until = world.time_s + 2.0
		u.status = "掩护交火"; return
	u.target_id = -1
	var goal := Vector2(28.5, 35.0) if u.kind == "flanker" else Vector2(32.5, 34.5)
	if not _reachable(u.pos, goal):
		var blocker := _blocking_structure(world, u, core.pos)
		if not blocker.is_empty() and u.pos.distance_to(blocker.pos) <= 24.0:
			u.target_id = int(blocker.id); u.path = PackedVector2Array(); u.status = "攻击障碍"; return
		goal = _approach_position(world, u.pos, core)
	if goal.x >= 0: _ai_move(world, u, goal)
	u.status = "重装推进" if u.kind == "heavy" else "推进"

func _standing_line(world, u: Dictionary, target: Dictionary) -> bool:
	var copy := u.duplicate(); copy.posture = 0
	return world.combat_system.has_line_of_fire(world, copy, target)

func _ai_move(world, u: Dictionary, destination: Vector2) -> void:
	u.job = "advance"
	if not u.path.is_empty() and u.goal.distance_to(destination) < 0.25: return
	if u.pos.distance_to(destination) < 0.2: u.path = PackedVector2Array(); return
	if _can_stand(world, destination) and _reachable(u.pos, destination): _start_path(world, u, destination)

func _cover_destination(world, u: Dictionary, target: Dictionary) -> Vector2:
	var best: Vector2 = u.pos
	var best_score: float = _cover_score(world, u, target, u.pos)
	var positions: Array[Vector2] = []
	for b in world.buildings:
		if b.destroyed or b.high or b.pos.distance_to(u.pos) > 9.0: continue
		for x in range(b.rect.position.x, b.rect.end.x):
			positions.append(Vector2(x + 0.5, b.rect.position.y - 0.5)); positions.append(Vector2(x + 0.5, b.rect.end.y + 0.5))
		for y in range(b.rect.position.y, b.rect.end.y):
			positions.append(Vector2(b.rect.position.x - 0.5, y + 0.5)); positions.append(Vector2(b.rect.end.x + 0.5, y + 0.5))
	for point in positions:
		if not _can_stand(world, point) or point.distance_to(u.pos) > 7.0: continue
		var occupied := false
		for other in world.units:
			if int(other.id) != int(u.id) and other.conscious and not other.dead and (other.pos.distance_to(point) < 0.55 or (not other.path.is_empty() and other.goal.distance_to(point) < 0.55)): occupied = true; break
		if occupied: continue
		var score: float = _cover_score(world, u, target, point)
		if score > best_score + 1.0 and _reachable(u.pos, point): best = point; best_score = score
	return best

func _cover_score(world, u: Dictionary, target: Dictionary, point: Vector2) -> float:
	var copy := u.duplicate(); copy.pos = point; copy.posture = 0
	if point.distance_to(target.pos) > 24.0 or not world.combat_system.has_line_of_fire(world, copy, target): return -INF
	var protection: Dictionary = world.cover_for(copy, target.pos)
	var score: float = float(protection.get("chance", 0.0)) * 10.0 - u.pos.distance_to(point) * 0.65
	score += (u.pos.distance_to(world.core().pos) - point.distance_to(world.core().pos)) * 0.15
	if u.kind == "flanker":
		for b in world.stations():
			if b.kind != "mg" or b.destroyed: continue
			var direction: Vector2 = point - b.pos
			if direction.length() < 32.0 and absf(wrapf(direction.angle() - float(b.facing), -PI, PI)) < float(b.arc) * 0.5: score -= 4.0
	return score

func _blocking_structure(world, u: Dictionary, goal: Vector2) -> Dictionary:
	var length: float = u.pos.distance_to(goal)
	for i in range(1, ceili(length * 4.0)):
		var point: Vector2 = u.pos.lerp(goal, i / maxf(1.0, length * 4.0))
		var b: Dictionary = world.building_at(_cell(point))
		if not b.is_empty() and b.high and not b.destroyed and _standing_line(world, u, b): return b
	return {}
