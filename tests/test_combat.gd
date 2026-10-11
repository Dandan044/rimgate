extends RefCounted

const State = preload("res://scripts/sim/state.gd")
const Config = preload("res://scripts/sim/battle_config.gd")
const DT := 1.0 / 60.0

var failures: Array[String] = []


func run(world_factory: Callable) -> Array[String]:
	failures.clear()
	if OS.get_cmdline_user_args().has("--combat-benchmark"):
		_profile_steps(world_factory)
	_probability_ranges(world_factory)
	_cover_geometry(world_factory)
	_sweeps_and_friendly_fire(world_factory)
	_armor_and_suppression(world_factory)
	_explosion_snapshot(world_factory)
	_mortar_cycles(world_factory)
	_reload_conservation(world_factory)
	_weapon_rules(world_factory)
	_terminal_trails(world_factory)
	_cross_module_orders(world_factory)
	_spatial_equivalence(world_factory)
	return failures


func _empty(world_factory: Callable):
	var world = world_factory.call()
	world.units.clear()
	world.buildings.clear()
	world.supplies.clear()
	world.projectiles.clear()
	world.events.clear()
	world.rng.seed = Config.SEED
	world.phase = "running"
	return world


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _close(actual: float, expected: float, message: String, tolerance: float = 0.001) -> void:
	_check(absf(actual - expected) <= tolerance, "%s: got %.6f, expected %.6f" % [message, actual, expected])


func _tick(world, count: int) -> void:
	for i in range(count):
		world.step_index += 1
		world.time_s += DT
		world.combat_system.update(world, DT)


func _fast_rifle() -> Dictionary:
	var weapon: Dictionary = Config.rifle()
	weapon.speed = 10000.0
	return weapon


func _probability_ranges(factory: Callable) -> void:
	var bare: float = _sample_arrivals(factory, -1.0, false)
	var half: float = _sample_arrivals(factory, 0.5, false)
	var capped: float = _sample_arrivals(factory, 3.0, false)
	var multi: float = _sample_arrivals(factory, 0.5, true)
	_close(bare, 0.60, "20,000 real projectiles without cover", 0.015)
	_close(half, 0.30, "20,000 real projectiles with independent P=.6/C=.5", 0.015)
	_close(capped, 0.09, "20,000 real projectiles with C capped at .85", 0.015)
	_close(multi, 0.30, "20,000 projectiles through multi-cell and adjacent cover", 0.015)
	print("COMBAT_RANGE samples=80000 bare=%.4f P.6_C.5=%.4f cap=%.4f multi=%.4f" % [bare, half, capped, multi])


func _sample_arrivals(factory: Callable, screen: float, multi: bool) -> float:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	var target: Dictionary = State.unit(100, 1, Vector2(8.5, 5.5))
	world.units.append(shooter)
	world.units.append(target)
	if screen >= 0.0:
		var cover: Dictionary = State.building(1000, "sandbag", Rect2i(6, 4, 2, 2) if multi else Rect2i(7, 5, 1, 1))
		cover.screen_volume = screen
		cover.hp = 10000000.0
		world.buildings.append(cover)
		if multi:
			var farther: Dictionary = State.building(1001, "sandbag", Rect2i(5, 5, 1, 1))
			farther.screen_volume = 0.85
			farther.hp = 10000000.0
			world.buildings.append(farther)
	var weapon: Dictionary = _fast_rifle()
	var arrivals: int = 0
	for i in range(20000):
		target.hp = 100.0
		target.bleed_rate = 0.0
		target.suppression = 0.0
		world.combat_system.spawn_direct_projectile(world, shooter, target, weapon, 0.6)
		world.combat_system.advance_projectiles(world, DT)
		if float(target.hp) < 100.0:
			arrivals += 1
	_check(world.projectiles.is_empty(), "isolated range does not leak expired projectiles")
	return float(arrivals) / 20000.0


func _cover_geometry(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	var target: Dictionary = State.unit(100, 1, Vector2(8.5, 5.5))
	world.units.append(shooter)
	world.units.append(target)
	var near: Dictionary = State.building(1000, "crate", Rect2i(6, 4, 2, 2))
	var far: Dictionary = State.building(1001, "sandbag", Rect2i(5, 5, 1, 1))
	world.buildings.append(near)
	world.buildings.append(far)
	var cover: Dictionary = world.cover_for(target, shooter.pos)
	_check(int(cover.building_id) == 1000 and Vector2i(cover.cell) == Vector2i(7, 5), "2x2 cover chooses the nearest incoming cell")
	_close(float(cover.chance), 0.55, "multi-cell cover volume is not summed")
	_check(not bool(cover.blocked), "standing can shoot over crate")
	target.posture = 1
	_check(not bool(world.cover_for(target, shooter.pos).blocked), "crate at exact .75 crouch height is not a relative wall")
	target.posture = 0
	var side: Dictionary = world.cover_for(target, Vector2(8.5, 0.5))
	_close(float(side.chance), 0.0, "side fire receives no frontal cover")
	target.posture = 2
	_check(bool(world.cover_for(target, shooter.pos).blocked), "prone sandbag/crate is a relative wall")
	_check(not world.combat_system.has_line_of_fire(world, shooter, target), "relative wall rejects direct aim")
	target.posture = 0
	shooter.stability = 1.0
	var weapon: Dictionary = Config.rifle()
	weapon.accuracy_near = 2.0
	weapon.accuracy_far = 2.0
	_close(world.combat_system.hit_probability(shooter, target, weapon), 0.95, "P upper clamp")
	weapon.accuracy_near = 0.0
	weapon.accuracy_far = 0.0
	_close(world.combat_system.hit_probability(shooter, target, weapon), 0.02, "P lower clamp")
	near.hp = 1.0
	_close(float(world.cover_for(target, shooter.pos).chance), 0.55, "damaged cover preserves interception")
	near.hp = 0.0
	_close(float(world.cover_for(target, shooter.pos).chance), 0.0, "destroyed cover stops protecting immediately")


func _sweeps_and_friendly_fire(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	var target: Dictionary = State.unit(100, 1, Vector2(11.5, 5.5))
	world.units.append(shooter)
	world.units.append(target)
	var wall: Dictionary = State.building(1000, "wall", Rect2i(6, 4, 1, 3))
	world.buildings.append(wall)
	_check(not world.combat_system.has_line_of_fire(world, shooter, target), "wall rejects aim")
	world.combat_system.spawn_direct_projectile(world, shooter, target, _fast_rifle(), 1.0)
	world.combat_system.advance_projectiles(world, DT)
	_close(float(target.hp), 100.0, "fast projectile cannot tunnel through wall")
	_close(float(wall.hp), 295.5, "wall takes kinetic building damage")
	shooter.pos = Vector2(6.5, 5.5)
	_check(not world.combat_system.has_line_of_fire(world, shooter, target), "muzzle inside wall cannot fire")
	shooter.pos = Vector2(2.5, 5.5)
	world.buildings.clear()
	var low: Dictionary = State.building(1001, "sandbag", Rect2i(5, 5, 1, 1))
	world.buildings.append(low)
	world.combat_system.spawn_direct_projectile(world, shooter, target, _fast_rifle(), 1.0)
	world.combat_system.advance_projectiles(world, DT)
	_close(float(target.hp), 82.0, "distant low obstacle is transparent")
	_close(float(low.hp), 200.0, "distant low obstacle is not damaged incidentally")
	world.combat_system.spawn_direct_projectile(world, shooter, low, _fast_rifle(), 1.0)
	world.combat_system.advance_projectiles(world, DT)
	_close(float(low.hp), 195.5, "explicit low-building target can be damaged")
	world.buildings.clear()
	target.hp = 100.0
	var friend: Dictionary = State.unit(2, 0, Vector2(5.5, 5.5))
	world.units.append(friend)
	world.combat_system.spawn_direct_projectile(world, shooter, target, _fast_rifle(), 1.0)
	world.combat_system.advance_projectiles(world, DT)
	_close(float(friend.hp), 82.0, "nearest friendly body intercepts an accurate bullet")
	_close(float(target.hp), 100.0, "first impact ends bullet")
	friend.hp = 100.0
	var miss: Dictionary = world.combat_system.spawn_direct_projectile(world, shooter, target, _fast_rifle(), 0.0)
	friend.pos = Vector2(shooter.pos) + Vector2(miss.dir) * 4.0
	friend.prev_pos = friend.pos
	world.combat_system.advance_projectiles(world, DT)
	_close(float(friend.hp), 82.0, "a deliberately missed bullet can hit a friendly")
	_close(float(target.hp), 100.0, "miss direction avoids the original silhouette")
	world.units.erase(friend)
	var accurate: Dictionary = world.combat_system.spawn_direct_projectile(world, shooter, target, Config.rifle(), 1.0)
	target.pos = Vector2(11.5, 7.5)
	target.prev_pos = target.pos
	world.combat_system.advance_projectiles(world, 0.2)
	_close(float(target.hp), 100.0, "original target moving away evades a fixed-direction shot")
	_check(Vector2(accurate.dir).is_equal_approx(Vector2.RIGHT), "accurate projectile does not track")
	world.projectiles.clear()
	target.pos = Vector2(11.5, 5.5)
	target.prev_pos = target.pos
	var crossing: Dictionary = State.unit(101, 1, Vector2(5.5, 6.5))
	crossing.prev_pos = Vector2(5.5, 4.5)
	world.units.append(crossing)
	var crossing_weapon: Dictionary = Config.rifle()
	crossing_weapon.speed = 360.0
	world.combat_system.spawn_direct_projectile(world, shooter, target, crossing_weapon, 1.0)
	world.combat_system.advance_projectiles(world, DT)
	_close(float(crossing.hp), 82.0, "sweep includes previous and current unit positions")


func _armor_and_suppression(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	var heavy: Dictionary = State.unit(100, 1, Vector2(8.5, 5.5), "heavy")
	world.units.append(shooter)
	world.units.append(heavy)
	world.combat_system.spawn_direct_projectile(world, shooter, heavy, _fast_rifle(), 1.0)
	world.combat_system.advance_projectiles(world, DT)
	_close(float(heavy.hp), 145.5, "rifle against heavy armor receives quarter damage")
	_close(float(heavy.bleed_rate), 4.5 * 0.003, "bleeding follows actual armored damage")
	_close(float(heavy.suppression), 12.0, "direct hit and near miss take the maximum once")
	var mg: Dictionary = Config.machine_gun()
	mg.speed = 10000.0
	world.combat_system.spawn_direct_projectile(world, shooter, heavy, mg, 1.0)
	world.combat_system.advance_projectiles(world, DT)
	_close(float(heavy.hp), 121.5, "MG penetration matches heavy armor")
	world.units.erase(heavy)
	var near: Dictionary = State.unit(101, 1, Vector2(6.5, 6.1))
	world.units.append(near)
	var distant: Dictionary = State.unit(102, 1, Vector2(15.5, 5.5))
	world.combat_system.spawn_direct_projectile(world, shooter, distant, Config.rifle(), 1.0)
	for i in range(12):
		world.combat_system.advance_projectiles(world, 0.01)
	_close(float(near.hp), 100.0, "near miss is not a body hit")
	_close(float(near.suppression), 4.0, "one projectile does not repeatedly apply near-miss suppression")


func _explosion_snapshot(factory: Callable) -> void:
	var world = _empty(factory)
	var victim: Dictionary = State.unit(1, 0, Vector2(6.5, 5.5))
	world.units.append(victim)
	var wall: Dictionary = State.building(1000, "wall", Rect2i(5, 4, 1, 3))
	wall.hp = 1.0
	world.buildings.append(wall)
	var crate: Dictionary = State.building(1001, "crate", Rect2i(4, 7, 2, 2))
	world.buildings.append(crate)
	world.combat_system.explode(world, Vector2(4.5, 5.5), 0, 1)
	_close(float(wall.hp), 0.0, "blast destroys weak wall")
	_close(float(victim.hp), 92.5, "same blast uses wall state before destruction")
	_close(float(victim.bleed_rate), 0.0, "shock wave does not cause bleeding")
	_close(float(crate.hp), 306.25, "multi-cell building takes one nearest-rectangle blast result")
	var crate_hits: int = 0
	for event in world.events:
		if event.type == "damage" and int(event.entity_id) == int(crate.id):
			crate_hits += 1
		if event.type in ["damage", "explosion"]:
			_check(event.has("pos") and event.has("team") and event.has("weapon_kind"), "combat events expose immutable visual context")
	_check(crate_hits == 1, "blast damages an entire multi-cell building once")
	_check(world.projectiles.size() == 24, "blast generates 24 real fragments")
	var fragment: Dictionary = world.projectiles[0]
	world.combat_system.advance_projectiles(world, DT)
	_check(Vector2(fragment.pos).is_equal_approx(Vector2(4.5, 5.5)), "new fragments wait until next simulation step")
	world.projectiles.clear()
	fragment.dir = Vector2.RIGHT
	fragment.velocity = Vector2.RIGHT * float(fragment.speed)
	world.projectiles.append(fragment)
	world.step_index += 1
	world.combat_system.advance_projectiles(world, 0.05)
	_close(float(victim.hp), 68.5, "next-step fragment passes destroyed wall and can injure its own gunner")
	_close(float(victim.bleed_rate), 24.0 * 0.003, "fragment bleeding and friendly damage are real")
	_check(int(world.stats.friendly_fire) >= 2, "shock wave and fragment both count friendly injury")
	var prone_world = _empty(factory)
	var prone: Dictionary = State.unit(2, 0, Vector2(6.5, 5.5))
	prone.posture = 2
	prone_world.units.append(prone)
	prone_world.buildings.append(State.building(1002, "sandbag", Rect2i(5, 5, 1, 1)))
	prone_world.combat_system.explode(prone_world, Vector2(3.5, 5.5), 1)
	_close(float(prone.hp), 91.875, "prone low cover gives blast reduction, never immunity")
	var heavy_world = _empty(factory)
	var heavy: Dictionary = State.unit(100, 1, Vector2(5.5, 5.5), "heavy")
	heavy_world.units.append(heavy)
	heavy_world.combat_system.explode(heavy_world, Vector2(4.5, 5.5), 0)
	_close(float(heavy.hp), 105.0, "heavy blast reduction does not use kinetic armor")


func _mortar_world(factory: Callable, count: int):
	var world = _empty(factory)
	var mortar: Dictionary = State.building(1000, "mortar", Rect2i(20, 20, 1, 1))
	mortar.fire_point = Vector2(20.5, 8.5)
	mortar.fire_requested = true
	world.buildings.append(mortar)
	for i in range(count):
		var u: Dictionary = State.unit(i + 1, 0, mortar.crew_points[i])
		u.job = "operate"
		u.stage = "station"
		u.station_id = int(mortar.id)
		u.stability = 1.0
		world.units.append(u)
		mortar.crew.append(int(u.id))
	return world


func _mortar_cycles(factory: Callable) -> void:
	var solo = _mortar_world(factory, 1)
	_tick(solo, 839)
	_check(int(solo.stats.mortar_shots) == 0, "solo mortar cannot fire before 10+4 seconds")
	_tick(solo, 1)
	_check(int(solo.stats.mortar_shots) == 1, "solo mortar fires at 10+4 seconds")
	_check(int(solo.buildings[0].ammo) == 3 and int(solo.buildings[0].loaded) == 0, "mortar ammo is removed at loading and firing")
	_check(not bool(solo.buildings[0].fire_requested), "one bombardment command fires one shell")
	_tick(solo, 179)
	_check(solo.projectiles.size() == 1 and solo.projectiles[0].kind == "mortar", "mortar shell flies for full three seconds")
	_tick(solo, 1)
	_check(solo.projectiles.size() == 24 and solo.projectiles[0].kind == "fragment", "mortar flight ends in explosion and deferred fragments")
	var duo = _mortar_world(factory, 2)
	_tick(duo, 479)
	_check(int(duo.stats.mortar_shots) == 0, "two-person mortar cannot fire before 4+4 seconds")
	_tick(duo, 1)
	_check(int(duo.stats.mortar_shots) == 1, "two-person mortar fires at 4+4 seconds")
	var suppressed = _mortar_world(factory, 2)
	suppressed.units[0].forced_prone = true
	_tick(suppressed, 600)
	_check(int(suppressed.buildings[0].loaded) == 1, "healthy assistant loads while gunner is forced prone")
	_check(int(suppressed.stats.mortar_shots) == 0 and float(suppressed.buildings[0].aim_progress) == 0.0, "forced gunner cannot aim or fire")
	suppressed.units[0].forced_prone = false
	_tick(suppressed, 240)
	_check(int(suppressed.stats.mortar_shots) == 1, "gunner establishes a fresh full aim after interruption")
	var reserved = _mortar_world(factory, 1)
	reserved.units[0].stage = "approach_station"
	_tick(reserved, 60)
	_check(bool(reserved.buildings[0].fire_requested), "reserved approaching gunner retains bombardment intent")
	_close(float(reserved.buildings[0].reload_progress), 0.0, "reserved approaching crew do not perform work")
	reserved.units[0].stage = "supply_pickup"
	_tick(reserved, 60)
	_check(bool(reserved.buildings[0].fire_requested), "internal supply trip retains bombardment intent")
	reserved.units[0].stage = "station"
	_tick(reserved, 300)
	var mortar: Dictionary = reserved.buildings[0]
	_close(float(mortar.reload_progress), 5.0, "single-person loading work accumulates")
	var assistant: Dictionary = State.unit(2, 0, mortar.crew_points[1])
	assistant.job = "operate"
	assistant.stage = "station"
	assistant.station_id = int(mortar.id)
	reserved.units.append(assistant)
	mortar.crew.append(2)
	_tick(reserved, 120)
	_check(int(mortar.loaded) == 1, "adding assistant preserves work and changes remaining speed")
	_tick(reserved, 120)
	mortar.crew.erase(1)
	reserved.units[0].job = "idle"
	reserved.units[0].station_id = -1
	_tick(reserved, 1)
	_close(float(mortar.aim_progress), DT, "gunner replacement restarts aim")
	mortar.crew.clear()
	_tick(reserved, 1)
	_check(not bool(mortar.fire_requested) and int(mortar.loaded) == 1, "all crew leaving cancels intent but preserves chambered shell")


func _reload_conservation(factory: Callable) -> void:
	var world = _empty(factory)
	var u: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	u.loaded = 0
	u.reserve = 45
	world.units.append(u)
	_tick(world, 1)
	_check(int(u.reload_reserved) == 30 and int(u.reserve) == 45, "rifle reload reserves without early ammunition removal")
	_tick(world, 60)
	var progress: float = u.reload_progress
	u.forced_prone = true
	_tick(world, 120)
	_close(float(u.reload_progress), progress, "forced prone pauses personal reload")
	u.forced_prone = false
	u.posture_timer = 1.0
	_tick(world, 60)
	_close(float(u.reload_progress), progress, "posture transition pauses personal reload")
	u.posture_timer = 0.0
	_tick(world, 120)
	_check(int(u.loaded) == 30 and int(u.reserve) == 15 and int(u.reload_reserved) == 0, "completed personal reload transfers ammunition once")
	u.loaded = 0
	_tick(world, 1)
	u.reload_progress = 2.99
	u.job = "treat"
	_tick(world, 1)
	_check(int(u.loaded) == 0 and int(u.reserve) == 15 and int(u.reload_reserved) == 0, "new work at reload completion cancels without consuming ammunition")
	u.job = "idle"
	_tick(world, 1)
	u.reload_progress = 2.99
	u.conscious = false
	_tick(world, 1)
	_check(int(u.loaded) == 0 and int(u.reserve) == 15 and int(u.reload_reserved) == 0, "incapacitation at reload completion preserves ammunition")
	var mg_world = _mortar_world(factory, 1)
	var b: Dictionary = mg_world.buildings[0]
	b.kind = "mg"
	b.loaded = 0
	b.ammo = 200
	b.fire_requested = false
	_tick(mg_world, 1)
	_check(int(b.reload_reserved) == 100 and int(b.ammo) == 200, "MG belt reserves without consuming spare stock")
	_tick(mg_world, 100)
	mg_world.units[0].forced_prone = true
	var belt_progress: float = b.reload_progress
	_tick(mg_world, 100)
	_close(float(b.reload_progress), belt_progress, "forced prone pauses belt change")
	mg_world.units[0].forced_prone = false
	_tick(mg_world, 200)
	_check(int(b.loaded) == 100 and int(b.ammo) == 100 and int(b.reload_reserved) == 0, "belt completion transfers stock exactly once")
	b.loaded = 0
	_tick(mg_world, 1)
	_tick(mg_world, 50)
	var replacement: Dictionary = State.unit(2, 0, b.crew_points[0])
	replacement.job = "operate"
	replacement.stage = "station"
	replacement.station_id = int(b.id)
	mg_world.units.append(replacement)
	b.crew.clear()
	b.crew.append(2)
	_tick(mg_world, 1)
	_close(float(b.reload_progress), 0.0, "new MG operator restarts canceled belt change")
	_check(int(b.ammo) == 100 and int(b.loaded) == 0, "operator change preserves belt and stock")


func _weapon_rules(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	var target: Dictionary = State.unit(100, 1, Vector2(10.5, 5.5))
	world.units.append(shooter)
	world.units.append(target)
	shooter.target_id = 100
	shooter["combat_target_id"] = 100
	shooter.stability = 0.5
	target.drafted = false
	target.job = "treat"
	_tick(world, 1)
	_check(int(world.stats.rifle_shots) == 0, "normal standing rifle waits for stability threshold")
	shooter.velocity = Vector2.RIGHT
	shooter.stability = 0.15
	_tick(world, 1)
	_check(int(world.stats.rifle_shots) == 1, "normal moving rifle uses moving stability ceiling")
	shooter.forced_prone = true
	_tick(world, 60)
	_check(int(world.stats.rifle_shots) == 1, "forced prone interrupts even an ongoing burst")
	shooter.forced_prone = false
	shooter.target_id = 9999
	shooter.stability = 1.0
	_tick(world, 60)
	_check(int(world.stats.rifle_shots) == 1, "invalid explicit target does not silently retarget")
	var mg_world = _mortar_world(factory, 1)
	var b: Dictionary = mg_world.buildings[0]
	b.kind = "mg"
	b.loaded = 100
	b.fire_requested = false
	mg_world.units[0].style = 0
	var enemy: Dictionary = State.unit(100, 1, Vector2(20.5, 28.5))
	enemy.job = "treat"
	mg_world.units.append(enemy)
	_tick(mg_world, 1)
	_check(int(mg_world.stats.mg_shots) == 0, "MG respects fixed 120 degree firing arc")
	enemy.pos = Vector2(20.5, 12.5)
	enemy.prev_pos = enemy.pos
	_tick(mg_world, 1)
	_check(int(mg_world.stats.mg_shots) == 1, "station MG fires in arc without intercepting itself")


func _terminal_trails(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	var victim: Dictionary = State.unit(2, 1, Vector2(3.5, 5.5))
	world.units.append(shooter)
	world.units.append(victim)
	var weapon: Dictionary = Config.rifle()
	weapon.speed = 120.0
	var bullet: Dictionary = world.combat_system.spawn_direct_projectile(world, shooter, victim, weapon, 1.0)
	var rng_before: int = world.rng.state
	world.combat_system.advance_projectiles(world, DT)
	_check(world.projectiles.is_empty() and world.combat_system.finished_projectiles.size() == 1, "same-step birth and impact exports exactly one terminal trail")
	if world.combat_system.finished_projectiles.size() != 1:
		return
	var trail: Dictionary = world.combat_system.finished_projectiles[0]
	var hit_distance: float = 1.0 - float(Config.RADII[0])
	_check(trail.reason == "impact" and int(trail.id) == int(bullet.id) and int(trail.step) == int(world.step_index), "terminal trail identifies the original projectile and step")
	_check(Vector2(trail.prev_pos).is_equal_approx(shooter.pos) and Vector2(trail.pos).is_equal_approx(Vector2(shooter.pos) + Vector2.RIGHT * hit_distance), "terminal impact keeps the exact swept start and endpoint")
	_close(float(trail.fraction), hit_distance / 2.0, "terminal hit fraction uses the entire fixed step")
	_close(float(trail.prev_age), 0.0, "new terminal bullet starts at age zero")
	_close(float(trail.age), hit_distance / 120.0, "terminal bullet age follows actual flight time")
	_check(world.rng.state == rng_before, "terminal trail output consumes no RNG")
	var types: Array = []
	for event in world.events:
		types.append(event.type)
	_check(types == ["weapon_fired", "damage", "projectile_impact"], "terminal output preserves the original battle event sequence")
	var final_position: Vector2 = bullet.pos
	trail.pos = Vector2.INF
	trail.velocity = Vector2.ZERO
	_check(Vector2(bullet.pos) == final_position and Vector2(bullet.velocity) == Vector2.RIGHT * 120.0, "terminal trail values do not alias projectile state")
	world.combat_system.advance_projectiles(world, DT)
	_check(world.combat_system.finished_projectiles.is_empty(), "next advance clears old terminal output even with no live projectiles")

	var range_world = _empty(factory)
	var origin: Dictionary = State.unit(1, 0, Vector2.ZERO)
	var distant: Dictionary = State.unit(2, 1, Vector2(10.0, 0.0))
	weapon = Config.rifle()
	weapon.speed = 60.0
	weapon.range = 1.25
	var ranged: Dictionary = range_world.combat_system.spawn_direct_projectile(range_world, origin, distant, weapon, 1.0)
	var events_before: int = range_world.events.size()
	range_world.combat_system.advance_projectiles(range_world, DT)
	_check(range_world.combat_system.finished_projectiles.is_empty(), "surviving bullet does not create a terminal trail")
	range_world.combat_system.advance_projectiles(range_world, DT)
	_check(range_world.projectiles.is_empty() and range_world.combat_system.finished_projectiles.size() == 1, "range expiry exports one terminal trail")
	if range_world.combat_system.finished_projectiles.size() != 1:
		return
	trail = range_world.combat_system.finished_projectiles[0]
	_check(trail.reason == "range" and Vector2(trail.prev_pos) == Vector2.RIGHT and Vector2(trail.pos) == Vector2(1.25, 0.0), "range terminal segment begins at the last live position")
	_close(float(trail.fraction), 0.25, "range expiry fraction includes the shortened final segment")
	_close(float(trail.prev_age), 1.0 / 60.0, "range terminal previous age")
	_close(float(trail.age), 1.25 / 60.0, "range terminal final age")
	_check(range_world.events.size() == events_before and int(range_world.stats.projectile_serial) == int(ranged.id), "range expiry adds no event or combat serial")

	var clipped = _empty(factory)
	var close_victim: Dictionary = State.unit(2, 1, Vector2(1.4, 0.0))
	clipped.units.append(close_victim)
	clipped.combat_system.spawn_direct_projectile(clipped, origin, close_victim, weapon, 1.0)
	clipped.combat_system.advance_projectiles(clipped, DT)
	clipped.combat_system.advance_projectiles(clipped, DT)
	_check(clipped.combat_system.finished_projectiles.size() == 1, "hit within a shortened range segment exports a trail")
	if clipped.combat_system.finished_projectiles.size() == 1:
		trail = clipped.combat_system.finished_projectiles[0]
		_close(float(trail.fraction), 0.4 - float(Config.RADII[0]), "clipped-segment hit time is relative to full dt, not local segment t")

	var fragment_world = _empty(factory)
	weapon = Config.fragment()
	weapon.range = 0.25
	fragment_world.combat_system.spawn_direct_projectile(fragment_world, origin, distant, weapon, 1.0)
	fragment_world.combat_system.advance_projectiles(fragment_world, DT)
	_check(fragment_world.combat_system.finished_projectiles.is_empty(), "deferred newborn fragment has no terminal trail")
	fragment_world.step_index += 1
	fragment_world.combat_system.advance_projectiles(fragment_world, DT)
	_check(fragment_world.combat_system.finished_projectiles.size() == 1 and fragment_world.combat_system.finished_projectiles[0].kind == "fragment", "fragment range expiry uses the same terminal protocol")

	var shell_world = _empty(factory)
	var shell: Dictionary = {"id": 9000, "kind": "mortar", "weapon_kind": "mortar", "team": 0, "shooter_id": 1, "target_id": -1, "pos": Vector2(2.99, 0), "prev_pos": Vector2.ZERO, "start": Vector2.ZERO, "impact": Vector2(3, 0), "velocity": Vector2.RIGHT, "dir": Vector2.RIGHT, "age": 2.99, "life": 0.01, "arc_height": 0.0, "born_step": -1}
	shell_world.projectiles.append(shell)
	shell_world.combat_system.advance_projectiles(shell_world, 0.02)
	_check(shell_world.combat_system.finished_projectiles.size() == 1 and shell_world.projectiles.size() == 24, "ground impact exports only the shell while deferring its live fragments")
	if shell_world.combat_system.finished_projectiles.size() == 1:
		trail = shell_world.combat_system.finished_projectiles[0]
		_check(trail.reason == "ground" and trail.kind == "mortar" and Vector2(trail.pos) == Vector2(3, 0), "mortar terminal trail reaches the actual ground impact")
		_close(float(trail.fraction), 0.5, "mortar ground fraction uses remaining flight time")
		_close(float(trail.prev_age), 2.99, "mortar terminal starts at the prior age")
		_close(float(trail.age), 3.0, "mortar terminal ends at complete flight time")
		for key in ["id", "kind", "weapon_kind", "team", "shooter_id", "prev_pos", "pos", "dir", "velocity", "prev_age", "age", "fraction", "reason", "step"]:
			_check(trail.has(key), "terminal trail protocol includes %s" % key)


func _cross_module_orders(factory: Callable) -> void:
	var world = factory.call()
	world.next_wave = 3
	var u: Dictionary = world.units[0]
	u.loaded = 0
	u.reserve = 150
	u.reload_reserved = 30
	u.reload_progress = 1.0
	_check(bool(world.submit([1], "move", {"position": Vector2(25.7, 35.5)}).ok), "moving during personal reload is legal")
	world.start_battle()
	world.step()
	_check(float(u.reload_progress) > 1.0, "move command preserves an ongoing personal reload")
	for i in range(20):
		world.step()
	_check(String(u.job) == "idle" and float(u.reload_progress) > 1.0, "arrival preserves an ongoing personal reload")
	var hospital = factory.call()
	hospital.next_wave = 3
	hospital.units[0].pos = Vector2(37.0, 40.5)
	hospital.units[1].pos = Vector2(37.5, 40.5)
	hospital.units[1].hp = 20.0
	hospital.units[1].conscious = false
	hospital.units[1].bleed_rate = 0.1
	hospital.units[2].pos = hospital.medical_slots[0]
	var accepted: Dictionary = hospital.submit([1], "rescue", {"target_id": 2})
	_check(bool(accepted.ok), "rescue can choose among available hospital slots")
	if bool(accepted.ok):
		var allocation: Dictionary = hospital.pending_orders[-1].data._allocations[1]
		_check(int(allocation.medical) != 0, "rescue avoids a bed endpoint occupied by a conscious unit")
	var pending = factory.call()
	var station: Dictionary = pending.stations()[0]
	station.ammo = 200
	_check(bool(pending.submit([1], "resupply", {"target_id": station.id}).ok), "one whole crate fits remaining MG capacity")
	_check(not bool(pending.submit([2], "resupply", {"target_id": station.id}).ok), "pending full-crate reservation prevents capacity overbooking")
	var count: int = pending.pending_orders.size()
	_check(not bool(pending.submit([1], "move", {"position": Vector2(38.5, 38.5)}).ok), "invalid replacement is rejected")
	_check(pending.pending_orders.size() == count and pending.pending_orders[-1].kind == "resupply", "invalid replacement preserves previous valid intent")
	pending.reset()
	_check(pending.pending_orders.is_empty() and pending.medical_reservations.is_empty() and int(pending.stations()[0].supply_reserved) == 0, "reset clears hidden logistics intentions")


func _same_combat(indexed, reference, label: String) -> bool:
	var same: bool = true
	for item in ["units", "buildings", "projectiles", "events", "stats"]:
		if indexed.get(item) != reference.get(item):
			_check(false, "%s preserves exhaustive %s and ordering" % [label, item])
			same = false
	if indexed.rng.state != reference.rng.state:
		_check(false, "%s preserves the exact RNG state" % label)
		same = false
	if indexed.combat_system.finished_projectiles != reference.combat_system.finished_projectiles:
		_check(false, "%s preserves terminal rendering output and ordering" % label)
		same = false
	return same


func _equivalence_scene(factory: Callable, seed_value: int):
	var world = _empty(factory)
	var layout: RandomNumberGenerator = RandomNumberGenerator.new()
	layout.seed = seed_value
	for i in range(30):
		var position: Vector2 = Vector2(layout.randf_range(-8.0, 24.0), layout.randf_range(-8.0, 24.0))
		var u: Dictionary = State.unit(i + 1, i % 2, position, "heavy" if i % 4 == 0 else "rifle")
		u.prev_pos = position + Vector2(layout.randf_range(-5.0, 5.0), layout.randf_range(-5.0, 5.0))
		u.posture = i % 3
		u.conscious = i % 11 != 0
		u.job = "treat"
		u.hp = 500.0
		u.max_hp = 500.0
		world.units.append(u)
	for i in range(48):
		var rectangle: Rect2i = Rect2i(layout.randi_range(-8, 23), layout.randi_range(-8, 23), 1 + i % 3, 1 + i % 2)
		var b: Dictionary = State.building(1000 + i, ["sandbag", "crate", "wall"][i % 3], rectangle)
		b.hp = 1.0 if i % 7 == 0 else b.max_hp
		world.buildings.append(b)
	# Exact grid boundaries, overlapping covers, and a body crossing several cells.
	world.units[0].pos = Vector2(8.0, 4.0)
	world.units[0].prev_pos = Vector2(-8.0, 4.0)
	world.units[1].pos = Vector2(8.5, 4.0)
	world.units[1].prev_pos = world.units[1].pos
	world.buildings.append(State.building(2000, "sandbag", Rect2i(7, 3, 1, 2)))
	world.buildings.append(State.building(2001, "crate", Rect2i(6, 3, 2, 2)))
	for i in range(96):
		var weapon: Dictionary = Config.fragment() if i % 5 == 0 else (Config.machine_gun() if i % 3 == 0 else Config.rifle())
		weapon.speed = [80.0, 360.0, 10000.0][i % 3]
		weapon.range = 100.0
		var shooter: Dictionary = world.units[i % world.units.size()]
		var target: Dictionary = world.buildings[i % world.buildings.size()] if i % 9 == 0 else world.units[(i + 7) % world.units.size()]
		world.combat_system.spawn_direct_projectile(world, shooter, target, weapon, 0.6)
	return world


func _spatial_equivalence(factory: Callable) -> void:
	var compared: int = 0
	for scene in range(16):
		var indexed = _equivalence_scene(factory, 8100 + scene)
		var reference = _equivalence_scene(factory, 8100 + scene)
		reference.combat_system.use_spatial_index = false
		for frame in range(12):
			if frame == 3:
				indexed.combat_system.explode(indexed, Vector2(8.0, 4.0), scene % 2, 1)
				reference.combat_system.explode(reference, Vector2(8.0, 4.0), scene % 2, 1)
			if frame == 6:
				# A layout edit between passes must invalidate all old candidates.
				indexed.buildings[0].rect = Rect2i(4, 4, 1, 1)
				reference.buildings[0].rect = Rect2i(4, 4, 1, 1)
				indexed.units[0].pos = Vector2(4.0, -4.0)
				reference.units[0].pos = Vector2(4.0, -4.0)
			_tick(indexed, 1)
			_tick(reference, 1)
			compared += 1
			if not _same_combat(indexed, reference, "spatial scene %d step %d" % [scene, frame]):
				return
	# The actual pressure layout also exercises weapon targeting and unit movement.
	var worlds: Array = [factory.call(), factory.call()]
	worlds[1].combat_system.use_spatial_index = false
	for world in worlds:
		world.spawn_wave(0)
		world.spawn_wave(1)
		world.spawn_wave(2)
		world.next_wave = 3
		world.submit([1], "operate", {"target_id": world.stations()[0].id})
		world.submit([2], "operate", {"target_id": world.stations()[1].id})
		world.submit([3, 4], "operate", {"target_id": world.stations()[2].id})
		world.submit([5], "move", {"position": Vector2(25.5, 21.6)})
		world.submit([6], "move", {"position": Vector2(36.5, 21.6)})
		world.start_battle()
	var weapon: Dictionary = Config.rifle()
	weapon.damage = 0.0
	weapon.range = 40.0
	for frame in range(90):
		for world in worlds:
			for u in world.units:
				u.hp = u.max_hp
				u.dead = false
				u.conscious = true
				u.bleed_rate = 0.0
			while world.projectiles.size() < 256:
				var count: int = world.projectiles.size()
				world.combat_system.spawn_direct_projectile(world, world.units[count % world.units.size()], world.units[(count + 7) % world.units.size()], weapon, 1.0)
			world.step()
		compared += 1
		if not _same_combat(worlds[0], worlds[1], "pressure equivalence step %d" % frame):
			return
	# World.reset reuses the combat object, so stale grids must not survive it.
	for world in worlds:
		world.reset()
		world.start_battle()
		world.step()
	_check(_same_combat(worlds[0], worlds[1], "spatial world reset"), "reset preserves exhaustive combat")
	print("COMBAT_SPATIAL_EQUIVALENCE steps=%d exact_state_and_rng=true" % compared)


func _profile_steps(factory: Callable) -> void:
	var world = factory.call()
	world.spawn_wave(0)
	world.spawn_wave(1)
	world.spawn_wave(2)
	world.next_wave = 3
	world.submit([1], "operate", {"target_id": world.stations()[0].id})
	world.submit([2], "operate", {"target_id": world.stations()[1].id})
	world.submit([3, 4], "operate", {"target_id": world.stations()[2].id})
	world.start_battle()
	world.step()
	var weapon: Dictionary = Config.rifle()
	weapon.damage = 0.0
	weapon.range = 40.0
	var fill_us: int = 0
	var unit_us: int = 0
	var combat_us: int = 0
	var final_us: int = 0
	for i in range(330):
		var start: int = Time.get_ticks_usec()
		for u in world.units:
			u.hp = u.max_hp
			u.bleed_rate = 0.0
			u.dead = false
			u.conscious = true
		for b in world.buildings:
			b.hp = b.max_hp
		while world.projectiles.size() < 256:
			var count: int = world.projectiles.size()
			world.combat_system.spawn_direct_projectile(world, world.units[count % world.units.size()], world.units[(count + 7) % world.units.size()], weapon, 1.0)
		if world.projectiles.size() > 256:
			world.projectiles.resize(256)
		var filled: int = Time.get_ticks_usec()
		world.step_index += 1
		world.time_s += DT
		world.unit_system.update(world, DT)
		var units_done: int = Time.get_ticks_usec()
		world.combat_system.update(world, DT)
		var combat_done: int = Time.get_ticks_usec()
		world.unit_system.finalize(world)
		var finalized: int = Time.get_ticks_usec()
		if i >= 30:
			fill_us += filled - start
			unit_us += units_done - filled
			combat_us += combat_done - units_done
			final_us += finalized - combat_done
	print("COMBAT_MICRO samples=300 fill_ms=%.3f unit_ms=%.3f combat_ms=%.3f final_ms=%.3f total_ms=%.3f" % [fill_us / 300000.0, unit_us / 300000.0, combat_us / 300000.0, final_us / 300000.0, (fill_us + unit_us + combat_us + final_us) / 300000.0])
