extends RefCounted

const C = preload("res://scripts/sim/battle_config.gd")
const Pose = preload("res://scripts/sim/weapon_pose.gd")
var navigation := AStarGrid2D.new()
var nav_revision: int = 0
var arrival_serial: int = 0
var occupied_cells: Dictionary = {}
var reserved_cells: Dictionary = {}
var reserved_edges: Dictionary = {}
var use_placement_cache := true
var _placement_scope := false
var _placement_blockers: Dictionary = {}
# Pure lookups are scoped to a single update or stationary candidate scan.
# They never survive combat/destruction or another unit's movement.
var use_update_query_cache := true
var use_escape_query_cache := true
var _stand_scope := false
var _stand_cache: Dictionary = {}
const INVALID_CELL := Vector2i(-1, -1)
const INTERACTION_DISTANCE := 1.01
const SETTINGS := ["posture", "style", "fire_control", "target_policy"]
const ACTIONS := ["move", "attack", "stop", "draft", "operate", "resupply", "fire", "rescue", "treat"]

func setup(world) -> void:
	arrival_serial = 0
	occupied_cells.clear(); reserved_cells.clear(); reserved_edges.clear()
	for u in world.units: _init_unit(u)
	rebuild_navigation(world)
	_refresh_traffic(world)

func _init_unit(u: Dictionary) -> void:
	if not u.has("nav_revision"):
		u["nav_revision"] = -1; u["arrival_order"] = 2147483647
		u["supply_target"] = -1; u["internal_supply"] = false; u["rescue_owner"] = -1
		u["treatment_reserved"] = false; u["treatment_source"] = ""; u["ai_next"] = 0.0
		u["blocked_time"] = 0.0; u["rout_latched"] = false; u["flank_done"] = false
		u["progress_point"] = Vector2.INF; u["progress_distance"] = INF
		u["ai_target_id"] = -1; u["melee_target_id"] = -1; u["melee_progress"] = 0.0
		u["ai_destination"] = Vector2(-1, -1)
	if not u.has("move_active"):
		u["move_active"] = false; u["move_from"] = INVALID_CELL; u["move_to"] = INVALID_CELL
		u["move_origin"] = Vector2(u.pos); u["traffic_retry"] = 0.0
		u["traffic_yield"] = false; u["traffic_resume"] = Vector2.INF; u["traffic_for"] = -1
		u["traffic_wait_start"] = -1.0
		u["action_job"] = ""; u["action_stage"] = ""; u["wake_pending"] = false
	if not u.has("station_seat"): u["station_seat"] = -1
	var defaults := {"pressure_level": 0, "cower": false, "pressure_entered": -999.0, "pressure_release_timer": 0.0, "pressure_event_time": -999.0, "pressure_event_serial": 0, "pressure_ready_since": -1.0, "pressure_checked_at": -1.0, "pressure_release_since": -1.0, "auto_posture_next": 0.0, "hold_fire": false, "target_policy": "strict", "reload_stage": 0, "reload_paused": false, "idle_reload_since": -1.0, "arrival_facing": INF, "action_pause_reason": ""}
	for key in defaults:
		if not u.has(key): u[key] = defaults[key]

func rebuild_navigation(world) -> void:
	navigation.region = Rect2i(Vector2i.ZERO, C.MAP_SIZE)
	navigation.cell_size = Vector2.ONE; navigation.offset = Vector2(0.5, 0.5)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.jumping_enabled = false; navigation.update()
	for b in world.buildings:
		if b.destroyed or float(b.hp) <= 0: continue
		for y in range(b.rect.position.y, b.rect.end.y):
			for x in range(b.rect.position.x, b.rect.end.x):
				if _barrier_type(b) == "wall": navigation.set_point_solid(Vector2i(x, y), true)
				elif _barrier_type(b) == "cover": navigation.set_point_weight_scale(Vector2i(x, y), 3.0)
	nav_revision += 1

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))

func _center(p: Vector2) -> Vector2:
	return Vector2(_cell(p)) + Vector2(0.5, 0.5)

func _barrier_type(b: Dictionary) -> String:
	return String(b.get("barrier_type", "wall" if b.get("high", false) else ("floor" if float(b.get("height", 0.0)) < 0.1 else "cover")))

func _active(u: Dictionary) -> bool:
	return not bool(u.dead) and bool(u.conscious) and float(u.hp) > 0.0 and int(u.carrier_id) < 0

func occupied_by(cell: Vector2i, ignore_id: int = -1) -> int:
	var owner: int = int(occupied_cells.get(cell, -1))
	return owner if owner != ignore_id else -1

func _body_at(world, cell: Vector2i, ignore_id: int = -1) -> bool:
	for other in world.units:
		if int(other.id) != ignore_id and int(other.carrier_id) < 0 and not _active(other) and _cell(other.pos) == cell: return true
	return false

func destination_available(world, point: Vector2, ignore_id: int = -1) -> bool:
	return _destination_free(world, _center(point), [ignore_id])

func _destination_free(world, point: Vector2, ignored: Array, projection: Dictionary = {}) -> bool:
	if not _can_stand(world, point): return false
	var cell := _cell(point)
	# AI evaluates hundreds of candidate squares without moving anyone between
	# those queries. Build its ownership snapshot once, then discard it before
	# the next unit moves. Public/projected orders keep the live query below.
	if _placement_scope and projection.is_empty():
		for owner in _placement_blockers.get(cell, {}):
			if not ignored.has(int(owner)): return false
		return true
	for other in world.units:
		if ignored.has(int(other.id)) or int(other.carrier_id) >= 0: continue
		# Bodies allow transit, but never form another active unit's final square.
		if _cell(other.pos) == cell: return false
		if not _active(other): continue
		if bool(other.get("move_active", false)) and cell in [Vector2i(other.move_from), Vector2i(other.move_to)]: return false
		var task: Dictionary = projection.get("tasks", {}).get(int(other.id), {})
		var projected_goal: Vector2 = task.get("goal", Vector2(other.goal))
		if bool(task.get("has_goal", not other.path.is_empty())) and _cell(projected_goal) == cell: return false
		var station_id: int = int(task.get("station", other.station_id))
		if station_id >= 0:
			var station: Dictionary = world.entity(station_id)
			if not station.is_empty():
				var seat: int = maxi(0, int(task.get("seat", other.get("station_seat", 0))))
				if _cell(station.crew_points[mini(seat, station.crew_points.size() - 1)]) == cell: return false
	var medical: Dictionary = projection.get("med", world.medical_reservations)
	for slot in medical:
		if not ignored.has(int(medical[slot])) and _cell(world.medical_slots[int(slot)]) == cell: return false
	return true

func _nearest_free_center(world, u: Dictionary, position: Vector2) -> Vector2:
	var base: Vector2i = _cell(position)
	for ring in range(0, 16):
		for y in range(base.y - ring, base.y + ring + 1):
			for x in range(base.x - ring, base.x + ring + 1):
				if maxi(absi(x - base.x), absi(y - base.y)) != ring: continue
				var point := Vector2(x + 0.5, y + 0.5)
				if _destination_free(world, point, [int(u.id)]): return point
	return Vector2.INF

func _edge_key(from: Vector2i, to: Vector2i) -> String:
	return "%d,%d>%d,%d" % [from.x, from.y, to.x, to.y]

func _refresh_traffic(world) -> void:
	occupied_cells.clear(); reserved_cells.clear(); reserved_edges.clear()
	var ordered: Array = world.units.duplicate()
	ordered.sort_custom(func(a, b): return int(a.id) < int(b.id))
	for u in ordered:
		_init_unit(u)
		if not _active(u): u.move_active = false; continue
		var cell: Vector2i = _cell(u.pos)
		if occupied_cells.has(cell):
			var free := _nearest_free_center(world, u, u.pos)
			if free != Vector2.INF:
				u.pos = free; u.prev_pos = free; u.move_active = false; u.nav_revision = -1; cell = _cell(free)
		occupied_cells[cell] = int(u.id)
		reserved_cells[cell] = int(u.id)
	for u in ordered:
		if not _active(u) or not bool(u.move_active): continue
		reserved_cells[Vector2i(u.move_from)] = int(u.id); reserved_cells[Vector2i(u.move_to)] = int(u.id)
		reserved_edges[_edge_key(u.move_from, u.move_to)] = {"from": Vector2i(u.move_from), "to": Vector2i(u.move_to), "owner": int(u.id)}

func _inside(p: Vector2) -> bool:
	return p.x >= 0.25 and p.y >= 0.25 and p.x < C.MAP_SIZE.x - 0.25 and p.y < C.MAP_SIZE.y - 0.25

func _can_stand(world, p: Vector2) -> bool:
	if not _inside(p): return false
	var cell := _cell(p)
	if _stand_scope and _stand_cache.has(cell): return bool(_stand_cache[cell])
	var building: Dictionary = world.building_at(cell)
	var result: bool = building.is_empty() or _barrier_type(building) == "floor"
	if _stand_scope: _stand_cache[cell] = result
	return result

func _can_walk(world, p: Vector2) -> bool:
	if not _inside(p): return false
	for b in world.buildings:
		if b.destroyed or float(b.hp) <= 0 or _barrier_type(b) != "wall": continue
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
		p.tasks[int(u.id)] = {"station": int(u.station_id), "seat": int(u.get("station_seat", -1)), "crate": int(u.crate_id), "medical": int(u.medical_slot), "patient": int(u.rescued_id), "drafted": bool(u.drafted), "supply_target": int(u.get("supply_target", -1)), "goal": Vector2(u.goal), "has_goal": not u.path.is_empty()}
	for s in world.supplies:
		if not s.delivered: p.crates[int(s.id)] = int(s.carried_by) if int(s.carried_by) >= 0 else int(s.reserved_by)
	for key in world.medical_reservations: p.med[int(key)] = int(world.medical_reservations[key])
	for u in world.units:
		if int(u.get("rescue_owner", -1)) >= 0: p.patients[int(u.id)] = int(u.rescue_owner)
	for order in world.pending_orders:
		var kind: String = order.kind
		if kind in SETTINGS or kind in ["fire", "station_attack"]: continue
		for id in order.ids:
			if not p.tasks.has(int(id)): continue
			if kind == "attack" and int(p.tasks[int(id)].station) >= 0: continue
			if kind == "draft" and bool(order.data.get("value", true)):
				p.tasks[int(id)].drafted = true; continue
			_project_release(p, int(id))
			if kind == "draft": p.tasks[int(id)].drafted = bool(order.data.get("value", true))
			var alloc: Dictionary = order.data.get("_allocations", {}).get(int(id), {})
			if alloc.has("goal"): p.tasks[int(id)].goal = alloc.goal; p.tasks[int(id)].has_goal = true
			if kind == "operate": p.tasks[int(id)].station = int(order.data.target_id); p.tasks[int(id)].seat = int(alloc.get("seat", 0))
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
	p.tasks[id].has_goal = false

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
	if kind == "fire_control" and not data.get("value") is bool: return _bad("火控设置无效")
	if kind == "target_policy" and not String(data.get("value", "")) in ["strict", "priority"]: return _bad("锁定模式无效")
	if kind in SETTINGS or kind in ["stop", "draft"]: return {"ok": true, "reason": ""}
	if kind == "move":
		if not data.get("position") is Vector2: return _bad("缺少移动位置")
		for id in selected: _project_release(projection, id)
		if data.has("formation"):
			var formation: Dictionary = data.formation
			if not formation.get("axis") is Vector2: return _bad("队列方向无效")
			var planned := _plan_formation(world, selected, data.position, formation.axis, float(formation.get("spacing", 1.0)), float(formation.get("facing", 0.0)), projection)
			if not planned.ok: return planned
			allocations = planned.allocations
		else:
			var goals: Array[Vector2] = _group_goals(world, selected, data.position, projection)
			if goals.size() != selected.size(): return _bad("落点无法通行或没有足够空间")
			for i in range(selected.size()):
				if not _reachable(world.entity(selected[i]).pos, goals[i]): return _bad("没有可达路径")
				allocations[selected[i]] = {"goal": goals[i]}
	elif kind == "attack":
		var target: Dictionary = world.entity(int(data.get("target_id", -1)))
		if target.is_empty() or bool(target.get("dead", false)) or bool(target.get("destroyed", false)) or float(target.get("hp", 0.0)) <= 0.0: return _bad("攻击目标无效")
		for id in selected:
			if int(projection.tasks[id].station) >= 0: return _bad("请选中工事指定目标")
	elif kind == "operate":
		var b: Dictionary = world.entity(int(data.get("target_id", -1)))
		if b.is_empty() or not b.has("capacity") or int(b.capacity) < 1 or b.destroyed or b.hp <= 0: return _bad("该设施不能操作")
		for id in selected: _project_release(projection, id)
		var count := 0
		for task in projection.tasks.values():
			if int(task.station) == int(b.id): count += 1
		if count + selected.size() > int(b.capacity): return _bad("工事岗位已满")
		var taken_seats: Array[int] = []
		for task in projection.tasks.values():
			if int(task.station) == int(b.id): taken_seats.append(int(task.get("seat", 0)))
		for id in selected:
			var seat := -1
			for candidate in range(int(b.capacity)):
				if not taken_seats.has(candidate) and _destination_free(world, b.crew_points[candidate], selected, projection): seat = candidate; break
			if seat < 0: return _bad("操作点被人员或任务占用")
			var point: Vector2 = b.crew_points[seat]
			if not _reachable(world.entity(id).pos, point): return _bad("无法到达操作点")
			allocations[id] = {"goal": point, "seat": seat}; projection.tasks[id].station = int(b.id); projection.tasks[id].seat = seat; projection.tasks[id].goal = point; projection.tasks[id].has_goal = true; count += 1; taken_seats.append(seat)
	elif kind == "resupply":
		var b: Dictionary = world.entity(int(data.get("target_id", -1)))
		if b.is_empty() or not b.has("capacity") or int(b.capacity) < 1 or b.destroyed or b.hp <= 0: return _bad("无效补给目标")
		for id in selected: _project_release(projection, id)
		var reserved := _project_supply_amount(world, projection, int(b.id))
		for id in selected:
			var crate: Dictionary = _available_crate(world, world.entity(id).pos, b, projection.crates, id, projection)
			if crate.is_empty(): return _bad("没有可达弹药箱")
			if int(b.ammo) + reserved + int(crate.amount) > int(b.ammo_capacity): return _bad("没有完整一箱的剩余容量")
			var delivery: Vector2 = _approach_position(world, world.entity(id).pos, b, id, projection)
			if delivery.x < 0 or not _reachable(crate.pos, delivery): return _bad("无法到达交付点")
			allocations[id] = {"crate": int(crate.id), "delivery": delivery, "goal": _pickup_position(world, world.entity(id).pos, crate.pos, id, projection)}
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
			var slot := _available_medical_slot(world, u.pos, projection.med, id, projection)
			if slot < 0: return _bad("没有可达救护位置")
			var approach := _near_unit_position(world, u.pos, patient, id, projection)
			if approach.x < 0 or not _reachable(u.pos, approach): return _bad("无法接近伤员")
			if _adjacent_position(world, u.pos, world.medical_slots[slot], id).x < 0: return _bad("无法接近救护位置")
			allocations[id] = {"medical": slot, "goal": approach}
		else:
			if float(patient.bleed_rate) <= 0: return _bad("目标不需要止血")
			if int(u.bandages) <= 0 and (not C.MEDICAL_RECT.has_point(patient.pos) or world.medical_stock <= 0): return _bad("没有可用绷带")
			var approach := _near_unit_position(world, u.pos, patient, id, projection)
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

func _group_goals(world, ids: Array[int], clicked: Vector2, projection: Dictionary = {}) -> Array[Vector2]:
	var result: Array[Vector2] = []
	clicked = _center(clicked)
	if not _can_stand(world, clicked): return result
	var candidates: Array[Vector2] = [clicked]
	for ring in range(1, 9):
		for y in range(-ring, ring + 1):
			for x in range(-ring, ring + 1):
				if maxi(absi(x), absi(y)) == ring: candidates.append(clicked + Vector2(x, y))
	for point in candidates:
		if _destination_free(world, point, ids, projection) and not result.has(point): result.append(point)
		if result.size() >= ids.size(): break
	return result

func _flow_edge(graph: Array, from: int, to: int, capacity: int, cost: float) -> void:
	var forward := {"to": to, "reverse": graph[to].size(), "capacity": capacity, "cost": cost}
	var reverse := {"to": from, "reverse": graph[from].size(), "capacity": 0, "cost": -cost}
	graph[from].append(forward); graph[to].append(reverse)

# Unit -> unique cell -> ideal slot. Residual edges allow later assignments to
# move earlier units, so a greedy choice cannot reject a feasible whole group.
func _formation_flow(world, ids: Array[int], candidates: Array[Vector2], ideals: Array[Vector2]) -> Array[int]:
	var n := ids.size(); var m := candidates.size()
	var source := 0; var unit_start := 1; var cell_in := n + 1; var cell_out := n + m + 1; var slot_start := n + 2 * m + 1; var sink := 2 * n + 2 * m + 1
	var graph: Array = []
	for vertex in range(sink + 1): graph.append([])
	for unit in range(n):
		_flow_edge(graph, source, unit_start + unit, 1, 0.0)
		for candidate in range(m):
			var cost := _formation_path_cost(world.entity(ids[unit]).pos, candidates[candidate])
			if cost < 1.0e12: _flow_edge(graph, unit_start + unit, cell_in + candidate, 1, cost)
	for candidate in range(m):
		_flow_edge(graph, cell_in + candidate, cell_out + candidate, 1, 0.0)
		for slot in range(n):
			var offset := candidates[candidate] - ideals[slot]
			if maxf(absf(offset.x), absf(offset.y)) <= 2.000001:
				_flow_edge(graph, cell_out + candidate, slot_start + slot, 1, offset.length_squared() * 1000000.0)
	for slot in range(n): _flow_edge(graph, slot_start + slot, sink, 1, 0.0)
	for flow in range(n):
		var distance: Array[float] = []; distance.resize(graph.size()); distance.fill(INF); distance[source] = 0.0
		var parent_vertex: Array[int] = []; parent_vertex.resize(graph.size()); parent_vertex.fill(-1)
		var parent_edge: Array[int] = []; parent_edge.resize(graph.size()); parent_edge.fill(-1)
		var queued: Array[bool] = []; queued.resize(graph.size()); queued.fill(false)
		var queue: Array[int] = [source]; queued[source] = true; var head := 0
		while head < queue.size():
			var vertex: int = queue[head]; head += 1; queued[vertex] = false
			for edge_index in range(graph[vertex].size()):
				var edge: Dictionary = graph[vertex][edge_index]
				if int(edge.capacity) <= 0: continue
				var value: float = distance[vertex] + float(edge.cost)
				var target := int(edge.to)
				if value >= distance[target] - 0.00000001: continue
				distance[target] = value; parent_vertex[target] = vertex; parent_edge[target] = edge_index
				if not queued[target]: queue.append(target); queued[target] = true
		if parent_vertex[sink] < 0: return []
		var vertex := sink
		while vertex != source:
			var previous := parent_vertex[vertex]; var edge: Dictionary = graph[previous][parent_edge[vertex]]
			edge.capacity = int(edge.capacity) - 1
			graph[vertex][int(edge.reverse)].capacity = int(graph[vertex][int(edge.reverse)].capacity) + 1
			vertex = previous
	var result: Array[int] = []; result.resize(n); result.fill(-1)
	for unit in range(n):
		for edge in graph[unit_start + unit]:
			if int(edge.to) >= cell_in and int(edge.to) < cell_in + m and int(edge.capacity) == 0:
				result[unit] = int(edge.to) - cell_in; break
	return result

func plan_formation(world, ids: Array, center: Vector2, axis: Vector2, spacing: float, facing: float) -> Dictionary:
	return _plan_formation(world, ids, center, axis, spacing, facing, _projection(world))

func _plan_formation(world, ids: Array, center: Vector2, axis: Vector2, spacing: float, facing: float, projection: Dictionary) -> Dictionary:
	if ids.is_empty(): return {"ok": false, "reason": "请先选择人员", "allocations": {}}
	if not center.is_finite() or not axis.is_finite() or axis.length_squared() < 0.000001 or not is_finite(spacing) or not is_finite(facing): return {"ok": false, "reason": "队形参数无效", "allocations": {}}
	var selected: Array[int] = []
	for raw_id in ids:
		var id := int(raw_id); var u: Dictionary = world.entity(id)
		if u.is_empty() or not _active(u) or int(u.team) != 0: return {"ok": false, "reason": "队形中有无法行动的人员", "allocations": {}}
		if not selected.has(id): selected.append(id)
	selected.sort()
	var projected := projection.duplicate(true)
	for id in selected: _project_release(projected, id)
	var ideals: Array[Vector2] = []
	var candidates: Array[Vector2] = []
	axis = axis.normalized(); spacing = clampf(spacing, 1.0, 4.0)
	for index in range(selected.size()):
		var ideal := _center(center + axis * (float(index) - float(selected.size() - 1) * 0.5) * spacing)
		ideals.append(ideal)
		for y in range(-2, 3):
			for x in range(-2, 3):
				var point := ideal + Vector2(x, y)
				if candidates.has(point) or not _destination_free(world, point, selected, projected): continue
				# A formation cell must be reachable by at least one selected member.
				for id in selected:
					if _reachable(world.entity(id).pos, point): candidates.append(point); break
	candidates.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	if candidates.size() < selected.size(): return {"ok": false, "reason": "队形空间不足", "allocations": {}}
	var matched := _formation_flow(world, selected, candidates, ideals)
	if matched.size() != selected.size(): return {"ok": false, "reason": "队形没有整组可达空间", "allocations": {}}
	var allocations := {}
	for index in range(selected.size()): allocations[selected[index]] = {"goal": candidates[matched[index]], "facing": facing}
	return {"ok": true, "reason": "", "allocations": allocations}

func _formation_path_cost(from: Vector2, to: Vector2) -> float:
	var path := navigation.get_point_path(_cell(from), _cell(to))
	if path.is_empty(): return 1.0e12
	var length := 0.0; var previous: Vector2 = from
	for point in path:
		length += previous.distance_to(point) * navigation.get_point_weight_scale(_cell(point)); previous = point
	return length

func apply_order(world, ids: Array, kind: String, data: Dictionary) -> void:
	var sorted_ids := ids.duplicate(); sorted_ids.sort()
	for raw_id in sorted_ids:
		var u: Dictionary = world.entity(int(raw_id))
		if u.is_empty() or u.dead or not u.conscious: continue
		_init_unit(u)
		var alloc: Dictionary = data.get("_allocations", {}).get(int(u.id), {})
		if kind == "posture":
			u.posture_mode = int(data.value)
			if u.posture_mode >= 0 and not bool(u.cower): _change_posture(u, maxi(int(u.posture_mode), mini(2, int(u.pressure_level))))
			continue
		if kind == "style": u.style = int(data.value); continue
		if kind == "fire_control": u.hold_fire = bool(data.value); continue
		if kind == "target_policy": u.target_policy = String(data.value); continue
		if kind == "fire":
			var b: Dictionary = world.entity(int(data.target_id))
			if not b.is_empty() and int(u.station_id) == int(b.id):
				if int(b.target_id) >= 0 or Vector2(b.fire_point) != Vector2(data.position):
					b.aim_progress = 0.0; b["aim_elapsed"] = 0.0; b["aim_fraction"] = 0.0
				b.target_id = -1; b["aim_target_id"] = -1
				b["mortar_aim_point"] = Vector2(data.position)
				b.fire_point = data.position; b.fire_requested = true
			continue
		if kind == "attack" and int(u.station_id) >= 0:
			world.emit_event("order_rejected", {"unit_id": u.id, "reason": "请选中工事指定目标"})
			continue
		if kind == "draft" and bool(data.get("value", true)):
			if world.time_s >= float(u.rout_until):
				u.drafted = true
				if u.job in ["rout", "flee"]: _cancel_job(world, u)
			continue
		# Work commands suspend personal chambering; the completed stage belongs
		# to this weapon and must survive task hand-offs and completion.
		if kind in ["move", "operate", "resupply", "rescue", "treat"]:
			world.combat_system._interrupt_reload(u, float(C.rifle().reload))
		if kind == "stop" and int(u.station_id) >= 0:
			var station: Dictionary = world.entity(int(u.station_id))
			if not station.is_empty():
				station.reload_progress = 0.0; station.reload_reserved = 0; station["reload_stage"] = 0; station.fire_requested = false; station.target_id = -1
		_cancel_job(world, u, kind not in ["stop", "draft"])
		match kind:
			"draft": u.drafted = false; u.status = "未征召"
			"move":
				u.job = "move"; u.status = "移动"; u.arrival_facing = float(alloc.get("facing", INF))
				_start_path(world, u, alloc.get("goal", data.position))
			"attack": u.target_id = int(data.target_id); u.status = "指定攻击"
			"operate":
				var b: Dictionary = world.entity(int(data.target_id))
				if b.is_empty() or b.destroyed or b.crew.size() >= int(b.capacity): _reject(world, u, "岗位已不可用"); continue
				u.job = "operate"; u.stage = "approach_station"; u.station_id = int(b.id); u.arrival_order = 2147483647
				b.crew.append(int(u.id)); u.status = "前往岗位"
				var point: Vector2 = alloc.get("goal", b.crew_points[mini(b.crew.size() - 1, b.crew_points.size() - 1)])
				u.station_seat = int(alloc.get("seat", maxi(0, b.crew_points.find(point))))
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
		_publish_action_stage(world, u)

func _cancel_job(world, u: Dictionary, preserve_reload: bool = true) -> void:
	release_station(world, u); _release_supply(world, u); _drop_patient(world, u); _release_medical(world, u)
	u.job = "idle"; u.stage = ""; u.path = PackedVector2Array(); u.path_index = 0; u.goal = Vector2(u.move_to) + Vector2(0.5, 0.5) if bool(u.move_active) else _center(u.pos)
	u.target_id = -1; u.rescued_id = -1; u.job_timer = 0.0; u.velocity = Vector2.ZERO
	if not preserve_reload:
		u.reload_progress = 0.0; u.reload_reserved = 0; u.reload_stage = 0; u.reload_paused = false; u.idle_reload_since = -1.0
	u.burst_left = 0; u.treatment_reserved = false; u.treatment_source = ""; u.arrival_facing = INF
	u.melee_target_id = -1; u.melee_progress = 0.0
	u.traffic_yield = false; u.traffic_resume = Vector2.INF; u.traffic_for = -1
	u.traffic_wait_start = -1.0
	u.status = "待命" if u.drafted or u.team == 1 else "未征召"
	_publish_action_stage(world, u)

func release_station(world, u: Dictionary) -> void:
	var id: int = int(u.station_id)
	if id < 0: return
	var b: Dictionary = world.entity(id)
	if not b.is_empty():
		var was_gunner: bool = not b.crew.is_empty() and int(b.crew[0]) == int(u.id)
		b.crew.erase(int(u.id))
		if b.kind == "mg": b.burst_left = 0
		if was_gunner: b.aim_progress = 0.0
		if b.crew.is_empty():
			world.combat_system._interrupt_reload(b, 10.0 if b.kind == "mortar" else float(C.machine_gun().reload))
			b.aim_progress = 0.0
		world.emit_event("station_changed", {"entity_id": b.id, "unit_id": u.id})
		if was_gunner and not b.crew.is_empty(): _reposition_station_crew(world, b)
	u.station_id = -1; u.station_seat = -1; u.arrival_order = 2147483647

func _reposition_station_crew(world, b: Dictionary) -> void:
	# Crew order is a role; the physical seat stays assigned through promotion.
	var crew: Array = b.crew.duplicate()
	for index in range(crew.size()):
		var member: Dictionary = world.entity(int(crew[index]))
		if member.is_empty() or not String(member.stage) in ["station", "approach_station", "return_station"]: continue
		var seat: int = int(member.get("station_seat", -1))
		if seat < 0: seat = mini(index, b.crew_points.size() - 1); member.station_seat = seat
		var point: Vector2 = b.crew_points[seat]
		if member.goal.distance_to(point) < 0.02 and (not member.path.is_empty() or member.pos.distance_to(point) < 0.05): continue
		if not _reachable(member.pos, point): _reject(world, member, "操作点无法到达"); continue
		member.stage = "approach_station"; member.status = "调整操作岗位"
		_start_path(world, member, point)

func _crate(world, id: int) -> Dictionary:
	for s in world.supplies:
		if int(s.id) == id: return s
	return {}

func _available_crate(world, from: Vector2, b: Dictionary, owners: Dictionary = {}, ignore_id: int = -1, projection: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}; var distance := INF
	var kind: String = "mg_ammo" if b.kind == "mg" else "mortar_ammo"
	for s in world.supplies:
		var owner: int = int(owners.get(int(s.id), s.reserved_by))
		# A projected cancellation can release a currently carried box before pickup.
		if s.delivered or s.kind != kind or owner >= 0: continue
		if int(s.carried_by) >= 0 and not owners.has(int(s.id)): continue
		var d: float = from.distance_squared_to(s.pos)
		if d < distance and _pickup_position(world, from, s.pos, ignore_id, projection).x >= 0: result = s; distance = d
	return result

func _begin_supply(world, u: Dictionary, b: Dictionary, internal: bool, crate_id: int = -1, delivery: Vector2 = Vector2(-1, -1)) -> bool:
	if b.is_empty() or b.destroyed or b.hp <= 0: return false
	var s: Dictionary = _crate(world, crate_id) if crate_id >= 0 else _available_crate(world, u.pos, b, {}, int(u.id))
	if s.is_empty() or s.delivered or int(s.carried_by) >= 0 or int(s.reserved_by) >= 0: return false
	if int(b.ammo) + int(b.supply_reserved) + int(s.amount) > int(b.ammo_capacity): return false
	if delivery.x < 0: delivery = _approach_position(world, s.pos, b, int(u.id))
	if delivery.x < 0 or not _reachable(s.pos, delivery): return false
	var pickup := _pickup_position(world, u.pos, s.pos, int(u.id))
	if pickup.x < 0: return false
	s.reserved_by = int(u.id); b.supply_reserved += int(s.amount)
	u.crate_id = int(s.id); u.supply_target = int(b.id); u.internal_supply = internal; u["delivery_point"] = delivery
	u.stage = "supply_pickup"; u.status = "取弹药箱"
	if not internal: u.job = "resupply"
	return _start_path(world, u, pickup)

func _release_supply(world, u: Dictionary) -> void:
	var s: Dictionary = _crate(world, int(u.crate_id))
	if not s.is_empty():
		var b: Dictionary = world.entity(int(u.get("supply_target", -1)))
		if not b.is_empty(): b.supply_reserved = maxi(0, int(b.supply_reserved) - int(s.amount))
		if int(s.carried_by) == int(u.id): s.pos = _nearest_stand(world, u.pos); s.carried_by = -1
		if int(s.reserved_by) == int(u.id): s.reserved_by = -1
	u.crate_id = -1; u.supply_target = -1; u.internal_supply = false

func _available_medical_slot(world, from: Vector2, reservations: Dictionary, ignore_id: int = -1, projection: Dictionary = {}) -> int:
	var result := -1; var best := INF
	for i in range(world.medical_slots.size()):
		if reservations.has(i): continue
		var point: Vector2 = world.medical_slots[i]; var occupied := false
		for patient in world.units:
			if int(patient.id) != ignore_id and int(patient.carrier_id) < 0 and _cell(patient.pos) == _cell(point): occupied = true; break
		var d: float = point.distance_squared_to(from)
		if not occupied and d < best and _destination_free(world, point, [ignore_id], projection) and _reachable(from, point): result = i; best = d
	return result

func _release_medical(world, u: Dictionary) -> void:
	if int(u.medical_slot) >= 0 and int(world.medical_reservations.get(int(u.medical_slot), -1)) == int(u.id): world.medical_reservations.erase(int(u.medical_slot))
	u.medical_slot = -1
	var patient: Dictionary = world.entity(int(u.rescued_id))
	if not patient.is_empty() and int(patient.get("rescue_owner", -1)) == int(u.id): patient.rescue_owner = -1

func _drop_patient(world, u: Dictionary) -> void:
	var patient: Dictionary = world.entity(int(u.rescued_id))
	if not patient.is_empty() and int(patient.get("carrier_id", -1)) == int(u.id):
		var point := _nearest_free_center(world, patient, u.pos)
		if point == Vector2.INF: point = _center(u.pos)
		patient.pos = point; patient.prev_pos = point; patient.carrier_id = -1
		if _active(patient): occupied_cells[_cell(point)] = int(patient.id); reserved_cells[_cell(point)] = int(patient.id)

func _near_unit_position(world, from: Vector2, patient: Dictionary, ignore_id: int = -1, projection: Dictionary = {}) -> Vector2:
	if int(patient.id) == ignore_id: return _center(patient.pos)
	return _adjacent_position(world, from, patient.pos, ignore_id, projection)

func _pickup_position(world, from: Vector2, position: Vector2, ignore_id: int, projection: Dictionary = {}) -> Vector2:
	var point := _center(position)
	if _destination_free(world, point, [ignore_id], projection) and _reachable(from, point): return point
	return _adjacent_position(world, from, point, ignore_id, projection)

func _adjacent_position(world, from: Vector2, position: Vector2, ignore_id: int, projection: Dictionary = {}) -> Vector2:
	var best := Vector2(-1, -1); var distance := INF
	for offset in [Vector2.UP, Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		var p: Vector2 = _center(position) + offset
		var d: float = p.distance_squared_to(from)
		if _destination_free(world, p, [ignore_id], projection) and d < distance and _reachable(from, p): best = p; distance = d
	return best

func _approach_position(world, from: Vector2, b: Dictionary, ignore_id: int = -1, projection: Dictionary = {}) -> Vector2:
	var best := Vector2(-1, -1); var distance := INF
	for y in range(b.rect.position.y - 1, b.rect.end.y + 1):
		for x in range(b.rect.position.x - 1, b.rect.end.x + 1):
			var p := Vector2(x + 0.5, y + 0.5); var d: float = p.distance_squared_to(from)
			if _destination_free(world, p, [ignore_id], projection) and d < distance and _reachable(from, p): best = p; distance = d
	return best

func _nearest_stand(world, position: Vector2) -> Vector2:
	var base := _center(Vector2(clampf(position.x, 0.5, 63.5), clampf(position.y, 0.5, 47.5)))
	if _can_stand(world, base): return base
	for ring in range(1, 12):
		for y in range(-ring, ring + 1):
			for x in range(-ring, ring + 1):
				if maxi(absi(x), absi(y)) != ring: continue
				var p := base + Vector2(x, y)
				if _can_stand(world, p): return p
	return base

func _start_path(world, u: Dictionary, goal: Vector2) -> bool:
	goal = _center(goal)
	if not _can_stand(world, goal) or not _reachable(u.pos, goal): _reject(world, u, "没有可达路径"); return false
	if _body_at(world, _cell(goal), int(u.id)): _reject(world, u, "落点被伤员或遗体占用"); return false
	var start: Vector2i = Vector2i(u.move_to) if bool(u.move_active) else _cell(u.pos)
	u.goal = goal; u.path = navigation.get_point_path(start, _cell(goal))
	u.path_index = 0 if bool(u.move_active) or u.pos.distance_to(Vector2(start) + Vector2(0.5, 0.5)) > 0.00001 else (1 if u.path.size() > 1 else 0)
	u.nav_revision = nav_revision; u.blocked_time = 0.0; u.traffic_retry = 0.0
	u.progress_point = Vector2.INF; u.progress_distance = INF
	return true

func _traffic_path(world, u: Dictionary, goal: Vector2) -> PackedVector2Array:
	var start: Vector2i = Vector2i(u.move_to) if bool(u.move_active) else _cell(u.pos)
	var target := _cell(goal)
	var changed: Array[Vector2i] = []
	for other in world.units:
		if int(other.id) == int(u.id) or not _active(other): continue
		var cells: Array[Vector2i] = [_cell(other.pos)]
		if bool(other.get("move_active", false)): cells.append(Vector2i(other.move_from)); cells.append(Vector2i(other.move_to))
		for cell in cells:
			if cell == start or not navigation.region.has_point(cell) or navigation.is_point_solid(cell): continue
			navigation.set_point_solid(cell, true); changed.append(cell)
	var result := PackedVector2Array()
	if navigation.region.has_point(target) and not navigation.is_point_solid(target): result = navigation.get_point_path(start, target)
	for cell in changed: navigation.set_point_solid(cell, false)
	return result

func _reserve_edge(world, u: Dictionary, point: Vector2) -> bool:
	var from := _cell(u.pos)
	var to := _cell(point)
	if not _can_walk(world, point): return false
	if int(reserved_cells.get(to, -1)) not in [-1, int(u.id)]: return false
	if from.x != to.x and from.y != to.y:
		if navigation.is_point_solid(Vector2i(from.x, to.y)) or navigation.is_point_solid(Vector2i(to.x, from.y)): return false
	for edge in reserved_edges.values():
		if int(edge.owner) == int(u.id): continue
		# Includes reverse edges and the two diagonals crossing the same square.
		if Geometry2D.segment_intersects_segment(Vector2(from), Vector2(to), Vector2(edge.from), Vector2(edge.to)) != null: return false
	u.move_active = true; u.move_from = from; u.move_to = to; u.move_origin = Vector2(u.pos)
	reserved_cells[from] = int(u.id); reserved_cells[to] = int(u.id)
	reserved_edges[_edge_key(from, to)] = {"from": from, "to": to, "owner": int(u.id)}
	return true

func _release_edge(u: Dictionary) -> void:
	var from: Vector2i = u.move_from
	var to: Vector2i = u.move_to
	if from != to and int(reserved_cells.get(from, -1)) == int(u.id): reserved_cells.erase(from)
	reserved_cells[to] = int(u.id)
	u.move_active = false; u.move_from = INVALID_CELL; u.move_to = INVALID_CELL

func _release_occupancy(u: Dictionary) -> void:
	for cell in occupied_cells.keys():
		if int(occupied_cells[cell]) == int(u.id): occupied_cells.erase(cell)
	for cell in reserved_cells.keys():
		if int(reserved_cells[cell]) == int(u.id): reserved_cells.erase(cell)
	for key in reserved_edges.keys():
		if int(reserved_edges[key].owner) == int(u.id): reserved_edges.erase(key)
	u.move_active = false; u.move_from = INVALID_CELL; u.move_to = INVALID_CELL

func _can_yield(u: Dictionary) -> bool:
	if not _active(u) or bool(u.get("cower", false)) or float(u.posture_timer) > 0.0 or bool(u.move_active) or bool(u.traffic_yield): return false
	if u.team == 0 and int(u.target_id) >= 0: return false
	if u.job == "operate" and u.stage == "station": return false
	return not String(u.stage) in ["pickup_patient", "drop_patient", "treatment"]

func _begin_yield(world, u: Dictionary, requester: Dictionary) -> bool:
	if not _can_yield(u): return false
	var forbidden: Dictionary = {}
	for point in requester.path: forbidden[_cell(point)] = true
	forbidden[_cell(requester.pos)] = true
	var start := _cell(u.pos)
	var direction: Vector2 = Vector2(requester.goal - requester.pos).normalized()
	if not requester.path.is_empty(): direction = Vector2(requester.path[mini(int(requester.path_index), requester.path.size() - 1)] - requester.pos).normalized()
	if direction.is_zero_approx(): direction = Vector2(u.pos - requester.pos).normalized()
	var queue: Array[Vector2i] = [start]
	var parents: Dictionary = {start: start}
	var cursor := 0
	var destination := INVALID_CELL
	while cursor < queue.size():
		var cell := queue[cursor]; cursor += 1
		var point := Vector2(cell) + Vector2(0.5, 0.5)
		var lateral: float = absf(Vector2(point - u.pos).dot(direction.orthogonal()))
		if cell != start and lateral >= 0.5 and not forbidden.has(cell) and _destination_free(world, point, [int(u.id)]): destination = cell; break
		for offset in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if parents.has(next) or not navigation.region.has_point(next) or navigation.is_point_solid(next): continue
			if int(reserved_cells.get(next, -1)) not in [-1, int(u.id)]: continue
			parents[next] = cell; queue.append(next)
	if destination == INVALID_CELL: return false
	var path := PackedVector2Array()
	var node := destination
	while node != start: path.insert(0, Vector2(node) + Vector2(0.5, 0.5)); node = parents[node]
	u.traffic_resume = Vector2(u.goal) if not u.path.is_empty() else Vector2.INF
	u.traffic_yield = true; u.traffic_for = int(requester.id); u.path = path; u.path_index = 0
	u.traffic_wait_start = -1.0
	u.goal = Vector2(destination) + Vector2(0.5, 0.5); u.blocked_time = 0.0; u.status = "让路"
	world.emit_event("unit_traffic_yield", {"unit_id": u.id, "for_unit_id": requester.id, "pos": u.pos, "goal": u.goal})
	return true

func _handle_traffic_block(world, u: Dictionary, next: Vector2, dt: float) -> void:
	u.blocked_time = float(u.blocked_time) + dt
	if world.time_s < float(u.traffic_retry): return
	u.traffic_retry = world.time_s + 0.25
	if float(u.blocked_time) < 0.25: return
	var path := _traffic_path(world, u, u.goal)
	if path.size() > 1:
		u.path = path; u.path_index = 1; u.blocked_time = 0.0; return
	var blocker_id: int = int(reserved_cells.get(_cell(next), -1))
	var blocker: Dictionary = world.entity(blocker_id)
	if not blocker.is_empty() and float(u.blocked_time) >= 0.5:
		var oncoming: bool = blocker.path.is_empty()
		if not oncoming:
			var index: int = mini(int(blocker.path_index), blocker.path.size() - 1)
			oncoming = Vector2(blocker.path[index] - blocker.pos).dot(next - Vector2(u.pos)) < -0.01
		if oncoming:
			if blocker.path.is_empty() or int(blocker.id) > int(u.id):
				if _begin_yield(world, blocker, u): return
				if not blocker.path.is_empty() and _begin_yield(world, u, blocker): return
			else:
				if _begin_yield(world, u, blocker): return
				if _begin_yield(world, blocker, u): return
	if float(u.blocked_time) >= 2.0 and not blocker.is_empty() and blocker.path.is_empty() and not bool(blocker.move_active):
		if u.team == 1: u.ai_hold_until = 0.0; u.ai_next = 0.0; u.path = PackedVector2Array()
		else: _reject(world, u, "路径被人员阻挡，请调整落点")
	elif float(u.blocked_time) >= 4.0 and not blocker.is_empty() and not bool(blocker.get("cower", false)) and float(blocker.posture_timer) <= 0.0 and not bool(blocker.move_active) and not bool(blocker.traffic_yield):
		if u.team == 1: u.ai_hold_until = 0.0; u.ai_next = 0.0; u.path = PackedVector2Array(); u.status = "狭道无可让路位置"
		else: _reject(world, u, "狭道无可让路位置，请调整命令")

func _resume_yield(world, u: Dictionary) -> void:
	if not bool(u.traffic_yield) or not u.path.is_empty() or bool(u.move_active): return
	if u.traffic_resume == Vector2.INF:
		u.traffic_yield = false; u.traffic_for = -1; u.goal = u.pos; return
	if float(u.traffic_wait_start) < 0.0: u.traffic_wait_start = world.time_s
	if world.time_s < float(u.traffic_retry): return
	u.traffic_retry = world.time_s + 0.25
	var path := _traffic_path(world, u, u.traffic_resume)
	if path.is_empty():
		if world.time_s - float(u.traffic_wait_start) > 5.0:
			if u.team == 1: u.traffic_yield = false; u.traffic_resume = Vector2.INF; u.ai_next = 0.0; u.ai_hold_until = 0.0
			else: _reject(world, u, "让路后原落点仍被阻挡，请调整命令")
		return
	u.goal = u.traffic_resume; u.path = path; u.path_index = 1 if path.size() > 1 else 0
	u.traffic_resume = Vector2.INF; u.traffic_yield = false; u.traffic_for = -1; u.blocked_time = 0.0
	u.traffic_wait_start = -1.0

func _reject(world, u: Dictionary, reason: String) -> void:
	_cancel_job(world, u); u.status = reason
	world.emit_event("order_rejected", {"unit_id": u.id, "reason": reason})

func _finish_job(world, u: Dictionary, text: String = "待命") -> void:
	var old_job: String = u.job
	var arrival_facing: float = float(u.get("arrival_facing", INF))
	_cancel_job(world, u); u.status = text
	if old_job == "move" and is_finite(arrival_facing): u.facing = arrival_facing
	world.emit_event("order_completed", {"unit_id": u.id, "job": old_job})

func _change_posture(u: Dictionary, value: int) -> void:
	if int(u.posture) == value: return
	u.posture_timer = absf(float(u.posture) - value) * 0.35
	u.posture = value; u.stability = 0.0
	u["aim_progress"] = 0.0; u["aim_elapsed"] = 0.0; u["aim_fraction"] = 0.0; u.burst_left = 0

func _ensure_unit(u: Dictionary) -> void:
	_init_unit(u)

func _publish_action_stage(world, u: Dictionary) -> void:
	var old_job: String = u.get("action_job", "")
	var old_stage: String = u.get("action_stage", "")
	if old_job == String(u.job) and old_stage == String(u.stage): return
	u.action_job = String(u.job); u.action_stage = String(u.stage)
	world.emit_event("unit_action_stage", {"unit_id": int(u.id), "entity_id": int(u.id), "pos": Vector2(u.pos), "team": int(u.team), "job": String(u.job), "stage": String(u.stage), "previous_job": old_job, "previous_stage": old_stage, "target_id": int(u.rescued_id), "station_id": int(u.station_id)})

func update(world, dt: float) -> void:
	_stand_cache.clear(); _stand_scope = use_update_query_cache
	_refresh_traffic(world)
	var ordered: Array = world.units.duplicate()
	ordered.sort_custom(func(a, b): return int(a.id) < int(b.id))
	for u in ordered:
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
	_refresh_traffic(world)
	for u in ordered:
		if u.dead or not u.conscious or int(u.carrier_id) >= 0: continue
		if u.job == "rout":
			if world.time_s >= float(u.rout_until) and (u.team == 0 or float(u.suppression) < 40.0):
				u.job = "idle"; u.path = PackedVector2Array(); u.pressure_level = 0; u.cower = false; u.pressure_checked_at = world.time_s; u.status = "未征召" if u.team == 0 else "重新推进"
				u.ai_next = 0.0
		elif u.team == 1 and not bool(u.traffic_yield) and world.time_s >= float(u.ai_next):
			u.ai_next = world.time_s + 0.25; _enemy_ai(world, u)
		elif u.team == 0 and not u.drafted and not bool(u.traffic_yield) and world.time_s >= float(u.ai_next):
			u.ai_next = world.time_s + 0.25; _standby_ai(world, u)
		_auto_posture(world, u)
		if can_act(world, u, "move").ok: _move(world, u, dt)
		if not bool(u.move_active) and not bool(u.traffic_yield):
			var action := "operate" if u.job == "operate" and u.stage == "station" else ("treat" if u.job == "treat" else "rescue" if u.job == "rescue" else "move")
			var allowed := can_act(world, u, action)
			u.action_pause_reason = String(allowed.reason)
			if allowed.ok: _work(world, u, dt)
			elif not u.path.is_empty() or u.job != "idle": u.status = String(allowed.reason)
		var q: float = float(u.suppression) / 100.0
		var cap: float = (1.0 - 0.5 * q) * (0.2 if u.velocity.length_squared() > 0.0001 else 1.0)
		var rate: float = 0.5 * float(C.STYLE_RECOVERY[int(u.style)]) * (1.0 - 0.65 * q)
		u.stability = minf(cap, float(u.stability) + rate * dt)
		if bool(u.cower) or float(u.posture_timer) > 0.0: u.stability = 0.0
	for s in world.supplies:
		if int(s.carried_by) >= 0:
			var carrier: Dictionary = world.entity(int(s.carried_by))
			if not carrier.is_empty(): s.pos = carrier.pos
	for u in world.units:
		_publish_action_stage(world, u)
		if int(u.carrier_id) >= 0:
			var carrier: Dictionary = world.entity(int(u.carrier_id))
			if not carrier.is_empty(): u.pos = carrier.pos; u.velocity = carrier.velocity

	_stand_scope = false; _stand_cache.clear()

func finalize(world) -> void:
	for u in world.units:
		_init_unit(u)
		_update_life(world, u)
		if not u.dead and u.conscious: _update_pressure(world, u)
		# Combat reports empty rifles after its update. Empty enemy rifles instead
		# continue a visible structural assault; pressure and rout keep precedence.
		if u.team == 1 and not u.dead and u.conscious and not bool(u.cower) and u.job != "rout" and int(u.loaded) <= 0 and int(u.reserve) <= 0 and int(u.melee_target_id) >= 0:
			var assault: Dictionary = world.entity(int(u.melee_target_id))
			if not assault.is_empty() and not assault.destroyed and assault.hp > 0:
				u.status = "近战攻击" + str(assault.name) if _structure_distance(u.pos, assault) <= 0.85 else "空弹接近"
		if int(u.station_id) >= 0:
			var b: Dictionary = world.entity(int(u.station_id))
			if b.is_empty() or b.destroyed or b.hp <= 0: _cancel_job(world, u)
		_publish_action_stage(world, u)

func _update_life(world, u: Dictionary) -> void:
	if u.dead: return
	if float(u.hp) <= 0.0:
		u.hp = 0.0; u.dead = true; u.conscious = false
		_cancel_job(world, u, false); u.status = "阵亡"; u.posture = 2
		_release_occupancy(u)
		if int(u.carrier_id) >= 0:
			var carrier: Dictionary = world.entity(int(u.carrier_id))
			if not carrier.is_empty(): _cancel_job(world, carrier)
			u.carrier_id = -1
		world.emit_event("unit_state_changed", {"unit_id": u.id, "state": "dead", "pos": u.pos})
	elif u.conscious and float(u.hp) < float(u.max_hp) * 0.25:
		u.conscious = false; world.combat_system._interrupt_reload(u, float(C.rifle().reload)); _cancel_job(world, u); u.posture = 2; u.status = "昏迷"; u.stability = 0.0
		_release_occupancy(u)
		world.emit_event("unit_state_changed", {"unit_id": u.id, "state": "unconscious", "pos": u.pos})
	elif not u.conscious and float(u.hp) > float(u.max_hp) * 0.35:
		if int(u.carrier_id) < 0:
			var point := _nearest_free_center(world, u, u.pos)
			if point == Vector2.INF: u.wake_pending = true; return
			u.pos = point; u.prev_pos = point
		u.wake_pending = false
		u.conscious = true; u.status = "已苏醒"; u.drafted = false; u.ai_next = 0.0
		if not u.forced_prone and float(u.suppression) < 60.0: _change_posture(u, int(u.posture_mode) if int(u.posture_mode) >= 0 else 0)
		if int(u.carrier_id) < 0: occupied_cells[_cell(u.pos)] = int(u.id); reserved_cells[_cell(u.pos)] = int(u.id)
		world.emit_event("unit_state_changed", {"unit_id": u.id, "state": "awake", "pos": u.pos})

# One pressure update may be observed in update and finalize; release time is
# measured from the world clock so it is never counted twice in one step.
func _update_pressure(world, u: Dictionary) -> void:
	u.suppression = clampf(float(u.suppression), 0.0, 100.0)
	var now: float = world.time_s
	u.pressure_checked_at = now
	if u.job == "rout": return
	var level := int(u.get("pressure_level", 0))
	var required := 2 if float(u.suppression) >= 60.0 else (1 if float(u.suppression) >= 30.0 else 0)
	if level < required:
		_enter_pressure(world, u, required)
		level = required
	if level == 2 and int(u.posture) == 2 and float(u.posture_timer) <= 0.0:
		if float(u.pressure_ready_since) < 0.0: u.pressure_ready_since = now
		var ready: float = float(u.pressure_ready_since) + 0.75
		if float(u.suppression) >= 85.0 and now + 0.000001 >= ready and float(u.pressure_event_time) + 0.000001 >= ready:
			_enter_pressure(world, u, 3); level = 3
	elif level == 3 and float(u.posture_timer) <= 0.0:
		if float(u.pressure_ready_since) < 0.0: u.pressure_ready_since = now
		var ready: float = float(u.pressure_ready_since) + 0.75
		if float(u.suppression) >= 100.0 and now + 0.000001 >= ready and float(u.pressure_event_time) + 0.000001 >= ready:
			_start_rout(world, u); return
	if level in [1, 2, 3]:
		var threshold: float = [0.0, 25.0, 50.0, 70.0][level]
		if float(u.suppression) < threshold:
			if float(u.pressure_release_since) < 0.0: u.pressure_release_since = now
			u.pressure_release_timer = now - float(u.pressure_release_since)
			if float(u.pressure_release_timer) + 0.000001 >= 1.5:
				var next_level := 2 if float(u.suppression) >= 50.0 else (1 if float(u.suppression) >= 25.0 else 0)
				_enter_pressure(world, u, next_level)
				_auto_posture(world, u)
		else: u.pressure_release_timer = 0.0; u.pressure_release_since = -1.0

func _interrupt_action(world, u: Dictionary) -> void:
	u.stability = 0.0; u.burst_left = 0
	u["aim_progress"] = 0.0; u["aim_elapsed"] = 0.0; u["aim_fraction"] = 0.0
	world.combat_system._interrupt_reload(u, float(C.rifle().reload))
	if u.stage in ["pickup_patient", "drop_patient", "treatment"]: u.job_timer = 0.0
	if int(u.station_id) >= 0:
		var b: Dictionary = world.entity(int(u.station_id))
		if not b.is_empty():
			b.aim_progress = 0.0; b["aim_elapsed"] = 0.0; b["aim_fraction"] = 0.0; b.burst_left = 0
			world.combat_system._interrupt_reload(b, 10.0 if b.kind == "mortar" else float(C.machine_gun().reload))

func _enter_pressure(world, u: Dictionary, level: int) -> void:
	var old_level: int = int(u.get("pressure_level", 0))
	var was_cower: bool = bool(u.get("cower", false))
	u.pressure_level = level; u.cower = level == 3; u.forced_prone = level in [2, 3]
	u.pressure_entered = world.time_s; u.pressure_release_timer = 0.0; u.pressure_ready_since = -1.0; u.pressure_release_since = -1.0; u.auto_posture_next = 0.0
	var wanted := maxi(int(u.posture), mini(2, level)) if level > old_level else maxi(mini(2, level), int(u.posture_mode) if int(u.posture_mode) >= 0 else int(u.posture))
	var changed := wanted != int(u.posture) or was_cower != bool(u.cower)
	if wanted != int(u.posture): _change_posture(u, wanted)
	elif was_cower != bool(u.cower): u.posture_timer = 0.35
	if changed: _interrupt_action(world, u)
	u.status = {0: "压制解除", 1: "受压蹲伏", 2: "受压卧倒", 3: "蜷缩避弹"}.get(level, "")
	world.emit_event("unit_state_changed", {"unit_id": int(u.id), "state": "pressure_released" if level == 0 else "cowering" if level == 3 else "suppressed", "pressure_level": level, "posture": int(u.posture), "pos": Vector2(u.pos), "interrupted": changed})

func _start_rout(world, u: Dictionary) -> void:
	_cancel_job(world, u, false)
	u.drafted = false; u.rout_until = world.time_s + 10.0; u.forced_prone = false; u.forced_until = 0.0
	u.pressure_level = 4; u.cower = false; u.pressure_release_timer = 0.0; u.pressure_ready_since = -1.0
	u.pressure_entered = world.time_s
	u.job = "rout"; u.status = "溃逃"; _change_posture(u, 0)
	var destination := _escape_goal(world, u)
	if destination.x >= 0 and _can_stand(world, destination) and _reachable(u.pos, destination): _start_path(world, u, destination)
	world.emit_event("unit_state_changed", {"unit_id": u.id, "state": "routed", "until": u.rout_until, "pressure_level": 4, "pos": Vector2(u.pos)})

func _escape_goal(world, u: Dictionary) -> Vector2:
	var previous_stand_scope := _stand_scope
	var previous_placement_scope := _placement_scope
	if use_escape_query_cache:
		if not _stand_scope: _stand_cache.clear(); _stand_scope = true
		if use_placement_cache and not _placement_scope: _fill_placement_cache(world); _placement_scope = true
	var chances: Dictionary = {}
	var context: Dictionary = world.combat_system.cover_query_context(world) if use_escape_query_cache else {}
	var copy := u.duplicate(); copy.posture = 0
	var threat := _nearest_opponent(world, u)
	var incoming: Vector2 = Vector2(u.get("threat_origin", threat.get("pos", Vector2(u.pos) + Vector2.UP * 20.0)))
	var choices: Array[Vector2] = []
	var base := _cell(u.pos)
	for y in range(maxi(0, base.y - 12), mini(C.MAP_SIZE.y, base.y + 13)):
		for x in range(maxi(0, base.x - 12), mini(C.MAP_SIZE.x, base.x + 13)):
			var point := Vector2(x + 0.5, y + 0.5)
			if point.distance_squared_to(u.pos) <= 144.0: choices.append(point)
	for point in world.medical_slots:
		if not choices.has(point): choices.append(point)
	choices.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	var best := Vector2.INF; var best_risk := INF; var best_length := INF
	for point in choices:
		if not _destination_free(world, point, [int(u.id)]): continue
		var path := navigation.get_point_path(_cell(u.pos), _cell(point))
		if path.is_empty(): continue
		var length := 0.0; var previous: Vector2 = u.pos
		for waypoint in path: length += previous.distance_to(waypoint); previous = waypoint
		var protection: float = _escape_protection(world, copy, incoming, point, chances, context)
		var exposure := 0.0
		for fraction in [0.25, 0.5, 0.75]:
			var index := mini(path.size() - 1, floori(float(path.size()) * fraction))
			exposure += 1.0 - _escape_protection(world, copy, incoming, path[index], chances, context)
		var safe_bonus := 0.2 if C.MEDICAL_RECT.has_point(point) else 0.0
		var risk := (1.0 - protection) * 2.0 + exposure / 3.0 - safe_bonus
		if risk < best_risk - 0.000001 or (absf(risk - best_risk) <= 0.000001 and length < best_length - 0.000001):
			best = point; best_risk = risk; best_length = length
	if not previous_stand_scope: _stand_scope = false; _stand_cache.clear()
	if not previous_placement_scope: _placement_scope = false; _placement_blockers.clear()
	return best if best != Vector2.INF else _center(u.pos)

func _escape_protection(world, copy: Dictionary, incoming: Vector2, point: Vector2, chances: Dictionary, context: Dictionary) -> float:
	if use_escape_query_cache and chances.has(point): return float(chances[point])
	copy.pos = point
	var cover: Dictionary = world.combat_system.cover_for_context(world, copy, incoming, context) if use_escape_query_cache else world.cover_for(copy, incoming)
	var result: float = float(cover.get("chance", 0.0))
	if use_escape_query_cache: chances[point] = result
	return result

func _standby_ai(world, u: Dictionary) -> void:
	if world.time_s < float(u.rout_until): return
	var threat := _nearest_opponent(world, u)
	if not threat.is_empty() and (u.pos.distance_to(threat.pos) < 16.0 or world.time_s - float(u.last_threat) < 2.0):
		if u.job != "flee":
			u.job = "flee"; u.status = "退向后方"; _start_path(world, u, _escape_goal(world, u))
	elif u.job == "flee" and u.path.is_empty(): u.job = "idle"; u.status = "未征召"

func _move(world, u: Dictionary, dt: float) -> void:
	_resume_yield(world, u)
	if u.path.is_empty() and not bool(u.move_active): return
	if not u.path.is_empty() and int(u.nav_revision) != nav_revision:
		if not _start_path(world, u, u.goal): return
	var origin: Vector2 = u.pos
	var remaining: float = dt
	while remaining > 0.000001:
		var point: Vector2
		if bool(u.move_active): point = Vector2(u.move_to) + Vector2(0.5, 0.5)
		else:
			if int(u.path_index) >= u.path.size(): break
			point = u.path[int(u.path_index)]
			if u.pos.distance_to(point) < 0.000001: u.path_index += 1; continue
			# Imported/debug paths also obey adjacent cell transitions.
			var delta_cell: Vector2i = _cell(point) - _cell(u.pos)
			if maxi(absi(delta_cell.x), absi(delta_cell.y)) > 1: point = Vector2(_cell(u.pos) + Vector2i(clampi(delta_cell.x, -1, 1), clampi(delta_cell.y, -1, 1))) + Vector2(0.5, 0.5)
			if int(u.path_index) == u.path.size() - 1 and _body_at(world, _cell(point), int(u.id)):
				_reject(world, u, "落点被伤员或遗体占用"); break
			if not _reserve_edge(world, u, point): _handle_traffic_block(world, u, point, remaining); break
		var speed := _movement_speed(world, u)
		var delta: Vector2 = point - Vector2(u.pos)
		var travel: float = minf(delta.length(), speed * remaining)
		var previous_cell := _cell(u.pos)
		u.pos = Vector2(u.pos) + delta.normalized() * travel
		var current_cell := _cell(u.pos)
		if current_cell != previous_cell and int(occupied_cells.get(previous_cell, -1)) == int(u.id): occupied_cells.erase(previous_cell)
		occupied_cells[current_cell] = int(u.id)
		remaining = maxf(0.0, remaining - travel / maxf(speed, 0.000001))
		u.blocked_time = 0.0
		if u.pos.distance_to(point) < 0.000001:
			u.pos = point; _release_edge(u)
			if int(u.path_index) < u.path.size() and u.pos.distance_to(u.path[int(u.path_index)]) < 0.000001: u.path_index += 1
		else: break
	if int(u.path_index) >= u.path.size(): u.path = PackedVector2Array(); u.path_index = 0
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
	if not obstacle.is_empty() and _barrier_type(obstacle) == "cover": speed *= 0.5
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

# This query does not create reservations or mutate a unit. An override asks
# about a hypothetical settled pose, while retaining pressure restrictions.
func can_act(world, u: Dictionary, action: String, posture_override: int = -1) -> Dictionary:
	if u.is_empty() or not u.has("conscious") or bool(u.get("dead", false)) or not bool(u.get("conscious", false)) or float(u.get("hp", 0.0)) <= 0.0: return _bad("人员失去行动能力")
	if int(u.get("carrier_id", -1)) >= 0: return _bad("人员正在被搬运")
	if not action in ["fire", "reload", "operate", "move", "treat", "rescue"]: return _bad("未知动作")
	if bool(u.get("cower", false)): return _bad("蜷缩中，行动暂停")
	if int(u.get("pressure_level", 0)) == 4 or String(u.get("job", "")) == "rout":
		if action != "move": return _bad("溃逃中，无法执行该动作")
	elif world.time_s < float(u.get("rout_until", 0.0)) and action != "move": return _bad("溃逃冷却中")
	var posture := int(u.get("posture", 0)) if posture_override < 0 else posture_override
	if posture < 0 or posture > 2: return _bad("姿态无效")
	if int(u.get("pressure_level", 0)) in [1, 2] and posture < int(u.pressure_level): return _bad("受压制限制姿态")
	if posture_override < 0 and float(u.get("posture_timer", 0.0)) > 0.0: return _bad("姿态切换中")
	if action == "operate" and posture > 1: return _bad("卧倒无法操作工事，保留岗位")
	if action in ["fire", "reload"] and int(u.get("station_id", -1)) >= 0 and posture > 1: return _bad("卧倒无法操作工事，保留岗位")
	return {"ok": true, "reason": ""}

func _auto_posture(world, u: Dictionary) -> void:
	if bool(u.get("cower", false)) or float(u.posture_timer) > 0.0 or u.job == "rout": return
	var minimum := mini(2, int(u.get("pressure_level", 0)))
	if int(u.posture_mode) >= 0:
		_change_posture(u, maxi(int(u.posture_mode), minimum)); return
	# Movement keeps priority; automatic defensive choices never change position.
	if not u.path.is_empty() or bool(u.move_active) or u.job in ["move", "resupply", "rescue", "treat", "flee"]:
		_change_posture(u, minimum); return
	if world.time_s < float(u.get("auto_posture_next", 0.0)): return
	u.auto_posture_next = world.time_s + 0.1
	var station: Dictionary = world.entity(int(u.get("station_id", -1)))
	if not station.is_empty() and String(u.stage) != "station": _change_posture(u, minimum); return
	# Use the firing system's own selector for each hypothetical settled pose.
	# The selector may discard dead intentions; copies prevent a pose query
	# from mutating either the soldier or a station's actual target.
	var weapon: Dictionary = C.rifle() if station.is_empty() else C.machine_gun()
	for posture in [2, 1, 0]:
		if posture < minimum or not can_act(world, u, "fire", posture).ok: continue
		var copy := u.duplicate(true); copy.posture = posture; copy.posture_timer = 0.0
		var station_copy := station.duplicate(true)
		var target: Dictionary = world.combat_system._choose_target(world, copy, weapon, station_copy)
		if not target.is_empty(): _change_posture(u, posture); return
	# A quiet station still chooses its lowest compatible working posture.
	_change_posture(u, maxi(minimum, 1) if not station.is_empty() else minimum)

func _work(world, u: Dictionary, dt: float) -> void:
	if u.team == 1: _melee_work(world, u, dt)
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
			var seat: int = maxi(0, int(u.station_seat))
			_start_path(world, u, b.crew_points[mini(seat, b.crew_points.size() - 1)])
		else: _finish_job(world, u)

func _medical_work(world, u: Dictionary, dt: float) -> void:
	var patient: Dictionary = world.entity(int(u.rescued_id))
	if patient.is_empty() or patient.dead: _finish_job(world, u, "救护目标已死亡"); return
	if not u.path.is_empty(): return
	if u.stage == "approach_patient":
		if u.pos.distance_to(patient.pos) > INTERACTION_DISTANCE:
			var point := _near_unit_position(world, u.pos, patient, int(u.id))
			if point.x < 0: _reject(world, u, "伤员无法接近")
			else: _start_path(world, u, point)
			return
		if u.job == "rescue": u.stage = "pickup_patient"; u.job_timer = 0.0; u.status = "抱起伤员"
		else: _start_treatment(world, u, patient)
	elif u.stage == "pickup_patient":
		u.job_timer += dt
		if float(u.job_timer) + 0.000001 >= 1.0:
			patient.carrier_id = int(u.id); u.stage = "carry_patient"; u.job_timer = 0.0; u.status = "搬运伤员"
			var point := _adjacent_position(world, u.pos, world.medical_slots[int(u.medical_slot)], int(u.id))
			if point.x < 0: _reject(world, u, "救护位置被占用")
			else: _start_path(world, u, point)
	elif u.stage == "carry_patient": u.stage = "drop_patient"; u.job_timer = 0.0; u.status = "安置伤员"
	elif u.stage == "drop_patient":
		var bed: Vector2 = world.medical_slots[int(u.medical_slot)]
		if not _destination_free(world, bed, [int(u.id), int(patient.id)]): u.status = "等待救护位置腾空"; return
		u.job_timer += dt
		if float(u.job_timer) + 0.000001 >= 1.0:
			patient.carrier_id = -1; patient.pos = bed; patient.prev_pos = patient.pos
			if _active(patient): occupied_cells[_cell(bed)] = int(patient.id); reserved_cells[_cell(bed)] = int(patient.id)
			_start_treatment(world, u, patient)
	elif u.stage == "treatment":
		if float(patient.bleed_rate) <= 0: _finish_job(world, u, "已稳定"); return
		if u.pos.distance_to(patient.pos) > INTERACTION_DISTANCE: _reject(world, u, "急救目标已离开"); return
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

func _fill_placement_cache(world) -> void:
	_placement_blockers.clear()
	for other in world.units:
		if int(other.carrier_id) >= 0: continue
		_placement_add(_cell(other.pos), int(other.id))
		if not _active(other): continue
		if bool(other.get("move_active", false)):
			_placement_add(Vector2i(other.move_from), int(other.id))
			_placement_add(Vector2i(other.move_to), int(other.id))
		if not other.path.is_empty(): _placement_add(_cell(other.goal), int(other.id))
		if int(other.station_id) >= 0:
			var station: Dictionary = world.entity(int(other.station_id))
			if not station.is_empty():
				var seat: int = maxi(0, int(other.get("station_seat", 0)))
				_placement_add(_cell(station.crew_points[mini(seat, station.crew_points.size() - 1)]), int(other.id))
	for slot in world.medical_reservations:
		_placement_add(_cell(world.medical_slots[int(slot)]), int(world.medical_reservations[slot]))

func _enemy_ai(world, u: Dictionary) -> void:
	if use_placement_cache:
		_fill_placement_cache(world); _placement_scope = true
	_enemy_ai_live(world, u)
	_placement_scope = false
	_placement_blockers.clear()

func _placement_add(cell: Vector2i, owner: int) -> void:
	if not _placement_blockers.has(cell): _placement_blockers[cell] = {}
	_placement_blockers[cell][owner] = true

func _enemy_ai_live(world, u: Dictionary) -> void:
	if bool(u.cower) or world.time_s < float(u.rout_until): return
	if int(u.loaded) <= 0 and int(u.reserve) <= 0:
		u.target_id = -1; u.ai_target_id = -1
		_advance_to_structure(world, u, true); return
	u.melee_target_id = -1; u.melee_progress = 0.0
	var target: Dictionary = {}; var priority := -INF; var best_distance := INF
	for candidate in world.units:
		if candidate.team == u.team or candidate.dead or not candidate.conscious or int(candidate.carrier_id) >= 0: continue
		var distance: float = u.pos.distance_to(candidate.pos)
		if distance > 24.0 or not _standing_line(world, u, candidate): continue
		var level: float = 3.0 if int(candidate.station_id) >= 0 else 2.0
		if _better_target(level, distance, int(candidate.id), priority, best_distance, target):
			target = candidate; priority = level; best_distance = distance
	var core: Dictionary = world.core()
	var core_distance: float = u.pos.distance_to(core.pos)
	if core.hp > 0 and core_distance <= 24.0 and _standing_line(world, u, core) and _better_target(1.0, core_distance, int(core.id), priority, best_distance, target): target = core
	if not target.is_empty():
		var previous: Dictionary = world.entity(int(u.ai_target_id))
		if previous.is_empty() or previous.get("dead", false) or previous.get("destroyed", false) or u.pos.distance_to(previous.pos) > 24.0 or not _standing_line(world, u, previous): u.ai_hold_until = 0.0
		u.target_id = int(target.id)
		u.ai_target_id = int(target.id)
		if world.time_s >= float(u.ai_hold_until):
			var covered: Vector2 = _cover_destination(world, u, target)
			if covered.distance_to(u.pos) > 0.65: _ai_move(world, u, covered)
			else: u.path = PackedVector2Array()
			u.ai_hold_until = world.time_s + 2.0
		u.status = "重装推进交火" if u.kind == "heavy" and not u.path.is_empty() else "掩护交火"
		return
	u.target_id = -1; u.ai_target_id = -1
	_advance_to_structure(world, u, false)

func _better_target(priority: float, distance: float, id: int, current_priority: float, current_distance: float, current: Dictionary) -> bool:
	if current.is_empty() or priority > current_priority: return true
	if priority < current_priority: return false
	return distance < current_distance - 0.00001 or (absf(distance - current_distance) <= 0.00001 and id < int(current.id))

func _advance_to_structure(world, u: Dictionary, melee: bool) -> void:
	var target: Dictionary = world.core()
	var goal: Vector2 = _approach_position(world, u.pos, target, int(u.id))
	if goal.x < 0:
		target = _blocking_structure(world, u, world.core().pos)
		if target.is_empty(): u.path = PackedVector2Array(); u.status = "没有可达攻击目标"; return
		goal = _approach_position(world, u.pos, target, int(u.id))
	if not melee:
		goal = _structure_fire_position(world, u, target)
	if melee:
		if int(u.melee_target_id) != int(target.id): u.melee_progress = 0.0
		u.melee_target_id = int(target.id)
		if _structure_distance(u.pos, target) <= 0.85:
			u.path = PackedVector2Array(); u.job = "advance"; u.status = "近战攻击" + str(target.name); return
	elif target.kind != "core" and u.pos.distance_to(target.pos) <= 24.0 and _standing_line(world, u, target):
		u.target_id = int(target.id); u.path = PackedVector2Array(); u.status = "攻击障碍"; return
	if goal.x >= 0: _ai_move(world, u, goal)
	u.status = "空弹接近" if melee else ("重装推进" if u.kind == "heavy" else "推进")

func _structure_distance(position: Vector2, b: Dictionary) -> float:
	var rect := Rect2(b.rect)
	return position.distance_to(Vector2(clampf(position.x, rect.position.x, rect.end.x), clampf(position.y, rect.position.y, rect.end.y)))

func _melee_work(world, u: Dictionary, dt: float) -> void:
	if int(u.loaded) > 0 or int(u.reserve) > 0 or int(u.melee_target_id) < 0: return
	var target: Dictionary = world.entity(int(u.melee_target_id))
	if target.is_empty() or target.destroyed or float(target.hp) <= 0 or _structure_distance(u.pos, target) > 0.85:
		u.melee_progress = 0.0; return
	u.melee_progress = float(u.melee_progress) + dt
	while float(u.melee_progress) + 0.000001 >= 1.0 and float(target.hp) > 0:
		u.melee_progress = maxf(0.0, float(u.melee_progress) - 1.0)
		var damage := minf(5.0, float(target.hp))
		target.hp = maxf(0.0, float(target.hp) - damage); world.stats.damage += damage
		world.emit_event("damage", {"entity_id": target.id, "shooter_id": u.id, "pos": target.pos, "team": u.team, "target_team": 0, "weapon_kind": "melee", "amount": damage, "hp": target.hp, "bleeding": false})

func _standing_line(world, u: Dictionary, target: Dictionary) -> bool:
	var copy := u.duplicate(); copy.posture = 0
	var pose: Dictionary = Pose.aimed_rifle(copy.pos, target.pos, 0)
	if not world.combat_system._muzzle_clear(world, copy.pos, pose.muzzle): return false
	copy.pos = pose.muzzle
	return world.combat_system.has_line_of_fire(world, copy, target)

func _structure_fire_position(world, u: Dictionary, target: Dictionary) -> Vector2:
	var best := Vector2(-1, -1)
	var distance := INF
	var rect: Rect2i = target.rect
	for ring in range(1, 4):
		for y in range(rect.position.y - ring, rect.end.y + ring):
			for x in range(rect.position.x - ring, rect.end.x + ring):
				var point := Vector2(x + 0.5, y + 0.5)
				var cost: float = u.pos.distance_squared_to(point)
				# Preserve candidate order and strict tie rule, but skip expensive
				# pure queries for candidates that cannot improve the same result.
				if not cost < distance or point.distance_to(target.pos) > 24.0: continue
				if not _destination_free(world, point, [int(u.id)]) or not _reachable(u.pos, point): continue
				var copy := u.duplicate(); copy.pos = point
				if _standing_line(world, copy, target): best = point; distance = cost
	return best

func _ai_move(world, u: Dictionary, destination: Vector2) -> void:
	u.job = "advance"
	if not u.path.is_empty() and u.goal.distance_to(destination) < 0.25: return
	if u.pos.distance_to(destination) < 0.2: u.path = PackedVector2Array(); return
	if _can_stand(world, destination) and _reachable(u.pos, destination): _start_path(world, u, destination)

func _cover_destination(world, u: Dictionary, target: Dictionary) -> Vector2:
	var best: Vector2 = u.pos
	var core_goal := _approach_position(world, u.pos, world.core(), int(u.id))
	var current_score := _cover_score(world, u, target, u.pos, core_goal)
	var best_score: float = current_score
	var positions: Array[Vector2] = []
	for b in world.buildings:
		if b.destroyed or _barrier_type(b) != "cover" or b.pos.distance_to(u.pos) > 8.0: continue
		for x in range(b.rect.position.x, b.rect.end.x):
			positions.append(Vector2(x + 0.5, b.rect.position.y - 0.5)); positions.append(Vector2(x + 0.5, b.rect.end.y + 0.5))
		for y in range(b.rect.position.y, b.rect.end.y):
			positions.append(Vector2(b.rect.position.x - 0.5, y + 0.5)); positions.append(Vector2(b.rect.end.x + 0.5, y + 0.5))
	# Open firing positions let a flanker leave a gun's arc and let heavy troops
	# advance even where no sandbags exist. They are still scored, not waypoints.
	if u.kind in ["flanker", "heavy"]:
		for radius in [2.0, 4.0, 6.0]:
			for index in range(8): positions.append(_center(u.pos + Vector2.from_angle(index * TAU / 8.0) * radius))
	for point in positions:
		if not _destination_free(world, point, [int(u.id)]) or point.distance_to(u.pos) > 6.0 + 0.00001: continue
		var score: float = _cover_score(world, u, target, point, core_goal)
		if score > best_score + 0.00001: best = point; best_score = score
	return best if best_score >= current_score + 0.5 else Vector2(u.pos)

func _path_length(from: Vector2, to: Vector2) -> float:
	if to.x < 0 or not _reachable(from, to): return INF
	var path: PackedVector2Array = navigation.get_point_path(_cell(from), _cell(to))
	var length := 0.0; var previous := from
	for index in range(1, path.size()):
		var waypoint: Vector2 = to if index == path.size() - 1 else path[index]
		length += previous.distance_to(waypoint); previous = waypoint
	return length if path.size() > 1 else from.distance_to(to)

func _cover_score(world, u: Dictionary, target: Dictionary, point: Vector2, core_goal: Vector2 = Vector2(-1, -1)) -> float:
	var copy := u.duplicate(); copy.pos = point; copy.posture = 0
	if point.distance_to(target.pos) > 24.0 or not _standing_line(world, copy, target): return -INF
	var distance := _path_length(u.pos, point)
	if not is_finite(distance): return -INF
	var incoming: Vector2 = target.pos
	if target.has("conscious"):
		var station: Dictionary = world.entity(int(target.get("station_id", -1)))
		if not station.is_empty() and station.kind == "mg" and target.get("stage", "") == "station": incoming = Pose.station(station.pos, Vector2(point - station.pos).angle(), "mg").muzzle
		else: incoming = Pose.aimed_rifle(target.pos, point, 2 if not target.conscious else int(target.posture)).muzzle
	var protection: Dictionary = world.cover_for(copy, incoming) if target.has("conscious") else {"chance": 0.0}
	var score: float = float(protection.get("chance", 0.0)) * (1.0 if u.kind == "heavy" else 4.0) - distance * 0.1
	if u.kind == "heavy" and core_goal.x >= 0:
		var start_to_core := _path_length(u.pos, core_goal)
		var point_to_core := _path_length(point, core_goal)
		if is_finite(start_to_core) and is_finite(point_to_core): score += (start_to_core - point_to_core) * 0.25
	if u.kind == "flanker" and target.has("conscious") and target.conscious:
		var outside := true
		for b in world.stations():
			if b.kind != "mg" or b.destroyed: continue
			var direction: Vector2 = point - b.pos
			if direction.length() <= 32.0 and absf(wrapf(direction.angle() - float(b.facing), -PI, PI)) <= float(b.arc) * 0.5: outside = false; break
		if outside: score += 2.0
	return score

func _blocking_structure(world, u: Dictionary, goal: Vector2) -> Dictionary:
	var length: float = u.pos.distance_to(goal)
	for i in range(1, ceili(length * 4.0)):
		var point: Vector2 = u.pos.lerp(goal, i / maxf(1.0, length * 4.0))
		var b: Dictionary = world.building_at(_cell(point))
		# The first solid building on this ray is itself the intended target.
		# Its near face must not be rejected as the attacker's own cover.
		if not b.is_empty() and _barrier_type(b) == "wall" and not b.destroyed: return b
	return {}

