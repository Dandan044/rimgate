class_name BattleWorld
extends RefCounted

const Config = preload("res://scripts/sim/battle_config.gd")
const State = preload("res://scripts/sim/state.gd")
const UnitLogic = preload("res://scripts/sim/unit_system.gd")
const CombatLogic = preload("res://scripts/sim/combat_system.gd")
var units: Array[Dictionary] = []
var buildings: Array[Dictionary] = []
var supplies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var events: Array[Dictionary] = []
var pending_orders: Array[Dictionary] = []
var medical_slots: Array[Vector2] = []
var medical_reservations: Dictionary = {}
var medical_stock: int = 12
var phase: String = "preparing"
var time_s: float = 0.0
var step_index: int = 0
var next_wave: int = 0
var result_reason: String = ""
var rng := RandomNumberGenerator.new()
var stats: Dictionary = {}
var unit_system = UnitLogic.new()
var combat_system = CombatLogic.new()
var _event_serial: int = 0
var _next_enemy_id: int = 100
var _order_serial: int = 0

func _init() -> void:
	reset()

func reset() -> void:
	units.clear(); buildings.clear(); supplies.clear(); projectiles.clear(); events.clear(); pending_orders.clear()
	combat_system.finished_projectiles.clear()
	medical_reservations.clear(); medical_slots.clear(); medical_stock = 12
	phase = "preparing"; time_s = 0.0; step_index = 0; next_wave = 0; result_reason = ""; _next_enemy_id = 100; _event_serial = 0; _order_serial = 0
	rng.seed = Config.SEED
	stats = {"rifle_shots": 0, "mg_shots": 0, "mortar_shots": 0, "enemy_spawned": 0, "friendly_fire": 0, "damage": 0.0, "ammo_destroyed": 0}
	for x in [25.5, 27.5, 29.5, 34.5, 36.5, 38.5]:
		units.append(State.unit(units.size() + 1, 0, Vector2(x, 35.5)))
	for x in range(14, 25): _add_building("sandbag", Rect2i(x, 20, 1, 1))
	for x in range(37, 48): _add_building("sandbag", Rect2i(x, 20, 1, 1))
	_add_building("mg", Rect2i(20, 22, 1, 1)); _add_building("mg", Rect2i(43, 22, 1, 1)); _add_building("mortar", Rect2i(32, 29, 1, 1))
	for x in range(24, 29): _add_building("sandbag", Rect2i(x, 33, 1, 1))
	for x in range(36, 41): _add_building("sandbag", Rect2i(x, 33, 1, 1))
	_add_building("core", Rect2i(30, 36, 4, 4)); _add_building("crate", Rect2i(30, 23, 2, 2))
	for x in range(38, 44): _add_building("wall", Rect2i(x, 38, 1, 1))
	for y in [40.5, 42.5]:
		for x in [39.5, 41.5, 43.5]: medical_slots.append(Vector2(x, y))
	for i in range(14):
		supplies.append({"id": 2000 + i, "kind": "mg_ammo" if i < 8 else "mortar_ammo", "amount": 200 if i < 8 else 4, "pos": Vector2(26.5 + i % 4 * 0.65, 28.5 + i / 4 * 0.55), "reserved_by": -1, "carried_by": -1, "delivered": false})
	unit_system.setup(self)
	emit_event("reset")

func _add_building(kind: String, rect: Rect2i) -> void:
	buildings.append(State.building(1000 + buildings.size(), kind, rect))

func entity(id: int) -> Dictionary:
	for u in units:
		if int(u.id) == id: return u
	for b in buildings:
		if int(b.id) == id: return b
	return {}

func core() -> Dictionary:
	for b in buildings:
		if b.kind == "core": return b
	return {}

func building_at(cell: Vector2i) -> Dictionary:
	for b in buildings:
		if not b.destroyed and b.rect.has_point(cell): return b
	return {}

func stations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for b in buildings:
		if int(b.capacity) > 0: result.append(b)
	return result

func projected_station_for(id: int) -> int:
	var u := entity(id)
	var station: int = int(u.get("station_id", -1))
	for order in pending_orders:
		if not order.ids.has(id): continue
		if order.kind == "operate": station = int(order.data.get("target_id", -1))
		elif order.kind in ["move", "stop", "resupply", "rescue", "treat"]: station = -1
		elif order.kind == "draft" and not bool(order.data.get("value", true)): station = -1
	return station

func projected_crew(station_id: int) -> Array[int]:
	var result: Array[int] = []
	for u in units:
		if projected_station_for(int(u.id)) == station_id and not u.dead and u.conscious: result.append(int(u.id))
	return result

func submit(ids: Array, kind: String, data: Dictionary = {}) -> Dictionary:
	if phase in ["won", "lost"]: return {"ok": false, "reason": "战斗已结束"}
	var checked: Dictionary = unit_system.validate_order(self, ids, kind, data)
	if not checked.get("ok", false):
		emit_event("order_rejected", {"reason": checked.get("reason", "命令不可执行")})
		return checked
	_order_serial += 1
	pending_orders.append({"ids": ids.duplicate(), "kind": kind, "data": data.duplicate(true), "serial": _order_serial})
	return {"ok": true, "reason": ""}

func start_battle() -> void:
	if phase == "preparing": phase = "running"; emit_event("battle_started")

func set_paused(paused: bool) -> void:
	if phase in ["running", "paused"]: phase = "paused" if paused else "running"

func step(dt: float = Config.FIXED_DT) -> void:
	if phase != "running": return
	var orders: Array[Dictionary] = pending_orders.duplicate()
	pending_orders.clear()
	for order in orders: unit_system.apply_order(self, order.ids, order.kind, order.data)
	step_index += 1; time_s += dt
	while next_wave < Config.WAVE_TIMES.size() and time_s + 0.00001 >= Config.WAVE_TIMES[next_wave]:
		spawn_wave(next_wave); next_wave += 1
	unit_system.update(self, dt)
	combat_system.update(self, dt)
	unit_system.finalize(self)
	var navigation_dirty := false
	for b in buildings:
		if b.hp <= 0.0 and not b.destroyed:
			b.destroyed = true; navigation_dirty = true
			stats.ammo_destroyed += int(b.ammo) + int(b.loaded)
			b.ammo = 0; b.loaded = 0; b.reload_reserved = 0; b.supply_reserved = 0; b.fire_requested = false
			for id in b.crew.duplicate():
				var crew_unit := entity(int(id))
				if not crew_unit.is_empty(): unit_system.release_station(self, crew_unit)
			emit_event("building_destroyed", {"entity_id": b.id, "pos": b.pos})
	if navigation_dirty: unit_system.rebuild_navigation(self)
	var living := 0
	for u in units:
		if u.team == 0 and not u.dead: living += 1
	if core().hp <= 0: _finish("lost", "核心设施被摧毁")
	elif living == 0: _finish("lost", "全部守军阵亡")
	elif time_s + 0.00001 >= Config.DURATION: _finish("won", "已完成设施守卫")

func spawn_wave(index: int) -> void:
	var groups: Array = [[4, 0, 0, 0], [3, 3, 2, 0], [4, 4, 2, 2]][index]
	for entry in range(3):
		for i in range(int(groups[entry])):
			var p := Vector2(10.6 + i * 1.5, 0.6) if entry == 0 else (Vector2(44.6 + i * 1.5, 0.6) if entry == 1 else Vector2(0.6, 18.6 + i * 2.0))
			_spawn_enemy(p, "flanker" if entry == 2 else "rifleman")
	for i in range(int(groups[3])): _spawn_enemy(Vector2(45.3 + i * 2.0, 1.8), "heavy")
	emit_event("wave_started", {"wave": index + 1})

func _spawn_enemy(pos: Vector2, kind: String) -> void:
	var enemy := State.unit(_next_enemy_id, 1, pos, kind)
	enemy.job = "advance"; enemy.goal = core().pos
	units.append(enemy); _next_enemy_id += 1; stats.enemy_spawned += 1

func _finish(result: String, reason: String) -> void:
	phase = result; result_reason = reason
	emit_event("battle_ended", {"result": result, "reason": reason})

func emit_event(kind: String, data: Dictionary = {}) -> void:
	_event_serial += 1
	var event := data.duplicate()
	event["type"] = kind; event["time"] = time_s; event["step"] = step_index; event["serial"] = _event_serial
	events.append(event)
	if events.size() > 256: events.pop_front()

func cover_for(u: Dictionary, from: Vector2) -> Dictionary:
	return combat_system.cover_for(self, u, from)
