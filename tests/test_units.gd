extends RefCounted

var failures: Array[String] = []

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _quiet(factory: Callable):
	var world = factory.call()
	world.next_wave = 3; world.start_battle()
	return world

func _ticks(world, count: int) -> void:
	for i in range(count): world.step()

func run(factory: Callable) -> Array[String]:
	failures.clear()
	var w = factory.call()
	var mg: Dictionary = w.stations()[0]
	_check(w.submit([1], "operate", {"target_id": mg.id}).ok, "First paused station reservation accepted")
	_check(not w.submit([2], "operate", {"target_id": mg.id}).ok, "Paused station cannot be overbooked")
	_check(w.submit([1], "move", {"position": Vector2(22.5, 30.5)}).ok, "Replacing paused station command accepted")
	_check(w.submit([2], "operate", {"target_id": mg.id}).ok, "Replacement releases projected seat")
	w.start_battle(); w.next_wave = 3; w.step()
	_check(w.units[0].station_id == -1 and w.units[1].station_id == mg.id, "Actual seats agree with paused projection")
	w = _quiet(factory)
	_check(w.submit([1, 2, 3], "move", {"position": Vector2(22.5, 28.5)}).ok, "Group move accepted")
	w.step()
	_check(w.units[0].goal.distance_to(w.units[1].goal) > 0.5, "Group destinations are distinct")
	_ticks(w, 400)
	_check(w.units[0].pos.distance_to(w.units[0].goal) < 0.1, "Continuous movement reaches exact endpoint")
	_check(not w.submit([1], "move", {"position": Vector2(38.5, 38.5)}).ok, "Wall is not a legal endpoint")
	_check(not w.submit([1], "move", {"position": Vector2(15.5, 20.5)}).ok, "Low obstacle cannot be a stopping point")
	var travel = _quiet(factory)
	travel.units[0].pos = Vector2(8.5, 44.5)
	travel.submit([1], "move", {"position": Vector2(38.5, 44.5)})
	var travel_steps := 0
	while travel_steps < 800:
		travel.step(); travel_steps += 1
		if travel.units[0].job == "idle": break
	_check(absi(travel_steps - 720) <= 1 and travel.units[0].pos.distance_to(Vector2(38.5, 44.5)) < 0.0001, "Thirty clear tiles take distance/speed = 12 seconds without per-node lost time: %d steps" % travel_steps)
	# An intermediate point only .01 tiles away must not consume a whole tick.
	travel = _quiet(factory)
	var walker: Dictionary = travel.units[0]
	walker.pos = Vector2(8.5, 44.5); walker.goal = Vector2(10.5, 44.5)
	walker.path = PackedVector2Array([Vector2(8.51, 44.5), walker.goal]); walker.path_index = 0; walker.nav_revision = travel.unit_system.nav_revision
	travel.unit_system._move(travel, walker, 1.0 / 60.0)
	_check(absf(walker.pos.x - (8.5 + 2.5 / 60.0)) < 0.00001, "One physics step consumes full movement budget across a short waypoint")
	travel = _quiet(factory); walker = travel.units[0]
	walker.pos = Vector2(8.5, 44.5)
	travel.submit([1], "posture", {"value": 2}); travel.submit([1], "move", {"position": Vector2(20.5, 44.5)}); travel.step()
	_check(walker.posture_timer > 0.65 and walker.pos.x > 8.5, "Posture transition retains its .7-second timer while continuous movement continues")
	walker.suppression = 60.0; walker.last_threat = travel.time_s
	var pressed_position: Vector2 = walker.pos
	travel.step(); _ticks(travel, 30)
	_check(walker.forced_prone and walker.pos == pressed_position, "Forced suppression still stops movement independently of posture transition")
	travel = _quiet(factory); walker = travel.units[0]
	walker.pos = Vector2(8.5, 44.5)
	travel.submit([1], "move", {"position": Vector2(10.5, 44.5)}); travel.step()
	# An arriving conscious unit dynamically occupies the previously free goal.
	travel.units[1].pos = Vector2(10.5, 44.5); _ticks(travel, 360)
	_check(walker.job == "idle" and walker.status.contains("阻挡"), "Lateral motion without net progress terminates a genuinely blocked order")
	travel = _quiet(factory)
	travel.units[0].pos = Vector2(18.5, 44.5); travel.units[1].pos = Vector2(22.5, 44.5)
	travel.submit([1], "move", {"position": Vector2(24.5, 44.5)})
	travel.submit([2], "move", {"position": Vector2(16.5, 44.5)})
	var minimum_separation := INF
	for i in range(600):
		travel.step(); minimum_separation = minf(minimum_separation, travel.units[0].pos.distance_to(travel.units[1].pos))
	_check(minimum_separation >= 0.419 and travel.units[0].pos.distance_to(Vector2(24.5, 44.5)) < 0.05 and travel.units[1].pos.distance_to(Vector2(16.5, 44.5)) < 0.05, "Two opposite movers pass each other without overlap or false deadlock: " + str([travel.units[0].pos, travel.units[1].pos, minimum_separation]))
	travel = _quiet(factory)
	travel.submit([1, 2, 3, 4, 5, 6], "move", {"position": Vector2(23.5, 30.5)})
	_ticks(travel, 1500)
	var group_arrived := true
	for member in travel.units:
		if member.pos.distance_to(member.goal) > 0.05 or member.job != "idle": group_arrived = false
	_check(group_arrived, "All six members converge on distinct group destinations without avoidance deadlock")
	var reloading = _quiet(factory)
	reloading.units[0].loaded = 0; reloading.units[0].reload_progress = 1.4; reloading.units[0].reload_reserved = 30
	reloading.submit([1], "move", {"position": Vector2(24.5, 30.5)}); reloading.step()
	_check(reloading.units[0].reload_progress > 1.4 and reloading.units[0].reload_reserved == 30, "Ordinary movement preserves an in-progress personal reload")
	reloading.submit([1], "attack", {"target_id": reloading.core().id}); reloading.step()
	_check(reloading.units[0].reload_progress > 1.4, "Ordinary target assignment preserves personal reload")
	reloading.submit([1], "stop"); reloading.step()
	_check(reloading.units[0].reload_progress < 0.1, "Stop cancels prior reload before a fresh one can start")
	w.units[0].pos = Vector2(37.5, 37.5)
	_check(w.submit([1], "move", {"position": Vector2(40.5, 40.5)}).ok, "Wall detour is reachable")
	var crossed_wall := false
	for i in range(500):
		w.step()
		var building: Dictionary = w.building_at(Vector2i(w.units[0].pos.floor()))
		if not building.is_empty() and building.high: crossed_wall = true
	_check(not crossed_wall and w.units[0].pos.distance_to(Vector2(40.5, 40.5)) < 0.2, "Navigation goes around walls without crossing")
	w = _quiet(factory); mg = w.stations()[0]
	w.units[0].pos = Vector2(27.5, 28.5)
	_check(w.submit([1], "resupply", {"target_id": mg.id}).ok, "Manual resupply accepted")
	w.step(); _ticks(w, 120)
	var box: Dictionary = {}
	for s in w.supplies:
		if s.carried_by == 1: box = s
	_check(not box.is_empty(), "Supply pickup produces carried physical box")
	_check(w.submit([1], "stop").ok, "Carrying task can be cancelled")
	w.step()
	_check(w.units[0].crate_id == -1 and mg.supply_reserved == 0, "Cancel clears capacity and unit reservations")
	if not box.is_empty(): _check(not box.delivered and box.carried_by == -1 and box.reserved_by == -1 and box.amount == 200, "Cancelled box remains on ground unchanged")
	_check(w.submit([1], "resupply", {"target_id": mg.id}).ok, "Dropped box can be claimed again")
	_ticks(w, 700)
	_check(mg.ammo == 200 and mg.supply_reserved == 0, "Delivery adds exactly one box")
	w = _quiet(factory)
	var mortar: Dictionary = w.stations()[2]
	w.units[0].pos = mortar.crew_points[0]; w.units[1].pos = mortar.crew_points[1]
	_check(w.submit([1, 2], "operate", {"target_id": mortar.id}).ok, "Two mortar operators accepted")
	_check(w.submit([1], "fire", {"target_id": mortar.id, "position": Vector2(32.5, 12.5)}).ok, "Fire intent accepts reserved operator before arrival")
	w.step()
	_check(w.units[0].station_id == mortar.id and mortar.fire_requested, "Fire is a station subcommand")
	_check(not w.submit([1], "attack", {"target_id": w.core().id}).ok, "Mortar attack requires ground fire UI")
	w.units[0].hp = 20.0; w.unit_system.finalize(w)
	_check(w.units[0].station_id == -1 and mortar.crew.size() == 1 and mortar.crew[0] == 2, "Downed gunner releases slot and promotes loader")
	_check(mortar.fire_requested, "Gunner replacement preserves fire point")
	w = _quiet(factory); mortar = w.stations()[2]; mortar.ammo = 8
	w.units[0].pos = Vector2(20.5, 35.5); w.units[1].pos = mortar.crew_points[1]
	w.submit([1, 2], "operate", {"target_id": mortar.id}); _ticks(w, 500)
	_check(mortar.crew.size() == 2 and mortar.crew[0] == 2, "First actual arrival becomes gunner")
	_check(w.units[1].pos.distance_to(mortar.crew_points[0]) < 0.05 and w.units[0].pos.distance_to(mortar.crew_points[1]) < 0.05, "Arrival reorders role positions without overlapping operators: " + str([w.units[0].pos, w.units[0].stage, w.units[0].goal, w.units[0].path_index, w.units[0].path, w.units[1].pos, w.units[1].stage, w.units[1].goal]))
	w.units[1].hp = 20.0; w.unit_system.finalize(w); _ticks(w, 120)
	_check(w.units[0].stage == "station" and w.units[0].pos.distance_to(mortar.crew_points[0]) < 0.05, "Promoted loader reaches the vacated gunner point")
	w = _quiet(factory)
	var u: Dictionary = w.units[0]
	u.hp = 25.0; w.unit_system.finalize(w); _check(u.conscious, "HP exactly 25 is conscious")
	u.hp = 24.9; w.unit_system.finalize(w); _check(not u.conscious, "HP below 25 collapses")
	u.hp = 35.0; w.unit_system.finalize(w); _check(not u.conscious, "HP exactly 35 stays unconscious")
	u.hp = 35.1; w.unit_system.finalize(w); _check(u.conscious, "HP above 35 wakes")
	u.hp = 0.0; w.unit_system.finalize(w); _check(u.dead, "HP zero dies")
	w = _quiet(factory); u = w.units[0]
	u.hp = 50.0; _ticks(w, 60)
	_check(absf(u.hp - 50.001) < 0.00001, "Natural healing is 0.001 HP per second")
	u.suppression = 60.0; u.last_threat = w.time_s; w.unit_system.finalize(w)
	_check(u.forced_prone and u.posture == 2, "Pressure forces prone")
	u.suppression = 100.0; w.unit_system.finalize(w)
	_check(u.job == "rout" and not u.drafted, "Maximum pressure causes undraft and rout")
	_check(not w.submit([1], "draft", {"value": true}).ok, "Rout cooldown rejects draft")
	_ticks(w, 601)
	_check(w.submit([1], "draft", {"value": true}).ok, "Draft is available when ten-second cooldown expires")
	w = _quiet(factory)
	w.units[0].pos = Vector2(39.0, 40.5); w.units[1].pos = Vector2(39.5, 40.5)
	w.units[1].hp = 20.0; w.units[1].conscious = false; w.units[1].bleed_rate = 0.1
	_check(w.submit([1], "treat", {"target_id": 2}).ok, "Field treatment accepted")
	_ticks(w, 380)
	_check(w.units[1].bleed_rate == 0.0 and w.units[1].hp < 20.0 and w.units[0].bandages == 1, "Treatment stops blood loss without healing and spends one bandage")
	w = _quiet(factory)
	w.units[0].pos = Vector2(28.5, 31.5); w.units[1].pos = Vector2(29.0, 31.5)
	w.units[1].hp = 20.0; w.units[1].conscious = false; w.units[1].bleed_rate = 0.1
	_check(w.submit([1], "rescue", {"target_id": 2}).ok, "Rescue accepted")
	_check(not w.submit([3], "rescue", {"target_id": 2}).ok, "Paused rescue cannot reserve the same patient twice")
	_ticks(w, 100)
	_check(w.units[1].carrier_id == 1 and w.units[1].hp < 20.0, "Carried patient continues bleeding")
	w.submit([1], "stop"); w.step()
	_check(w.units[1].carrier_id == -1 and w.medical_reservations.is_empty(), "Cancelling rescue drops patient and releases medical slot")
	w = _quiet(factory); w.spawn_wave(0)
	var enemy: Dictionary = w.units[6]
	enemy.pos = Vector2(1.5, 24.5)
	enemy.suppression = 100.0; enemy.last_threat = w.time_s; w.unit_system.finalize(w)
	_check(enemy.job == "rout" and enemy.goal.distance_to(enemy.spawn_entry) < 0.05, "Enemy rout prefers its own entry even when another entry is nearer")
	_ticks(w, 650)
	_check(enemy.job != "rout" and enemy.rout_until <= w.time_s, "Enemy AI resumes after suppression cooldown")
	_test_enemy_contract(factory)
	_test_logistics_medical_contract(factory)
	return failures

func _isolated_enemy(factory: Callable, position: Vector2, kind: String = "rifleman"):
	var w = _quiet(factory)
	for ally in w.units:
		ally.dead = int(ally.id) != 1; ally.conscious = not ally.dead; ally.drafted = false
		ally.pos = Vector2(60.5, 44.5)
	w._spawn_enemy(position, kind)
	w.unit_system._ensure_unit(w.units[-1])
	return w

func _test_enemy_contract(factory: Callable) -> void:
	var w = _isolated_enemy(factory, Vector2(32.5, 33.5))
	var enemy: Dictionary = w.units[-1]
	var operator: Dictionary = w.units[0]; var rifle: Dictionary = w.units[1]
	operator.pos = Vector2(40.5, 30.5); operator.station_id = int(w.stations()[1].id)
	rifle.dead = false; rifle.conscious = true; rifle.pos = Vector2(33.5, 33.5)
	w.unit_system._enemy_ai(w, enemy)
	_check(enemy.target_id == operator.id, "Enemy strictly prefers a more distant operator to a nearer awake rifleman or core")
	operator.dead = true; w.unit_system._enemy_ai(w, enemy)
	_check(enemy.target_id == rifle.id, "Enemy prefers awake defender to core")
	rifle.conscious = false; w.unit_system._enemy_ai(w, enemy)
	_check(enemy.target_id == w.core().id, "Visible core outranks an adjacent unconscious defender")
	operator.dead = false; operator.station_id = -1; operator.conscious = true; operator.pos = Vector2(31.5, 33.5)
	rifle.conscious = true; rifle.pos = Vector2(33.5, 33.5)
	w.units.reverse(); w.unit_system._enemy_ai(w, enemy)
	_check(enemy.target_id == 1, "Equal priority and distance resolve by entity ID independently of array order")
	operator.pos = Vector2(30.5, 33.5); w.unit_system._enemy_ai(w, enemy)
	_check(enemy.target_id == 2, "Same-priority target chooses distance before entity ID")
	w = _isolated_enemy(factory, Vector2(32.5, 12.5), "heavy"); enemy = w.units[-1]
	w.units[0].pos = Vector2(32.5, 23.5)
	w.unit_system._enemy_ai(w, enemy)
	_check(not enemy.path.is_empty() and enemy.goal.y > enemy.pos.y + 2.0 and enemy.goal.distance_to(enemy.pos) <= 6.0001, "Heavy selects a reachable forward firing point within six tiles instead of stopping at first sight")
	var held_goal: Vector2 = enemy.goal
	w.time_s = 0.25; w.unit_system._enemy_ai(w, enemy)
	_check(enemy.goal == held_goal and enemy.ai_hold_until == 2.0, "Enemy keeps a selected firing position for two seconds")
	w = _isolated_enemy(factory, Vector2(0.6, 18.6), "flanker"); enemy = w.units[-1]
	w.unit_system._enemy_ai(w, enemy)
	_check(enemy.goal.y >= 35.5 and enemy.goal.distance_to(Vector2(10.5, 31.5)) > 1.0, "Flanker without a visible target follows a reachable core approach rather than a fixed flank waypoint")
	# The same viable point has exactly the contracted flanker arc bonus.
	w = _isolated_enemy(factory, Vector2(8.5, 25.5), "flanker"); enemy = w.units[-1]
	w.units[0].pos = Vector2(8.5, 30.5)
	var outside_score: float = w.unit_system._cover_score(w, enemy, w.units[0], enemy.pos)
	for station in w.stations():
		if station.kind == "mg": station.facing = (enemy.pos - station.pos).angle()
	var inside_score: float = w.unit_system._cover_score(w, enemy, w.units[0], enemy.pos)
	_check(absf(outside_score - inside_score - 2.0) < 0.00001, "Flanker adds two points only outside both machine-gun arcs")
	w = _isolated_enemy(factory, Vector2(32.5, 35.5)); enemy = w.units[-1]
	enemy.loaded = 0; enemy.reserve = 0
	_ticks(w, 59)
	_check(w.core().hp == 1000.0, "Empty enemy melee cannot damage before one full working second")
	w.step(); _check(w.core().hp == 995.0, "Adjacent empty enemy deals exactly five structural damage per second")
	_ticks(w, 60)
	_check(w.core().hp == 990.0 and w.stats.rifle_shots == 0 and enemy.status.contains("近战"), "Empty enemy sustains structural melee without inventing rifle ammunition")
	enemy.forced_prone = true; enemy.forced_until = w.time_s + 10.0; enemy.suppression = 70.0; enemy.last_threat = w.time_s
	_ticks(w, 60)
	_check(w.core().hp == 990.0, "Forced prone interrupts structural melee without shortening suppression")
	w = _isolated_enemy(factory, Vector2(32.5, 33.5)); enemy = w.units[-1]
	enemy.loaded = 0; enemy.reserve = 0
	for x in range(64): w._add_building("wall", Rect2i(x, 34, 1, 1))
	w.unit_system.rebuild_navigation(w)
	_ticks(w, 60)
	var blocker: Dictionary = w.building_at(Vector2i(32, 34))
	_check(enemy.melee_target_id == blocker.id and blocker.hp == 295.0 and w.core().hp == 1000.0, "Unreachable core redirects empty enemy melee to the first blocking wall: " + str([enemy.melee_target_id, blocker.id, blocker.hp, enemy.pos, enemy.status, enemy.goal]))

func _test_logistics_medical_contract(factory: Callable) -> void:
	var w = factory.call(); var mg: Dictionary = w.stations()[0]
	for box in w.supplies:
		if box.kind == "mg_ammo" and box.id != 2000: box.delivered = true
	_check(w.submit([1], "resupply", {"target_id": mg.id}).ok, "First paused carrier reserves the final box")
	_check(not w.submit([2], "resupply", {"target_id": mg.id}).ok and w.supplies[0].reserved_by == -1 and mg.supply_reserved == 0, "Pending box claim prevents duplicates without mutating real supply state")
	w.submit([1], "stop")
	_check(w.submit([2], "resupply", {"target_id": mg.id}).ok, "Replacing the pending task releases the last projected box")
	w.start_battle(); w.next_wave = 3; w.step()
	_check(w.supplies[0].reserved_by == 2 and mg.supply_reserved == 200, "Resuming materializes exactly one last-box reservation")
	w = _quiet(factory); mg = w.stations()[0]
	w.units[0].pos = mg.crew_points[0]; mg.loaded = 0; mg.ammo = 0
	w.submit([1], "operate", {"target_id": mg.id}); w.step()
	_check(w.units[0].job == "operate" and w.units[0].stage == "supply_pickup" and mg.crew.has(1), "Empty machine-gun operator fetches a physical box while retaining its station")
	_ticks(w, 1500)
	_check(w.units[0].stage == "station" and mg.loaded == 100 and mg.ammo == 100 and w.units[0].loaded == 30 and w.units[0].reserve == 150, "Automatic supply returns to post and feeds only the machine gun")
	w = _quiet(factory); mg = w.stations()[0]
	for box in w.supplies: box.delivered = true
	w.units[0].pos = mg.crew_points[0]; mg.loaded = 0
	w.submit([1], "operate", {"target_id": mg.id}); _ticks(w, 120)
	_check(w.units[0].stage == "station" and mg.crew.has(1) and w.units[0].status.contains("缺") and w.units[0].loaded == 30, "No supply retains the empty post and never silently switches to the operator rifle")
	w = _quiet(factory)
	w.units[0].pos = Vector2(39.0, 40.5); w.units[0].bandages = 0
	w.units[1].pos = Vector2(39.5, 40.5); w.units[1].hp = 20.0; w.units[1].conscious = false; w.units[1].bleed_rate = 0.1
	w.submit([1], "rescue", {"target_id": 2}); _ticks(w, 900)
	_check(w.units[0].job == "idle" and w.units[1].carrier_id == -1 and w.units[1].bleed_rate == 0.0 and w.medical_stock == 11 and w.medical_reservations.is_empty(), "Complete rescue transports, places and treats with one hospital medicine, releasing reservations")
	_check(not w.units[1].conscious and w.units[1].hp < 20.0, "Rescue and treatment do not bypass the long natural recovery rule")
	w = _quiet(factory)
	w.units[0].pos = Vector2(39.0, 40.5); w.units[0].bandages = 0; w.medical_stock = 0
	w.units[1].pos = Vector2(39.5, 40.5); w.units[1].hp = 20.0; w.units[1].conscious = false; w.units[1].bleed_rate = 0.1
	w.submit([1], "rescue", {"target_id": 2}); _ticks(w, 400)
	_check(w.units[0].job == "idle" and w.units[1].carrier_id == -1 and w.units[1].bleed_rate == 0.1 and w.units[0].status.contains("缺药"), "Rescue without medicine still places the casualty but reports continued bleeding")
	w = _quiet(factory)
	w.units[0].pos = Vector2(28.5, 31.5); w.units[1].pos = Vector2(29.0, 31.5)
	w.units[1].bleed_rate = 0.1; w.units[1].hp = 60.0
	w.submit([1], "treat", {"target_id": 2}); _ticks(w, 150)
	w.submit([1], "stop"); w.step()
	_check(w.units[0].bandages == 2 and w.units[1].bleed_rate == 0.1 and not w.units[0].treatment_reserved, "Interrupted six-second treatment spends no bandage and leaves the wound active")
