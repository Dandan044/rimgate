extends RefCounted

const Config = preload("res://scripts/sim/battle_config.gd")
const Pose = preload("res://scripts/sim/weapon_pose.gd")
const EPS := 0.00001
const COVER_DISTANCE := 0.85
const NEAR_MISS_DISTANCE := 0.75
const MORTAR_LOAD_WORK := 10.0
const MORTAR_AIM_TIME := 4.0
const MORTAR_FLIGHT_TIME := 3.0
const BLAST_RADIUS := 4.0
const QUERY_CELL_SIZE := 4.0
const QUERY_PADDING := 0.001
const SEGMENT_TOLERANCE := 0.0001
const FRIENDLY_LOCAL_RADIUS := 1.4142135623730951
const IDLE_RELOAD_DELAY := 1.5

# The exhaustive path remains available for deterministic equivalence checks.
var use_spatial_index: bool = true
var _queries_ready: bool = false
var _building_grid: Dictionary = {}
var _unit_grid: Dictionary = {}
var _query_buildings: Array = []
var _query_units: Array = []
var _building_marks: PackedInt32Array = PackedInt32Array()
var _unit_marks: PackedInt32Array = PackedInt32Array()
var _query_serial: int = 0
# Rendering output for the most recent advance pass, separate from live bullets.
var finished_projectiles: Array[Dictionary] = []


func update(world, dt: float) -> void:
	_prepare_queries(world)
	for u in world.units:
		_ensure_weapon(u)
		_update_weapon_clock(u, dt)
		_update_rifle(world, u, dt)
	for b in world.buildings:
		if not _building_alive(b):
			continue
		_ensure_weapon(b)
		if b.kind == "mg":
			_update_weapon_clock(b, dt)
			_update_machine_gun(world, b, dt)
		elif b.kind == "mortar":
			_update_mortar(world, b, dt)
	advance_projectiles(world, dt)


# P belongs only to the firing decision. Geometry and cover never roll it again.
func hit_probability(shooter: Dictionary, target: Dictionary, weapon: Dictionary) -> float:
	var distance: float = Vector2(shooter.pos).distance_to(Vector2(target.pos))
	var ratio: float = clampf(distance / float(weapon.range), 0.0, 1.0)
	var accuracy: float = lerpf(float(weapon.accuracy_near), float(weapon.accuracy_far), ratio)
	var volume: float = 1.0 if _is_building(target) else _volume(target)
	var q: float = clampf(float(shooter.suppression) / 100.0, 0.0, 1.0)
	var stability: float = clampf(float(shooter.stability), 0.0, 1.0)
	var style: int = clampi(int(shooter.style), 0, 2)
	return clampf(accuracy * (0.25 + 0.75 * stability) * volume * (1.0 - 0.4 * q) * _injury_factor(shooter) * float(Config.STYLE_ACCURACY[style]), 0.02, 0.95)


func cover_for(world, unit: Dictionary, from: Vector2) -> Dictionary:
	var result: Dictionary = {"chance": 0.0, "blocked": false, "building_id": -1, "cell": Vector2i(-1, -1), "obstacles": []}
	var survival: float = 1.0
	var volume: float = _volume(unit)
	var obstacles: Array[Dictionary] = _cover_segments(world, from, Vector2(unit.pos), -1, int(unit.id))
	for obstacle in obstacles:
		obstacle["chance"] = 1.0 if bool(obstacle.blocked) else cover_probability(obstacle.entity, volume, float(obstacle.entry_distance))
		survival *= 1.0 - float(obstacle.chance)
		if bool(obstacle.blocked): result.blocked = true
		if int(result.building_id) < 0 and float(obstacle.chance) > 0.0:
			result.building_id = obstacle.building_id
			result.cell = obstacle.cell
	result.chance = 1.0 - survival
	result.obstacles = obstacles
	return result


# Intervals follow the actual ray, not the connected building group.
func _cover_segments(world, start: Vector2, end: Vector2, excluded_id: int = -1, target_id: int = -1) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	var length: float = start.distance_to(end)
	if length <= EPS: return pieces
	for building in _buildings_in_bounds(world, _segment_bounds(start, end)):
		if not _building_alive(building) or _barrier_type(building) == "floor" or int(building.id) in [excluded_id, target_id]: continue
		var rect: Rect2i = building.rect
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var interval: Vector2 = _segment_rect_interval(start, end, Rect2(x, y, 1.0, 1.0))
				if not _positive_crossing(start,end,interval): continue
				var wall: bool = _barrier_type(building) == "wall"
				pieces.append({"t": interval.x, "exit_t": interval.y, "entry_distance": interval.x * length, "exit_distance": interval.y * length, "building_id": int(building.id), "entity": building, "cell": Vector2i(x,y), "blocked": wall, "signature": _cover_signature(building), "members": [int(building.id)]})
	pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.building_id) < int(b.building_id) if absf(float(a.t)-float(b.t)) <= EPS else float(a.t) < float(b.t)
	)
	var merged: Array[Dictionary] = []
	for piece in pieces:
		var found: int = -1
		for i in range(merged.size()-1, -1, -1):
			if String(merged[i].signature) == String(piece.signature) and float(piece.entry_distance) <= float(merged[i].exit_distance) + SEGMENT_TOLERANCE:
				found = i; break
		if found < 0:
			merged.append(piece)
		else:
			merged[found].exit_t = maxf(float(merged[found].exit_t), float(piece.exit_t))
			merged[found].exit_distance = maxf(float(merged[found].exit_distance), float(piece.exit_distance))
			if not merged[found].members.has(int(piece.building_id)): merged[found].members.append(int(piece.building_id))
	return merged


func _cover_signature(building: Dictionary) -> String:
	var strength: float = float(building.get("screening_strength", Config.COVER_VOLUME_SCALE * float(building.get("screen_volume",0.0))))
	return "%s|%s|%.8f|%.8f" % [_barrier_type(building), String(building.get("material", building.get("kind", ""))), float(building.get("height",0.0)), strength]


func _segment_checked(projectile: Dictionary, segment: Dictionary) -> bool:
	for checked in projectile.get("cover_intervals", []):
		if String(checked.signature) == String(segment.signature) and minf(float(checked.end),float(segment.exit_distance)) + SEGMENT_TOLERANCE >= maxf(float(checked.begin),float(segment.entry_distance)):
			return true
	return false


func _mark_segment(projectile: Dictionary, segment: Dictionary) -> void:
	var checked: Array = projectile.get("cover_intervals", [])
	checked.append({"begin":float(segment.entry_distance), "end":float(segment.exit_distance), "signature":String(segment.signature)})
	projectile["cover_intervals"] = checked
	for id in segment.members: projectile.cover_checked[int(id)] = segment.cell


func cover_probability(building: Dictionary, target_volume: float, shooter_distance: float) -> float:
	var strength: float = maxf(0.0, float(building.get("screening_strength", Config.COVER_VOLUME_SCALE * float(building.get("screen_volume", 0.0)))))
	var distance_factor: float = clampf((shooter_distance - Config.COVER_NEAR_DISTANCE) / (Config.COVER_FULL_DISTANCE - Config.COVER_NEAR_DISTANCE), 0.0, 1.0)
	return Config.COVER_CAP * strength / maxf(EPS, strength + maxf(EPS, target_volume)) * distance_factor


func _barrier_type(building: Dictionary) -> String:
	return String(building.get("barrier_type", "wall" if bool(building.get("high", false)) else ("floor" if float(building.get("height", 0.0)) < 0.1 else "cover")))


func _building_crossing(building: Dictionary, start: Vector2, end: Vector2) -> Dictionary:
	# Sample one cell nearest the ray's target; collision remains at first entry.
	var first: float = INF
	var last: float = -INF
	var selected: Vector2i = Vector2i(-1, -1)
	var rect: Rect2i = building.rect
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell: Vector2i = Vector2i(x, y)
			var interval: Vector2 = _segment_rect_interval(start, end, Rect2(Vector2(cell), Vector2.ONE))
			if not _positive_crossing(start,end,interval):
				continue
			first = minf(first, interval.x)
			if interval.y > last + EPS:
				last = interval.y
				selected = cell
	return {} if first == INF else {"t": first, "cell": selected}


func has_line_of_fire(world, shooter: Dictionary, target: Dictionary) -> bool:
	if shooter.is_empty() or target.is_empty():
		return false
	var origin: Vector2 = shooter.pos
	var destination: Vector2 = target.pos
	var target_building_id: int = int(target.id) if _is_building(target) else -1
	for b in world.buildings:
		if not _building_alive(b):
			continue
		if _barrier_type(b) == "wall" and _point_inside_rect(origin,Rect2(b.rect)):
			return false
		if int(b.id) == target_building_id:
			continue
		if _barrier_type(b) == "wall" and _positive_crossing(origin,destination,_segment_rect_interval(origin,destination,Rect2(b.rect))):
			return false
	return true


# Geometry only: automatic posture selection can call this without advancing
# aim, taking a random draw, or changing an intention.
func can_fire_pose(world, shooter: Dictionary, target: Dictionary, station: Dictionary = {}) -> Dictionary:
	if shooter.is_empty() or not _target_alive(target): return {"ok":false,"reason":"目标已失效"}
	var posture: int = _posture(shooter)
	if not station.is_empty() and posture > 1: return {"ok":false,"reason":"当前姿态无法操作工事"}
	var weapon: Dictionary = Config.machine_gun() if not station.is_empty() else Config.rifle()
	var origin: Vector2 = shooter.pos if station.is_empty() else station.pos
	var offset: Vector2 = Vector2(target.pos)-origin
	if not station.is_empty() and String(station.kind) == "mortar":
		if offset.length()<8.0-EPS or offset.length()>40.0+EPS: return {"ok":false,"reason":"目标须距炮位8至40格"}
		var mortar_pose: Dictionary = Pose.station(origin,offset.angle(),"mortar")
		if not _muzzle_clear(world,Vector2(mortar_pose.get("pivot",origin)),Vector2(mortar_pose.muzzle)): return {"ok":false,"reason":"炮口被墙体阻挡"}
		return {"ok":true,"reason":""}
	if not station.is_empty() and absf(wrapf(offset.angle()-float(station.facing),-PI,PI)) > float(station.arc)*.5+EPS: return {"ok":false,"reason":"目标在工事射界之外"}
	var pose: Dictionary = Pose.aimed_rifle(origin,Vector2(target.pos),posture) if station.is_empty() else Pose.station(origin,offset.angle(),"mg")
	var muzzle: Vector2 = pose.muzzle
	var pivot: Vector2 = pose.get("pivot",origin)
	if muzzle.distance_to(Vector2(target.pos)) > float(weapon.range)+EPS: return {"ok":false,"reason":"目标超出射程"}
	if not _muzzle_clear(world,pivot,muzzle): return {"ok":false,"reason":"枪口被墙体阻挡"}
	var source: Dictionary = shooter.duplicate()
	source.pos = muzzle
	if not has_line_of_fire(world,source,target): return {"ok":false,"reason":"墙体阻挡射线"}
	var muzzle_height: float = float(pose.get("muzzle_height",1.5 if not station.is_empty() else float(Config.HEIGHTS[posture])*.8))
	for segment in _cover_segments(world,muzzle,Vector2(target.pos),int(station.get("id",-1)),int(target.id)):
		if not bool(segment.blocked) and float(segment.entry_distance) <= 1.0+SEGMENT_TOLERANCE and float(segment.entity.get("height",0.0)) >= muzzle_height-EPS:
			return {"ok":false,"reason":"低掩体高于当前枪口，无法出射"}
	return {"ok":true,"reason":""}


func query_shot(world, holder_id: int, target_id: int, posture_override: int = -1) -> Dictionary:
	var result: Dictionary = {"ok":false,"reason":"请选择有效射手","ready":false,"ready_reason":"","probability":0.0,"kind":"direct","factors":[],"segments":[],"blockers":[],"exempt_allies":[],"friendly_fire_risk":false}
	var holder: Dictionary = world.entity(holder_id)
	var target: Dictionary = world.entity(target_id)
	if holder.is_empty() or not _target_alive(target):
		result.reason = "目标已失效" if not _target_alive(target) else result.reason
		return result
	var station: Dictionary = holder if _is_building(holder) else {}
	var shooter: Dictionary = holder
	if not station.is_empty():
		if not _building_alive(station) or not String(station.kind) in ["mg","mortar"]: return result
		var crew: Array[Dictionary] = _station_crew(world,station)
		if crew.is_empty(): result.reason="需要先安排工事操作员"; return result
		shooter = crew[0]
	var source: Dictionary = shooter.duplicate()
	if posture_override >= 0: source.posture = posture_override
	var conditions: Dictionary = can_fire_pose(world,source,target,station)
	result.ok = bool(conditions.ok)
	result.reason = String(conditions.reason)
	if not bool(result.ok): return result
	result.ready = true
	if not station.is_empty() and String(shooter.get("stage","")) != "station": result.ready=false; result.ready_reason="操作员尚未到岗"
	elif bool(source.get("dead",false)) or not bool(source.get("conscious",true)): result.ready=false; result.ready_reason="射手失去行动能力"
	elif bool(source.get("cower",false)): result.ready=false; result.ready_reason="蜷缩中，无法行动"
	elif station.is_empty() and not _rifle_job_allowed(world,source): result.ready=false; result.ready_reason="当前工作无法使用单兵武器"
	elif float(source.get("posture_timer",0.0)) > EPS: result.ready=false; result.ready_reason="姿态切换中"
	elif not _action_allowed(world,source,"operate" if not station.is_empty() else "fire"): result.ready=false; result.ready_reason="当前反应或动作不允许开火"
	elif bool(holder.get("hold_fire",false)): result.ready=false; result.ready_reason="已停火"
	elif int(holder.get("reload_reserved",0)) > 0: result.ready=false; result.ready_reason="装填中"
	elif int(holder.get("loaded",0)) <= 0: result.ready=false; result.ready_reason="尚未装弹"
	elif String(holder.get("weapon_state","idle")) == "aiming": result.ready=false; result.ready_reason="正在瞄准"
	elif float(holder.get("weapon_cooldown",0.0)) > EPS or float(holder.get("burst_rest",0.0)) > EPS: result.ready=false; result.ready_reason="武器恢复中"
	if not station.is_empty() and String(station.kind) == "mortar":
		var scatter: float = _mortar_scatter(shooter)
		result.kind = "mortar"
		result.probability = mortar_coverage_probability(scatter,BLAST_RADIUS,0.0)
		result.factors = [{"name":"散布半径","value":scatter,"description":"均匀圆盘散布，按当前稳定度"},{"name":"爆炸半径","value":BLAST_RADIUS,"description":"目标脚点位于爆炸范围内；不预测移动"}]
		return result
	var position: Vector2 = source.pos if station.is_empty() else station.pos
	var pose: Dictionary = Pose.aimed_rifle(position,Vector2(target.pos),_posture(source)) if station.is_empty() else Pose.station(position,(Vector2(target.pos)-position).angle(),"mg")
	var muzzle: Vector2 = pose.muzzle
	var pivot: Vector2 = pose.get("pivot",position)
	var weapon: Dictionary = Config.rifle() if station.is_empty() else Config.machine_gun()
	source.pos = muzzle
	var raw: float = hit_probability(source,target,weapon)
	var ratio: float = clampf(muzzle.distance_to(Vector2(target.pos))/float(weapon.range),0.0,1.0)
	result.factors = [{"name":"距离基础精度","value":lerpf(float(weapon.accuracy_near),float(weapon.accuracy_far),ratio),"description":"从真实枪口到目标"},{"name":"稳定度","value":.25+.75*clampf(float(source.stability),0.0,1.0),"description":"当前快照，不预支未来瞄准收益"},{"name":"目标体积","value":1.0 if _is_building(target) else _volume(target),"description":"实际姿态及蜷缩体积"},{"name":"压制","value":1.0-.4*clampf(float(source.suppression)/100.0,0.0,1.0),"description":"射手当前压制"},{"name":"伤势","value":_injury_factor(source),"description":"射手伤势"},{"name":"作战风格","value":float(Config.STYLE_ACCURACY[clampi(int(source.style),0,2)]),"description":"与火控独立"},{"name":"发射准确率","value":raw,"description":"各精度因素相乘后限制在2%至95%"}]
	var direction: Vector2 = (Vector2(target.pos)-muzzle).normalized()
	var projectile: Dictionary = {"kind":String(weapon.kind),"team":int(source.team),"shooter_id":int(source.id),"target_id":target_id,"start":muzzle,"fire_reference":pivot,"source_building_id":int(station.get("id",-1))}
	projectile["exempt_allies"] = _eligible_allies(world,projectile)
	result.exempt_allies = projectile.exempt_allies.duplicate()
	var path: Dictionary = _query_direct_path(world,projectile,target,muzzle,direction,float(weapon.range),pivot)
	result.segments = path.segments
	result.blockers = path.blockers
	result.friendly_fire_risk = bool(path.friendly_fire_risk)
	result.probability = (1.0 if bool(path.get("contact_target",false)) else raw)*float(path.survival) if bool(path.reaches_target) else 0.0
	if bool(path.get("contact_target",false)): result.factors.append({"name":"枪口或出射首段接触目标","value":1.0,"description":"目标已覆盖发射点，射偏弹也会接触原目标"})
	# Miss samples avoid the original silhouette, but can still strike friends.
	# This deterministic inspection changes no combat RNG or world state.
	if not bool(result.friendly_fire_risk) and raw < 1.0:
		var limits: Vector2 = _miss_limits(muzzle,target,direction)
		for side in [-1,1]:
			for i in range(16):
				var angle: float = direction.angle()+(limits.y if side>0 else limits.x)+float(side)*lerpf(.025,.16,(float(i)+.5)/16.0)
				var miss: Dictionary = _query_direct_path(world,projectile,target,muzzle,Vector2.from_angle(angle),float(weapon.range),pivot)
				if bool(miss.friendly_fire_risk): result.friendly_fire_risk=true; break
			if bool(result.friendly_fire_risk): break
	return result


func _query_direct_path(world, projectile: Dictionary, target: Dictionary, origin: Vector2, direction: Vector2, length: float, pivot: Vector2) -> Dictionary:
	var end: Vector2 = origin+direction*length
	var result: Dictionary = {"survival":1.0,"reaches_target":false,"segments":[],"blockers":[],"friendly_fire_risk":false,"contact_target":false}
	var contacts: Array[Dictionary] = []
	for unit in world.units:
		if bool(unit.dead) or float(unit.hp)<=0.0 or int(unit.id)==int(projectile.shooter_id): continue
		var prefix_t: float = _moving_circle_hit(pivot,origin,Vector2(unit.pos),Vector2(unit.pos),_radius(unit))
		if prefix_t>=0.0 and not _body_exempt(projectile,unit,pivot.lerp(origin,prefix_t)):
			contacts.append({"distance":-1.0+prefix_t*.999,"unit":unit,"id":int(unit.id),"prefix":true})
		var t: float = _moving_circle_hit(origin,end,Vector2(unit.pos),Vector2(unit.pos),_radius(unit))
		if t>=0.0 and not _body_exempt(projectile,unit,origin.lerp(end,t)):
			contacts.append({"distance":t*length,"unit":unit,"id":int(unit.id),"prefix":false})
	contacts.sort_custom(func(a:Dictionary,b:Dictionary)->bool: return int(a.id)<int(b.id) if absf(float(a.distance)-float(b.distance))<EPS else float(a.distance)<float(b.distance))
	var first: Dictionary = contacts[0] if not contacts.is_empty() else {}
	var cutoff: float = float(first.distance) if not first.is_empty() else length
	if _is_building(target):
		var interval: Vector2 = _segment_rect_interval(origin,end,Rect2(target.rect))
		if _positive_crossing(origin,end,interval) and interval.x*length<cutoff: cutoff=interval.x*length; result.reaches_target=true
	elif not first.is_empty():
		result.reaches_target=int(first.id)==int(target.id)
		result.contact_target=bool(result.reaches_target) and float(first.distance)<=EPS
	if not first.is_empty() and not bool(result.reaches_target):
		result.blockers.append({"entity_id":int(first.id),"kind":"unit","distance":float(first.distance),"prefix":bool(first.prefix),"friendly":int(first.unit.team)==int(projectile.team)})
		result.friendly_fire_risk=int(first.unit.team)==int(projectile.team)
	for segment in _cover_segments(world,origin,end,int(projectile.get("source_building_id",-1)),int(target.id) if _is_building(target) else -1):
		if float(segment.entry_distance)>cutoff+EPS: break
		var protected: Dictionary = first.get("unit",{})
		var volume: float = _volume(protected) if not protected.is_empty() else 1.0
		var chance: float = 1.0 if bool(segment.blocked) else cover_probability(segment.entity,volume,float(segment.entry_distance))
		var detail: Dictionary = {"building_id":int(segment.building_id),"members":segment.members.duplicate(),"cell":segment.cell,"entry_distance":float(segment.entry_distance),"exit_distance":float(segment.exit_distance),"chance":chance,"blocked":bool(segment.blocked)}
		result.segments.append(detail)
		result.survival=float(result.survival)*(1.0-chance)
		if bool(segment.blocked): result.blockers.append({"entity_id":int(segment.building_id),"kind":"wall","distance":float(segment.entry_distance)}); result.reaches_target=false; result.friendly_fire_risk=false; break
	return result


func _mortar_scatter(gunner: Dictionary) -> float:
	return 2.5-1.5*clampf(float(gunner.stability),0.0,1.0)


func mortar_coverage_probability(scatter: float, blast: float, separation: float) -> float:
	if scatter <= EPS: return 1.0 if separation < blast else 0.0
	if separation >= scatter+blast: return 0.0
	if separation <= absf(scatter-blast): return minf(scatter*scatter,blast*blast)/(scatter*scatter)
	var a: float = acos(clampf((separation*separation+scatter*scatter-blast*blast)/(2.0*separation*scatter),-1.0,1.0))
	var b: float = acos(clampf((separation*separation+blast*blast-scatter*scatter)/(2.0*separation*blast),-1.0,1.0))
	var area: float = scatter*scatter*a+blast*blast*b-.5*sqrt(maxf(0.0,(-separation+scatter+blast)*(separation+scatter-blast)*(separation-scatter+blast)*(separation+scatter+blast)))
	return clampf(area/(PI*scatter*scatter),0.0,1.0)


# Misses avoid the original silhouette; moving targets and bystanders remain real.
func spawn_direct_projectile(world, shooter: Dictionary, target: Dictionary, weapon: Dictionary, probability_override: float = -1.0, muzzle: Vector2 = Vector2.INF) -> Dictionary:
	var origin: Vector2 = shooter.pos if muzzle == Vector2.INF else muzzle
	if not _muzzle_clear(world, Vector2(shooter.pos), origin):
		return {}
	var destination: Vector2 = target.pos
	var aim_state: Dictionary = shooter.duplicate()
	aim_state.pos = origin
	var probability: float = hit_probability(aim_state, target, weapon) if probability_override < 0.0 else clampf(probability_override, 0.0, 1.0)
	var accurate: bool = world.rng.randf() < probability
	var direction: Vector2 = (destination - origin).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	if not accurate:
		direction = _miss_direction(world, origin, target, direction)
	var projectile: Dictionary = _new_direct_projectile(world, origin, direction, int(shooter.team), int(shooter.id), int(target.id), weapon)
	projectile["accurate"] = accurate
	projectile["probability"] = probability
	projectile["fire_reference"] = Vector2(shooter.get("fire_reference", shooter.pos))
	projectile["prefix_start"] = projectile.fire_reference
	projectile["prefix_pending"] = true
	projectile["exempt_allies"] = _eligible_allies(world, projectile)
	world.projectiles.append(projectile)
	world.emit_event("weapon_fired", {"entity_id": int(shooter.get("weapon_holder_id", shooter.id)), "holder_id": int(shooter.get("weapon_holder_id", shooter.id)), "shooter_id": int(shooter.id), "target_id": int(target.id), "projectile_id": int(projectile.id), "pos": origin, "team": int(shooter.team), "weapon_kind": String(weapon.kind), "dir": direction, "aim_dir": (destination - origin).normalized()})
	return projectile


func _muzzle_clear(world, base: Vector2, muzzle: Vector2) -> bool:
	for building in _buildings_in_bounds(world, _segment_bounds(base, muzzle)):
		if not _building_alive(building) or _barrier_type(building) != "wall": continue
		var rect: Rect2 = Rect2(building.rect)
		if _point_inside_rect(base,rect) or _point_inside_rect(muzzle,rect) or _positive_crossing(base,muzzle,_segment_rect_interval(base,muzzle,rect)):
			return false
	return true


func advance_projectiles(world, dt: float) -> void:
	finished_projectiles.clear()
	if not _queries_ready:
		_prepare_queries(world)
	# Fragments appended during this pass cannot move before the next world step.
	var active: Array = world.projectiles.duplicate()
	world.projectiles.clear()
	for projectile in active:
		var p: Dictionary = projectile
		if p.kind in ["fragment", "mortar"] and int(p.born_step) >= int(world.step_index):
			world.projectiles.append(p)
			continue
		var survives: bool = _advance_shell(world, p, dt) if p.kind == "mortar" else _advance_direct(world, p, dt)
		if survives:
			world.projectiles.append(p)
	# Position/shape changes outside this combat pass must never reuse a stale grid.
	_queries_ready = false


func explode(world, position: Vector2, team: int, shooter_id: int = -1, projectile_id: int = -1) -> void:
	var snapshot: Array[Dictionary] = []
	for b in world.buildings:
		if _building_alive(b) and _barrier_type(b) != "floor":
			snapshot.append({"id": int(b.id), "rect": b.rect, "height": float(b.height), "high": _barrier_type(b) == "wall"})
	var outcomes: Array[Dictionary] = []
	for u in world.units:
		if bool(u.dead) or float(u.hp) <= 0.0:
			continue
		var distance: float = position.distance_to(Vector2(u.pos))
		if distance >= BLAST_RADIUS:
			continue
		var falloff: float = maxf(0.0, 1.0 - distance / BLAST_RADIUS)
		var barrier: float = _blast_barrier(snapshot, position, Vector2(u.pos), -1)
		var posture_factor: float = [1.0, 0.85, 0.65][_posture(u)]
		var armor_factor: float = 0.6 if String(u.kind) == "heavy" else 1.0
		outcomes.append({"entity": u, "damage": 100.0 * falloff * barrier * posture_factor * armor_factor, "suppression": 30.0 * falloff, "unit": true})
	for b in world.buildings:
		if not _building_alive(b):
			continue
		var nearest: Vector2 = _closest_point_rect(position, Rect2(b.rect))
		var distance: float = position.distance_to(nearest)
		if distance >= BLAST_RADIUS:
			continue
		var barrier: float = _blast_barrier(snapshot, position, nearest, int(b.id))
		outcomes.append({"entity": b, "damage": 150.0 * (1.0 - distance / BLAST_RADIUS) * barrier, "suppression": 0.0, "unit": false})
	var blast: Dictionary = {"id": projectile_id, "kind": "mortar", "weapon_kind": "mortar", "team": team, "shooter_id": shooter_id, "pos":position, "start":position, "suppression_applied": {}}
	world.emit_event("explosion", {"entity_id": shooter_id, "shooter_id": shooter_id, "projectile_id": projectile_id, "pos": position, "team": team, "weapon_kind": "mortar", "radius": BLAST_RADIUS, "fragment_radius": 10.0})
	# Apply only after every victim has read the pre-damage obstacle snapshot.
	for outcome in outcomes:
		var victim: Dictionary = outcome.entity
		if bool(outcome.unit):
			_damage_unit(world, victim, float(outcome.damage), blast, false)
			_suppress(world, victim, float(outcome.suppression), blast)
		else:
			_damage_building(world, victim, float(outcome.damage), blast)
	var fragment_weapon: Dictionary = Config.fragment()
	for i in range(24):
		var angle: float = (float(i) + world.rng.randf()) * TAU / 24.0
		world.projectiles.append(_new_direct_projectile(world, position, Vector2.from_angle(angle), team, shooter_id, -1, fragment_weapon))


func _update_weapon_clock(holder: Dictionary, dt: float) -> void:
	holder.weapon_cooldown = maxf(-dt, float(holder.weapon_cooldown) - dt)
	holder.burst_rest = maxf(0.0, float(holder.burst_rest) - dt)


func _ensure_weapon(holder: Dictionary) -> void:
	var defaults: Dictionary = {"aim_elapsed": 0.0, "aim_fraction": 0.0, "aim_target_id": -1, "weapon_state": "idle", "weapon_facing": float(holder.get("facing", -PI / 2.0)), "hold_fire":false, "target_policy":"strict", "reload_stage":0, "idle_reload_since":-1.0, "reload_paused":false}
	for key in defaults:
		if not holder.has(key): holder[key] = defaults[key]


func _reset_aim(holder: Dictionary, state: String = "idle") -> void:
	holder["aim_elapsed"] = 0.0
	holder["aim_fraction"] = 0.0
	holder["weapon_state"] = state
	holder.burst_left = 0


func _update_rifle(world, u: Dictionary, dt: float) -> void:
	var weapon: Dictionary = Config.rifle()
	if not _rifle_job_allowed(world,u):
		_interrupt_reload(u,float(weapon.reload))
		_reset_aim(u)
		u.idle_reload_since=-1.0
		return
	var can_reload: bool = _action_allowed(world,u,"reload") and not _is_moving(u)
	if int(u.reload_reserved)>0:
		_reset_aim(u,"reloading")
		if not can_reload:
			_interrupt_reload(u,float(weapon.reload)); u.status="换弹暂停"; return
		_advance_reload(world,u,float(weapon.reload),dt,"reserve",int(weapon.magazine))
		return
	var target: Dictionary = _choose_target(world,u,weapon)
	var waiting: bool = int(u.target_id)>=0 and String(u.get("target_policy","strict"))=="strict"
	if _want_reload(world,u,int(weapon.magazine),(not target.is_empty() or waiting) and not bool(u.get("hold_fire",false)),can_reload) and int(u.reserve)>0:
		_start_reload(world,u,mini(int(u.reserve),int(weapon.magazine)-int(u.loaded)))
		return
	if int(u.loaded)<=0:
		u.status="步枪弹药耗尽" if int(u.reserve)<=0 else "等待换弹"
		_reset_aim(u,"blocked"); return
	if bool(u.get("hold_fire",false)):
		_reset_aim(u); u.status="停火警戒"; return
	if not _action_allowed(world,u,"fire"):
		_reset_aim(u,"blocked"); return
	if target.is_empty():
		_reset_aim(u,"blocked" if waiting else "idle")
		if waiting: u.status="指定目标暂不可攻击，守位等待"
		return
	var condition: Dictionary = can_fire_pose(world,u,target)
	if not bool(condition.ok): _reset_aim(u,"blocked"); u.status=condition.reason; return
	var pose: Dictionary = Pose.aimed_rifle(Vector2(u.pos),Vector2(target.pos),_posture(u))
	u.weapon_facing=float(pose.angle)
	u["weapon_holder_id"]=int(u.id)
	u["fire_reference"]=Vector2(pose.get("pivot",u.pos))
	_fire_burst(world,u,u,target,weapon,Vector2(pose.muzzle),dt)


func _update_machine_gun(world, b: Dictionary, dt: float) -> void:
	var weapon: Dictionary = Config.machine_gun()
	var crew: Array[Dictionary] = _station_crew(world,b)
	var operator: Dictionary = crew[0] if not crew.is_empty() else {}
	if operator.is_empty() or String(operator.stage)!="station":
		_interrupt_reload(b,float(weapon.reload)); _reset_aim(b)
		b.status="无人操作" if crew.is_empty() else "等待操作员到岗"
		b.idle_reload_since=-1.0
		return
	if int(b.get("reload_operator",-1))!=int(operator.id):
		_interrupt_reload(b,float(weapon.reload)); _reset_aim(b)
		b["reload_operator"]=int(operator.id)
	var can_work: bool = _action_allowed(world,operator,"operate") and _posture(operator)<=1
	if int(b.reload_reserved)>0:
		_reset_aim(b,"reloading")
		if not can_work: _interrupt_reload(b,float(weapon.reload)); b.status="换弹带暂停"; return
		_advance_reload(world,b,float(weapon.reload),dt,"ammo",int(weapon.magazine))
		return
	var target: Dictionary = _choose_target(world,operator,weapon,b)
	var waiting: bool = int(b.target_id)>=0 and String(b.get("target_policy","strict"))=="strict"
	if _want_reload(world,b,int(weapon.magazine),(not target.is_empty() or waiting) and not bool(b.get("hold_fire",false)),can_work) and int(b.ammo)>0:
		_start_reload(world,b,mini(int(b.ammo),int(weapon.magazine)-int(b.loaded)))
		return
	if int(b.loaded)<=0: b.status="缺少机枪弹"; _reset_aim(b,"blocked"); return
	if not can_work: _reset_aim(b,"blocked"); b.status="操作暂停"; return
	if bool(b.get("hold_fire",false)): _reset_aim(b); b.status="停火警戒"; return
	if target.is_empty():
		_reset_aim(b,"blocked" if waiting else "idle")
		b.status="指定目标暂不可攻击" if waiting else "警戒射界"
		return
	var condition: Dictionary = can_fire_pose(world,operator,target,b)
	if not bool(condition.ok): _reset_aim(b,"blocked"); b.status=condition.reason; return
	b.weapon_facing=(Vector2(target.pos)-Vector2(b.pos)).angle()
	operator.weapon_facing=float(b.weapon_facing)
	var pose: Dictionary = Pose.station(Vector2(b.pos),float(b.weapon_facing),"mg")
	var shooter: Dictionary = operator.duplicate()
	shooter.pos=b.pos
	shooter["fire_reference"]=Vector2(pose.get("pivot",b.pos))
	shooter["weapon_holder_id"]=int(b.id)
	_fire_burst(world,shooter,b,target,weapon,Vector2(pose.muzzle),dt)
	operator.stability=shooter.stability
	operator["combat_target_id"]=shooter.get("combat_target_id",-1)


func _update_mortar(world, b: Dictionary, dt: float) -> void:
	var crew: Array[Dictionary] = _station_crew(world,b)
	if crew.is_empty():
		_interrupt_reload(b,MORTAR_LOAD_WORK)
		b.aim_progress=0.0; b.status="无人操作"; _reset_aim(b)
		return
	var gunner: Dictionary = crew[0]
	if int(b.get("mortar_gunner",-1))!=int(gunner.id):
		b["mortar_gunner"]=int(gunner.id); b.aim_progress=0.0
	var workers: int = 0
	for member in crew:
		if String(member.stage)=="station" and _action_allowed(world,member,"operate") and _posture(member)<=1: workers+=1
	# Chambering happens before a command exists; a loaded shell never fires itself.
	if int(b.loaded)<=0:
		b.aim_progress=0.0; _reset_aim(b,"reloading")
		if int(b.ammo)<=0: _cancel_reload(b); b.status="缺少炮弹"; return
		if int(b.reload_reserved)<=0: _start_reload(world,b,1)
		if workers<=0: _interrupt_reload(b,MORTAR_LOAD_WORK); b.status="装填暂停"; return
		_advance_reload(world,b,MORTAR_LOAD_WORK,dt*(2.5 if workers>=2 else 1.0),"ammo",1)
		return
	if not bool(b.fire_requested):
		b.aim_progress=0.0; b.status="炮弹已装膛"; _reset_aim(b); return
	if bool(b.get("hold_fire",false)):
		b.aim_progress=0.0; b.status="停火，轰击命令挂起"; _reset_aim(b); return
	var target: Dictionary = {}
	if int(b.target_id)>=0:
		target=world.entity(int(b.target_id))
		if not _target_alive(target):
			b.target_id=-1; b.fire_requested=false; b.aim_progress=0.0; _reset_aim(b); b.status="目标已失效"; return
		b.fire_point=target.pos
	var aim_point: Vector2 = b.fire_point
	if target.is_empty() and Vector2(b.get("mortar_aim_point",Vector2.INF))!=aim_point:
		b["mortar_aim_point"]=aim_point; b.aim_progress=0.0
	var distance: float = Vector2(b.pos).distance_to(aim_point)
	if distance<8.0-EPS or distance>40.0+EPS:
		b.aim_progress=0.0; b.status="落点须距炮位8至40格"; _reset_aim(b,"blocked"); return
	b.weapon_facing=(aim_point-Vector2(b.pos)).angle(); b.aim_target_id=int(b.target_id)
	if String(gunner.stage)!="station" or not _action_allowed(world,gunner,"operate") or _posture(gunner)>1:
		b.aim_progress=0.0; b.status="等待炮手瞄准"; _reset_aim(b,"blocked"); return
	b.aim_progress=float(b.aim_progress)+dt
	b.weapon_state="aiming"; b.aim_fraction=clampf(float(b.aim_progress)/MORTAR_AIM_TIME,0.0,1.0)
	b.status="瞄准 %.1f/4秒" % float(b.aim_progress)
	if float(b.aim_progress)+EPS<MORTAR_AIM_TIME: return
	var pose: Dictionary = Pose.station(Vector2(b.pos),float(b.weapon_facing),"mortar")
	var muzzle: Vector2 = pose.muzzle
	if not _muzzle_clear(world,Vector2(b.pos),muzzle): b.status="炮口被墙体阻挡"; b.weapon_state="blocked"; return
	var scatter: Vector2 = Vector2.from_angle(world.rng.randf()*TAU)*sqrt(world.rng.randf())*_mortar_scatter(gunner)
	var impact: Vector2 = aim_point+scatter
	var shell: Dictionary = {"id":_next_projectile_id(world),"kind":"mortar","weapon_kind":"mortar","team":int(gunner.team),"shooter_id":int(gunner.id),"target_id":int(b.target_id),"pos":muzzle,"prev_pos":muzzle,"start":muzzle,"impact":impact,"velocity":(impact-muzzle)/MORTAR_FLIGHT_TIME,"dir":(impact-muzzle).normalized(),"age":0.0,"life":MORTAR_FLIGHT_TIME,"arc_height":0.0,"born_step":int(world.step_index)}
	world.projectiles.append(shell)
	b.loaded=0; b.aim_progress=0.0; b.fire_requested=false; b.target_id=-1
	b.weapon_state="firing"; b.aim_fraction=1.0; b.status="炮弹飞行中"
	world.stats.mortar_shots=int(world.stats.get("mortar_shots",0))+1
	world.emit_event("weapon_fired",{"entity_id":int(b.id),"holder_id":int(b.id),"shooter_id":int(gunner.id),"projectile_id":int(shell.id),"pos":muzzle,"target_pos":impact,"team":int(gunner.team),"weapon_kind":"mortar","dir":shell.dir,"aim_dir":Vector2.from_angle(float(b.weapon_facing))})


func _is_moving(unit: Dictionary) -> bool:
	return bool(unit.get("move_active",false)) or Vector2(unit.get("velocity",Vector2.ZERO)).length_squared()>EPS


func _action_allowed(world, unit: Dictionary, action: String) -> bool:
	if world.unit_system.has_method("can_act"):
		return bool(world.unit_system.can_act(world,unit,action).get("ok",false))
	return not bool(unit.dead) and bool(unit.conscious) and not bool(unit.get("cower",false)) and float(unit.hp)>=float(unit.max_hp)*.25 and float(unit.posture_timer)<=EPS and float(unit.rout_until)<=float(world.time_s) and int(unit.crate_id)<0 and int(unit.rescued_id)<0 and int(unit.carrier_id)<0


func _want_reload(world, holder: Dictionary, capacity: int, busy: bool, compatible: bool) -> bool:
	if int(holder.loaded)>=capacity: holder.idle_reload_since=-1.0; return false
	if int(holder.loaded)<=0: return compatible
	if busy or not compatible: holder.idle_reload_since=-1.0; return false
	if float(holder.get("idle_reload_since",-1.0))<0.0: holder.idle_reload_since=float(world.time_s)
	return float(world.time_s)-float(holder.idle_reload_since)+EPS>=IDLE_RELOAD_DELAY


func _start_reload(world, holder: Dictionary, count: int) -> void:
	holder.reload_reserved=count; holder.reload_stage=0; holder.reload_progress=0.0; holder.reload_paused=false
	_reset_aim(holder,"reloading")
	world.emit_event("reload_started",{"entity_id":int(holder.id),"pos":Vector2(holder.pos),"stage":0})


func _interrupt_reload(holder: Dictionary, total_work: float) -> void:
	if int(holder.get("reload_reserved",0))<=0 or bool(holder.get("reload_paused",false)): return
	holder.reload_progress=float(clampi(int(holder.get("reload_stage",0)),0,1))*total_work*.5
	holder.reload_paused=true


func _advance_reload(world, holder: Dictionary, total_work: float, work: float, source_key: String, capacity: int) -> bool:
	holder.reload_paused=false
	holder.reload_progress=float(holder.reload_progress)+work
	if int(holder.get("reload_stage",0))==0 and float(holder.reload_progress)+EPS>=total_work*.5:
		holder.reload_stage=1
		world.emit_event("reload_stage",{"entity_id":int(holder.id),"pos":Vector2(holder.pos),"stage":1})
	holder.status="装填%s %.0f%%" % ["准备" if int(holder.reload_stage)==0 else "装入",100.0*float(holder.reload_progress)/total_work]
	if float(holder.reload_progress)+EPS<total_work: return false
	var transfer: int = mini(int(holder.reload_reserved),mini(int(holder.get(source_key,0)),capacity-int(holder.loaded)))
	holder[source_key]=int(holder.get(source_key,0))-transfer
	holder.loaded=int(holder.loaded)+transfer
	_cancel_reload(holder)
	world.emit_event("reload_complete",{"entity_id":int(holder.id),"pos":Vector2(holder.pos),"amount":transfer})
	return true


func _fire_burst(world, shooter: Dictionary, holder: Dictionary, target: Dictionary, weapon: Dictionary, muzzle: Vector2, dt: float = Config.FIXED_DT) -> void:
	_ensure_weapon(holder)
	var style: int = clampi(int(shooter.style), 0, 2)
	if int(holder.get("combat_style", -1)) != style:
		holder["combat_style"] = style
		_reset_aim(holder)
	var aim_angle: float = Vector2(target.pos - muzzle).angle()
	if int(holder.aim_target_id) != int(target.id):
		var previous_angle: float = float(holder.get("last_aim_angle", aim_angle))
		var retained: float = clampf(1.0 - absf(wrapf(aim_angle - previous_angle, -PI, PI)) / PI, 0.0, 1.0)
		if int(holder.aim_target_id) < 0: retained = 0.0
		shooter.stability = float(shooter.stability) * retained
		holder.aim_elapsed = float(holder.aim_elapsed) * retained
		holder.aim_target_id = int(target.id)
		holder.burst_left = 0
	elif holder.has("last_aim_angle"):
		var angular_retention: float = clampf(1.0 - absf(wrapf(aim_angle - float(holder.last_aim_angle), -PI, PI)) / PI, 0.0, 1.0)
		shooter.stability = float(shooter.stability) * angular_retention
		if String(holder.weapon_state) == "aiming": holder.aim_elapsed = float(holder.aim_elapsed) * angular_retention
	shooter["combat_target_id"] = int(target.id)
	holder["last_aim_angle"] = aim_angle
	if float(holder.burst_rest) > EPS:
		holder.weapon_state = "recovering"
		holder.aim_fraction = 0.0
		return
	if int(holder.burst_left) == 0:
		var q: float = clampf(float(shooter.suppression) / 100.0, 0.0, 1.0)
		var aim_seconds: float = float(Config.MG_AIM_SECONDS[style] if weapon.kind == "mg" else Config.RIFLE_AIM_SECONDS[style])
		var rate: float = (1.0 - 0.65 * q) * _injury_factor(shooter)
		if Vector2(shooter.velocity).length_squared() > 0.0009: rate *= 0.75
		if String(holder.weapon_state) != "aiming":
			world.emit_event("aim_started", {"entity_id": int(holder.id), "holder_id": int(holder.id), "target_id": int(target.id), "pos": muzzle, "weapon_kind": String(weapon.kind)})
		holder.weapon_state = "aiming"
		holder.aim_elapsed = float(holder.aim_elapsed) + dt * rate
		holder.aim_fraction = clampf(float(holder.aim_elapsed) / aim_seconds, 0.0, 1.0)
		holder.status = "瞄准 %d%%" % int(float(holder.aim_fraction) * 100.0)
		if float(holder.aim_elapsed) + EPS < aim_seconds:
			return
		holder.burst_left = -1 if style == 0 else ((5 if style == 1 else 3) if weapon.kind == "mg" else (3 if style == 1 else 1))
	holder.weapon_state = "firing"
	holder.aim_fraction = 1.0
	if float(holder.weapon_cooldown) > EPS:
		return
	var projectile: Dictionary = spawn_direct_projectile(world, shooter, target, weapon, -1.0, muzzle)
	if projectile.is_empty():
		_reset_aim(holder, "blocked")
		holder.status = "枪口被墙体阻挡"
		return
	projectile["source_building_id"] = -1 if holder == shooter else int(holder.id)
	holder.loaded = int(holder.loaded) - 1
	holder.weapon_cooldown = float(holder.weapon_cooldown) + 1.0 / float(weapon.rate)
	shooter.stability = maxf(0.0, float(shooter.stability) - float(weapon.recoil))
	holder.status = "射击"
	var stat: String = "mg_shots" if weapon.kind == "mg" else "rifle_shots"
	world.stats[stat] = int(world.stats.get(stat, 0)) + 1
	if int(holder.burst_left) > 0:
		holder.burst_left = int(holder.burst_left) - 1
		if int(holder.burst_left) == 0:
			holder.burst_rest = float(Config.MG_RECOVER_SECONDS[style] if weapon.kind == "mg" else Config.RIFLE_RECOVER_SECONDS[style])
			holder.aim_elapsed = 0.0
			holder.aim_fraction = 0.0
			holder.weapon_state = "recovering"


func _choose_target(world, shooter: Dictionary, weapon: Dictionary, station: Dictionary = {}) -> Dictionary:
	var preferred_id: int = int(shooter.target_id) if station.is_empty() else int(station.target_id)
	if preferred_id >= 0:
		var preferred: Dictionary = world.entity(preferred_id)
		if int(shooter.team) != 0 and not preferred.is_empty() and preferred.has("conscious") and not bool(preferred.conscious):
			# AI intentions are refreshed less often than bullets; discard a newly
			# downed victim immediately rather than finish a burst on that body.
			shooter.target_id = -1
			preferred = {}
		if _target_alive(preferred) and _target_in_range(world, shooter, preferred, weapon, station):
			return preferred
		if _target_alive(preferred):
			var holder: Dictionary = shooter if station.is_empty() else station
			if String(holder.get("target_policy","strict")) == "strict": return {}
		else:
			if station.is_empty(): shooter.target_id = -1
			else: station.target_id = -1

	var best: Dictionary = {}
	var best_score: float = INF
	for candidate in world.units:
		if int(candidate.team) == int(shooter.team) or not _target_alive(candidate) or not bool(candidate.conscious):
			continue
		var score: float = Vector2(shooter.pos).distance_squared_to(Vector2(candidate.pos))
		if score >= best_score or not _target_in_range(world, shooter, candidate, weapon, station):
			continue
		best = candidate
		best_score = score
	return best


func _target_in_range(world, shooter: Dictionary, target: Dictionary, weapon: Dictionary, station: Dictionary) -> bool:
	return bool(can_fire_pose(world,shooter,target,station).ok)


func validate_station_attack(world, station_id: int, target_id: int) -> Dictionary:
	var station: Dictionary = world.entity(station_id)
	var target: Dictionary = world.entity(target_id)
	if station.is_empty() or not _is_building(station) or station.get("kind", "") not in ["mg", "mortar"] or not _building_alive(station):
		return {"ok": false, "reason": "请选择可用的工事"}
	var crew: Array[int] = world.projected_crew(station_id)
	if crew.is_empty(): return {"ok": false, "reason": "需要先安排工事操作员"}
	if not _target_alive(target) or _is_building(target) or int(target.team) != 1:
		return {"ok": false, "reason": "请选择存活的敌人"}
	var distance: float = Vector2(station.pos).distance_to(Vector2(target.pos))
	if station.kind == "mortar":
		if distance < 8.0 - EPS or distance > 40.0 + EPS: return {"ok": false, "reason": "目标须距炮位8至40格"}
	else:
		var operator: Dictionary = world.entity(int(crew[0]))
		if not _target_in_range(world, operator, target, Config.machine_gun(), station):
			return {"ok": false, "reason": "目标在射程、射界之外或被墙体遮挡"}
	return {"ok": true, "reason": ""}


func request_station_attack(world, station_id: int, target_id: int) -> Dictionary:
	var result: Dictionary = validate_station_attack(world, station_id, target_id)
	if not bool(result.ok): return result
	var station: Dictionary = world.entity(station_id)
	station.target_id = target_id
	_reset_aim(station)
	station.aim_target_id = target_id
	if station.kind == "mortar":
		station.fire_point = world.entity(target_id).pos
		station["mortar_aim_point"] = station.fire_point
		station.fire_requested = true
		station.aim_progress = 0.0
	station.status = "指定目标"
	world.emit_event("station_target_changed", {"entity_id": station_id, "target_id": target_id, "pos": station.pos})
	return result


func _station_crew(world, b: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in b.crew:
		var u: Dictionary = world.entity(int(id))
		if u.is_empty() or int(u.station_id) != int(b.id) or String(u.job) != "operate":
			continue
		if bool(u.dead) or not bool(u.conscious) or float(u.hp) < float(u.max_hp) * 0.25 or float(u.rout_until) > float(world.time_s):
			continue
		result.append(u)
	return result


func _rifle_job_allowed(world, u: Dictionary) -> bool:
	if bool(u.dead) or not bool(u.conscious) or float(u.hp) < float(u.max_hp) * 0.25:
		return false
	if int(u.team) == 0 and not bool(u.drafted):
		return false
	if float(u.rout_until) > float(world.time_s) or int(u.carrier_id) >= 0:
		return false
	return not String(u.job) in ["operate", "resupply", "rescue", "treat", "rout"]


func _can_work(world, u: Dictionary) -> bool:
	return _action_allowed(world,u,"fire")


func _cancel_reload(holder: Dictionary) -> void:
	holder.reload_progress = 0.0
	holder.reload_reserved = 0
	holder["reload_stage"] = 0
	holder["reload_paused"] = false
	holder["idle_reload_since"] = -1.0


func _new_direct_projectile(world, origin: Vector2, direction: Vector2, team: int, shooter_id: int, target_id: int, weapon: Dictionary) -> Dictionary:
	return {"id": _next_projectile_id(world), "kind": String(weapon.kind), "weapon_kind": String(weapon.kind), "team": team, "shooter_id": shooter_id, "target_id": target_id, "start": origin, "pos": origin, "prev_pos": origin, "dir": direction, "velocity": direction * float(weapon.speed), "speed": float(weapon.speed), "damage": float(weapon.damage), "penetration": float(weapon.penetration), "remaining": float(weapon.range), "travelled": 0.0, "life": float(weapon.range) / float(weapon.speed), "born_step": int(world.step_index), "cover_checked": {}, "low_cells_seen": {}, "cover_intervals": [], "suppression_applied": {}}


func _next_projectile_id(world) -> int:
	var serial: int = int(world.stats.get("projectile_serial", 0)) + 1
	world.stats["projectile_serial"] = serial
	return serial


func _miss_direction(world, origin: Vector2, target: Dictionary, aim: Vector2) -> Vector2:
	var angle: float = aim.angle()
	var limits: Vector2 = _miss_limits(origin,target,aim)
	var lower: float = limits.x
	var upper: float = limits.y
	var miss_offset: float = world.rng.randf_range(0.025, 0.16)
	return Vector2.from_angle(angle + (upper + miss_offset if world.rng.randf() < 0.5 else lower - miss_offset))


func _miss_limits(origin: Vector2, target: Dictionary, aim: Vector2) -> Vector2:
	var limits: Vector2 = Vector2.ZERO
	if _is_building(target):
		var rect: Rect2 = Rect2(target.rect)
		for corner in [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]:
			var difference: float = wrapf(Vector2(corner-origin).angle()-aim.angle(),-PI,PI)
			limits.x=minf(limits.x,difference); limits.y=maxf(limits.y,difference)
	else:
		var tangent: float = asin(clampf((_radius(target)+.025)/maxf(origin.distance_to(Vector2(target.pos)),EPS),0.0,.9999))
		limits=Vector2(-tangent,tangent)
	return limits


func _advance_shell(world, p: Dictionary, dt: float) -> bool:
	var previous_age: float = p.age
	p.prev_pos = p.pos
	p.age = minf(MORTAR_FLIGHT_TIME, float(p.age) + dt)
	var fraction: float = float(p.age) / MORTAR_FLIGHT_TIME
	p.pos = Vector2(p.start).lerp(Vector2(p.impact), fraction)
	p.arc_height = 8.0 * 4.0 * fraction * (1.0 - fraction)
	p.life = maxf(0.0, MORTAR_FLIGHT_TIME - float(p.age))
	if float(p.age) + EPS < MORTAR_FLIGHT_TIME:
		return true
	world.emit_event("projectile_impact", {"entity_id": -1, "projectile_id": int(p.id), "pos": Vector2(p.impact), "team": int(p.team), "weapon_kind": "mortar", "material": "ground"})
	explode(world, Vector2(p.impact), int(p.team), int(p.shooter_id), int(p.id))
	_record_finished(world, p, (MORTAR_FLIGHT_TIME - previous_age) / dt if dt > 0.0 else 0.0, previous_age, MORTAR_FLIGHT_TIME, "ground")
	return false


func _advance_direct(world, p: Dictionary, dt: float) -> bool:
	var origin: Vector2 = p.pos
	var step_distance: float = float(p.speed) * dt
	var distance: float = minf(step_distance, float(p.remaining))
	var destination: Vector2 = origin + Vector2(p.dir) * distance
	p.prev_pos = origin
	var collisions: Array[Dictionary] = []
	var bounds: Rect2 = _segment_bounds(origin, destination)
	for u in _units_in_bounds(world, bounds):
		if bool(u.dead) or float(u.hp) <= 0.0 or (p.kind != "fragment" and int(u.id) == int(p.shooter_id)): continue
		var t: float = _moving_circle_hit(origin, destination, Vector2(u.prev_pos), Vector2(u.pos), _radius(u))
		if t >= 0.0 and not _body_exempt(p, u, origin.lerp(destination,t),Vector2(u.prev_pos).lerp(Vector2(u.pos),t)):
			collisions.append({"t": t, "priority": 1, "kind": "unit", "entity": u, "id": int(u.id)})
	if bool(p.get("prefix_pending", false)):
		var prefix: Vector2 = p.get("prefix_start", origin)
		for u in world.units:
			if bool(u.dead) or float(u.hp) <= 0.0 or int(u.id) == int(p.shooter_id): continue
			var t: float = _moving_circle_hit(prefix, Vector2(p.start), Vector2(u.pos), Vector2(u.pos), _radius(u))
			if t >= 0.0 and not _body_exempt(p, u, prefix.lerp(Vector2(p.start),t)):
				collisions.append({"t": -1.0+t*.999, "point":prefix.lerp(Vector2(p.start),t), "priority":1, "kind":"unit", "entity":u, "id":int(u.id)})
		p["prefix_pending"] = false
	for b in _buildings_in_bounds(world, bounds):
		if not _building_alive(b) or _barrier_type(b) == "floor" or int(b.id) == int(p.get("source_building_id", -1)): continue
		if _barrier_type(b) == "wall" or int(b.id) == int(p.target_id):
			var interval: Vector2 = _segment_rect_interval(origin, destination, Rect2(b.rect))
			if _positive_crossing(origin,destination,interval) or _point_inside_rect(origin,Rect2(b.rect)):
				collisions.append({"t": interval.x, "priority": 0, "kind": "building", "entity": b, "id": int(b.id)})
	var full_start: Vector2 = p.get("start", origin-Vector2(p.dir)*float(p.travelled))
	var full_end: Vector2 = full_start+Vector2(p.dir)*(float(p.travelled)+float(p.remaining))
	for segment in _cover_segments(world, full_start, full_end, int(p.get("source_building_id",-1)), int(p.target_id)):
		if bool(segment.blocked) or _segment_checked(p,segment): continue
		if float(segment.exit_distance) < float(p.travelled)-SEGMENT_TOLERANCE or float(segment.entry_distance) > float(p.travelled)+distance+EPS: continue
		var t: float = clampf((float(segment.entry_distance)-float(p.travelled))/maxf(EPS,distance),0.0,1.0)
		collisions.append({"t": t, "priority": 0, "kind": "low", "entity": segment.entity, "id": int(segment.building_id), "cell": segment.cell, "segment":segment})
	collisions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a.t) - float(b.t)) > EPS:
			return float(a.t) < float(b.t)
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		return int(a.id) < int(b.id)
	)
	for collision in collisions:
		var victim: Dictionary = collision.entity
		var t: float = float(collision.t)
		var impact_position: Vector2 = collision.get("point",origin.lerp(destination, clampf(t,0.0,1.0)))
		var armor_absorbed: bool = collision.kind == "unit" and float(p.penetration) < float(victim.get("armor", 0.0))
		if collision.kind == "low":
			var protected: Dictionary = _forward_victim(world, p, origin, destination, t)
			var volume: float = 1.0 if protected.is_empty() else _volume(protected)
			_mark_segment(p, collision.segment)
			var chance: float = cover_probability(victim, volume, float(collision.segment.entry_distance))
			if chance <= 0.0 or world.rng.randf() >= chance:
				continue
			_damage_building(world, victim, float(p.damage) * 0.25, p)
		else:
			if collision.kind == "unit":
				var damage: float = float(p.damage) * (1.0 if float(p.penetration) >= float(victim.armor) else 0.25)
				_damage_unit(world, victim, damage, p, true)
			else:
				_damage_building(world, victim, float(p.damage) * 0.25, p)
		p.pos = impact_position
		_suppress_along(world, p, origin, impact_position, clampf(t,0.0,1.0))
		var material: String = ("armor" if armor_absorbed else "unit") if collision.kind == "unit" else String(victim.get("material", {"sandbag": "sandbag", "crate": "wood", "wall": "concrete", "core": "concrete"}.get(String(victim.kind), "metal")))
		world.emit_event("projectile_impact", {"entity_id": int(victim.id), "shooter_id": int(p.shooter_id), "projectile_id": int(p.id), "pos": impact_position, "team": int(p.team), "weapon_kind": String(p.kind), "material": material, "armor_absorbed": armor_absorbed, "blocked_by_cover": collision.kind == "low"})
		_record_finished(world, p, distance * maxf(0.0,t) / step_distance if step_distance > 0.0 else 0.0, float(p.travelled) / float(p.speed), (float(p.travelled) + distance * maxf(0.0,t)) / float(p.speed), "impact")
		return false
	p.pos = destination
	p.remaining = maxf(0.0, float(p.remaining) - distance)
	p.travelled = float(p.travelled) + distance
	p.life = maxf(0.0, float(p.remaining) / float(p.speed))
	_suppress_along(world, p, origin, destination, 1.0)
	if float(p.remaining) <= EPS:
		_record_finished(world, p, distance / step_distance if step_distance > 0.0 else 0.0, (float(p.travelled) - distance) / float(p.speed), float(p.travelled) / float(p.speed), "range")
	return float(p.remaining) > EPS


func _record_finished(world, p: Dictionary, fraction: float, previous_age: float, age: float, reason: String) -> void:
	# Copy only drawing values. No mutable combat dictionaries escape through here.
	finished_projectiles.append({"id": int(p.id), "kind": String(p.kind), "weapon_kind": String(p.weapon_kind), "team": int(p.team), "shooter_id": int(p.shooter_id), "prev_pos": Vector2(p.prev_pos), "pos": Vector2(p.impact) if reason == "ground" else Vector2(p.pos), "dir": Vector2(p.dir), "velocity": Vector2(p.velocity), "prev_age": previous_age, "age": age, "fraction": clampf(fraction, 0.0, 1.0), "reason": reason, "step": int(world.step_index)})


func _forward_victim(world, p: Dictionary, origin: Vector2, step_end: Vector2, entry_t: float) -> Dictionary:
	var end: Vector2 = origin + Vector2(p.dir) * float(p.remaining)
	var best: Dictionary = {}
	var best_distance: float = INF
	var entry_distance: float = origin.distance_to(step_end) * entry_t
	for u in world.units:
		if bool(u.dead) or float(u.hp) <= 0.0 or (p.kind != "fragment" and int(u.id) == int(p.shooter_id)):
			continue
		var radius: float = _radius(u)
		var t: float = _moving_circle_hit(origin, end, Vector2(u.pos), Vector2(u.pos), radius)
		var distance: float = t * float(p.remaining) if t >= 0.0 else INF
		if t >= 0.0 and _body_exempt(p,u,origin.lerp(end,t)): continue
		var moving_t: float = _moving_circle_hit(origin, step_end, Vector2(u.prev_pos), Vector2(u.pos), radius)
		if moving_t>=0.0 and _body_exempt(p,u,origin.lerp(step_end,moving_t),Vector2(u.prev_pos).lerp(Vector2(u.pos),moving_t)): moving_t=-1.0
		if moving_t >= entry_t - EPS and moving_t >= 0.0:
			distance = minf(distance, moving_t * origin.distance_to(step_end))
		if distance + EPS < entry_distance or distance >= best_distance:
			continue
		best_distance = distance
		best = u
	return best


func _suppress_along(world, p: Dictionary, origin: Vector2, destination: Vector2, step_fraction: float) -> void:
	var amount: float = 7.0 if p.kind == "mg" else (2.0 if p.kind == "fragment" else 4.0)
	for u in _units_in_bounds(world, _segment_bounds(origin, destination, NEAR_MISS_DISTANCE)):
		if bool(u.dead) or float(u.hp) <= 0.0 or int(u.team) == int(p.team) or int(u.id) == int(p.shooter_id):
			continue
		var unit_start: Vector2 = u.prev_pos
		var unit_end: Vector2 = unit_start.lerp(Vector2(u.pos), step_fraction)
		if _distance_to_segment(Vector2.ZERO, origin - unit_start, destination - unit_end) <= NEAR_MISS_DISTANCE:
			_suppress(world, u, amount, p)


func _damage_unit(world, u: Dictionary, damage: float, source: Dictionary, bleeds: bool) -> void:
	var actual: float = minf(maxf(0.0, damage), maxf(0.0, float(u.hp)))
	if actual <= 0.0:
		return
	u.hp = maxf(0.0, float(u.hp) - actual)
	if bleeds:
		u.bleed_rate = minf(0.3, float(u.bleed_rate) + actual * 0.003)
	_suppress(world, u, 12.0, source)
	world.stats.damage = float(world.stats.get("damage", 0.0)) + actual
	if int(u.team) == int(source.team):
		world.stats.friendly_fire = int(world.stats.get("friendly_fire", 0)) + 1
	world.emit_event("damage", {"entity_id": int(u.id), "shooter_id": int(source.get("shooter_id", -1)), "projectile_id": int(source.get("id", -1)), "pos": Vector2(u.pos), "team": int(source.team), "target_team": int(u.team), "weapon_kind": String(source.kind), "amount": actual, "hp": float(u.hp), "bleeding": bleeds})


func _damage_building(world, b: Dictionary, damage: float, source: Dictionary) -> void:
	var actual: float = minf(maxf(0.0, damage), maxf(0.0, float(b.hp)))
	if actual <= 0.0:
		return
	b.hp = maxf(0.0, float(b.hp) - actual)
	world.stats.damage = float(world.stats.get("damage", 0.0)) + actual
	world.emit_event("damage", {"entity_id": int(b.id), "shooter_id": int(source.get("shooter_id", -1)), "projectile_id": int(source.get("id", -1)), "pos": Vector2(b.pos), "team": int(source.team), "target_team": 0, "weapon_kind": String(source.kind), "amount": actual, "hp": float(b.hp), "bleeding": false})


func _suppress(world, u: Dictionary, amount: float, source: Dictionary) -> void:
	if String(u.kind) == "heavy":
		amount *= 0.5
	if amount <= 0.0:
		return
	var applied: Dictionary = source.get("suppression_applied", {})
	var previous: float = float(applied.get(int(u.id), 0.0))
	if amount <= previous:
		return
	applied[int(u.id)] = amount
	source["suppression_applied"] = applied
	u.suppression = minf(100.0, float(u.suppression) + amount - previous)
	u.last_threat = float(world.time_s)
	u["pressure_event_time"] = float(world.time_s)
	u["pressure_event_serial"] = int(u.get("pressure_event_serial", 0)) + 1
	u["threat_origin"] = Vector2(source.get("start", source.get("pos", u.pos)))


func _blast_barrier(snapshot: Array[Dictionary], origin: Vector2, target: Vector2, excluded_id: int) -> float:
	var closest: float = -1.0
	var coefficient: float = 1.0
	if origin.distance_squared_to(target) < EPS * EPS:
		return coefficient
	for b in snapshot:
		if int(b.id) == excluded_id or float(b.height) < 0.1:
			continue
		var rect: Rect2i = b.rect
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var interval: Vector2 = _segment_rect_interval(origin, target, Rect2(x, y, 1.0, 1.0))
				if interval.x < 0.0 or interval.x >= 1.0 - EPS or interval.y <= closest + EPS:
					continue
				closest = interval.y
				coefficient = 0.15 if bool(b.high) else 0.5
	return coefficient


func _prepare_queries(world) -> void:
	_queries_ready = false
	if not use_spatial_index:
		return
	_query_buildings = world.buildings
	_query_units = world.units
	_building_grid.clear()
	_unit_grid.clear()
	_building_marks.resize(_query_buildings.size())
	_building_marks.fill(0)
	_unit_marks.resize(_query_units.size())
	_unit_marks.fill(0)
	_query_serial = 0
	for i in range(_query_buildings.size()):
		var b: Dictionary = _query_buildings[i]
		if _building_alive(b) and _barrier_type(b) != "floor":
			_index_bounds(_building_grid, Rect2(b.rect).grow(QUERY_PADDING), i)
	for i in range(_query_units.size()):
		var u: Dictionary = _query_units[i]
		if not bool(u.dead) and float(u.hp) > 0.0:
			# Include the full motion envelope, including unconscious/prone bodies.
			_index_bounds(_unit_grid, _segment_bounds(Vector2(u.prev_pos), Vector2(u.pos), _radius(u)), i)
	_queries_ready = true


func _segment_bounds(start: Vector2, end: Vector2, margin: float = 0.0) -> Rect2:
	var padding: float = margin + QUERY_PADDING + (end - start).length() * EPS
	return Rect2(start.min(end), (end - start).abs()).grow(padding)


func _index_bounds(grid: Dictionary, bounds: Rect2, index: int) -> void:
	var first: Vector2i = Vector2i((bounds.position / QUERY_CELL_SIZE).floor())
	var last: Vector2i = Vector2i((bounds.end / QUERY_CELL_SIZE).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not grid.has(cell):
				grid[cell] = []
			grid[cell].append(index)


func _buildings_in_bounds(world, bounds: Rect2) -> Array:
	if not use_spatial_index or not _queries_ready:
		return world.buildings
	return _query_bounds(_building_grid, _query_buildings, _building_marks, bounds)


func _units_in_bounds(world, bounds: Rect2) -> Array:
	if not use_spatial_index or not _queries_ready:
		return world.units
	return _query_bounds(_unit_grid, _query_units, _unit_marks, bounds)


func _query_bounds(grid: Dictionary, entities: Array, marks: PackedInt32Array, bounds: Rect2) -> Array:
	var first: Vector2i = Vector2i((bounds.position / QUERY_CELL_SIZE).floor())
	var last: Vector2i = Vector2i((bounds.end / QUERY_CELL_SIZE).floor())
	# Long diagonal/high-speed sweeps can cover more grid cells than entities.
	if (last.x - first.x + 1) * (last.y - first.y + 1) >= entities.size():
		return entities
	_query_serial += 1
	var indices: Array[int] = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for index in grid.get(Vector2i(x, y), []):
				if marks[index] != _query_serial:
					marks[index] = _query_serial
					indices.append(index)
	# Preserve ties, event order, and the RNG draw order of the exhaustive loops.
	indices.sort()
	var result: Array = []
	for index in indices:
		result.append(entities[index])
	return result


func _moving_circle_hit(start: Vector2, end: Vector2, unit_start: Vector2, unit_end: Vector2, radius: float) -> float:
	var relative: Vector2 = start - unit_start
	var delta: Vector2 = (end - start) - (unit_end - unit_start)
	var c: float = relative.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var a: float = delta.length_squared()
	if a <= EPS * EPS:
		return -1.0
	var b: float = 2.0 * relative.dot(delta)
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var t: float = (-b - sqrt(discriminant)) / (2.0 * a)
	return clampf(t, 0.0, 1.0) if t >= -EPS and t <= 1.0 + EPS else -1.0


# Query and real collision share the same world-distance tolerance. A point
# touching one corner is not a wall crossing, even if slab rounding returns a
# tiny reversed interval. A muzzle truly inside a wall remains blocked.
func _positive_crossing(start: Vector2, end: Vector2, interval: Vector2) -> bool:
	return interval.x>=0.0 and (interval.y-interval.x)*start.distance_to(end)>SEGMENT_TOLERANCE


func _point_inside_rect(point: Vector2, rect: Rect2) -> bool:
	return point.x>rect.position.x and point.x<rect.end.x and point.y>rect.position.y and point.y<rect.end.y


func _segment_rect_interval(start: Vector2, end: Vector2, rect: Rect2) -> Vector2:
	var delta: Vector2 = end - start
	var entry: float = 0.0
	var exit: float = 1.0
	for axis in range(2):
		var value: float = start[axis]
		var minimum: float = rect.position[axis]
		var maximum: float = rect.end[axis]
		if absf(delta[axis]) < EPS:
			if value < minimum - EPS or value > maximum + EPS:
				return Vector2(-1.0, -1.0)
			continue
		var t1: float = (minimum - value) / delta[axis]
		var t2: float = (maximum - value) / delta[axis]
		entry = maxf(entry, minf(t1, t2))
		exit = minf(exit, maxf(t1, t2))
		if entry > exit + EPS:
			return Vector2(-1.0, -1.0)
	return Vector2(clampf(entry, 0.0, 1.0), clampf(exit, 0.0, 1.0))


func _closest_point_rect(point: Vector2, rect: Rect2) -> Vector2:
	return Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))


func _point_rect_distance(point: Vector2, rect: Rect2) -> float:
	return point.distance_to(_closest_point_rect(point, rect))


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var offset: Vector2 = end - start
	if offset.length_squared() < EPS * EPS:
		return point.distance_to(start)
	var t: float = clampf((point - start).dot(offset) / offset.length_squared(), 0.0, 1.0)
	return point.distance_to(start + offset * t)


func _volume(unit: Dictionary) -> float:
	return 0.30 if bool(unit.get("cower", false)) else float(Config.VOLUMES[_posture(unit)])


func _radius(unit: Dictionary) -> float:
	return 0.12 if bool(unit.get("cower", false)) else float(Config.RADII[_posture(unit)])


func _eligible_allies(world, projectile: Dictionary) -> Array[int]:
	var result: Array[int] = []
	if not String(projectile.kind) in ["rifle", "mg"]: return result
	var reference: Vector2 = projectile.fire_reference
	for unit in world.units:
		if int(unit.id) in [int(projectile.shooter_id), int(projectile.target_id)] or int(unit.team) != int(projectile.team) or bool(unit.dead): continue
		var moving: bool = Vector2(unit.get("velocity",Vector2.ZERO)).length_squared() > EPS or bool(unit.get("move_active",false))
		var nearby: bool = reference.distance_to(Vector2(unit.pos)) <= FRIENDLY_LOCAL_RADIUS + SEGMENT_TOLERANCE
		if not moving:
			var delta: Vector2i = Vector2i(Vector2(unit.pos).floor())-Vector2i(reference.floor())
			nearby = absi(delta.x) <= 1 and absi(delta.y) <= 1
		if nearby: result.append(int(unit.id))
	return result


func _body_exempt(projectile: Dictionary, unit: Dictionary, collision_point: Vector2, unit_position: Vector2 = Vector2.INF) -> bool:
	if not String(projectile.kind) in ["rifle", "mg"] or int(unit.id) == int(projectile.target_id) or int(unit.team) != int(projectile.team): return false
	if not projectile.get("exempt_allies", []).has(int(unit.id)): return false
	var reference: Vector2 = projectile.get("fire_reference", projectile.start)
	var at_contact: Vector2 = Vector2(unit.pos) if unit_position == Vector2.INF else unit_position
	return reference.distance_to(at_contact) <= FRIENDLY_LOCAL_RADIUS + SEGMENT_TOLERANCE and reference.distance_to(collision_point) <= FRIENDLY_LOCAL_RADIUS + SEGMENT_TOLERANCE


func _posture(u: Dictionary) -> int:
	return 2 if not bool(u.get("conscious", true)) else clampi(int(u.get("posture", 0)), 0, 2)


func _injury_factor(u: Dictionary) -> float:
	var ratio: float = float(u.hp) / float(u.max_hp)
	return 0.65 if ratio < 0.5 else (0.85 if ratio < 0.75 else 1.0)


func _is_building(entity: Dictionary) -> bool:
	return entity.has("rect")


func _building_alive(b: Dictionary) -> bool:
	return not bool(b.destroyed) and float(b.hp) > 0.0


func _target_alive(target: Dictionary) -> bool:
	if target.is_empty():
		return false
	return _building_alive(target) if _is_building(target) else (not bool(target.dead) and float(target.hp) > 0.0)
