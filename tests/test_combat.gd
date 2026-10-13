extends RefCounted

const State = preload("res://scripts/sim/state.gd")
const Config = preload("res://scripts/sim/battle_config.gd")
const Pose = preload("res://scripts/sim/weapon_pose.gd")
const DT := 1.0 / 60.0

var failures: Array[String] = []


func run(world_factory: Callable) -> Array[String]:
	failures.clear()
	if OS.get_cmdline_user_args().has("--combat-benchmark"):
		_profile_steps(world_factory)
	_probability_ranges(world_factory)
	_probability_formula(world_factory)
	_cover_geometry(world_factory)
	_target_structure_visibility(world_factory)
	_sweeps_and_friendly_fire(world_factory)
	_armor_and_suppression(world_factory)
	_heavy_suppression_entries(world_factory)
	_explosion_snapshot(world_factory)
	_mortar_cycles(world_factory)
	_reload_conservation(world_factory)
	_full_ammunition_budget(world_factory)
	_destroyed_station_ammunition(world_factory)
	_weapon_rules(world_factory)
	_machine_gun_preference(world_factory)
	_unified_cover_boundaries(world_factory)
	_weapon_cycles_and_muzzles(world_factory)
	_mortar_unit_target(world_factory)
	_terminal_trails(world_factory)
	_cross_module_orders(world_factory)
	_v3_cover_intervals(world_factory)
	_v3_wall_corner_consistency(world_factory)
	_v3_ray_cache_lifecycle(world_factory)
	_v3_cover_query_context(world_factory)
	_v3_body_exemptions(world_factory)
	_v3_query_and_styles(world_factory)
	_v3_fire_control_and_preload(world_factory)
	_v3_style_range_metrics(world_factory)
	_v3_query_replay_equivalence(world_factory)
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
	_close(capped, 0.06, "20,000 real projectiles with C approaching .90", 0.015)
	_close(multi, 0.15, "20,000 projectiles through two independent covers, multi-cell once", 0.015)
	print("COMBAT_RANGE samples=80000 bare=%.4f P.6_C.5=%.4f cap=%.4f multi=%.4f" % [bare, half, capped, multi])


func _sample_arrivals(factory: Callable, screen: float, multi: bool) -> float:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2(1.5, 5.5))
	var target: Dictionary = State.unit(100, 1, Vector2(8.5, 5.5))
	world.units.append(shooter)
	world.units.append(target)
	if screen >= 0.0:
		var cover: Dictionary = State.building(1000, "sandbag", Rect2i(6, 4, 2, 2) if multi else Rect2i(7, 5, 1, 1))
		cover.screen_volume = screen
		cover.screening_strength = screen / (0.9 - screen) if screen < 0.9 else 1000000.0
		cover.hp = 10000000.0
		world.buildings.append(cover)
		if multi:
			var farther: Dictionary = State.building(1001, "sandbag", Rect2i(4, 5, 1, 1))
			farther.screen_volume = 0.5
			farther.screening_strength = 1.25
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


func _probability_formula(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2.ZERO)
	var target: Dictionary = State.unit(100, 1, Vector2.ZERO)
	var rifle: Dictionary = Config.rifle()
	shooter.stability = 1.0
	_close(world.combat_system.hit_probability(shooter, target, rifle), 0.6, "default rifle near accuracy")
	target.pos = Vector2(24.0, 0.0)
	_close(world.combat_system.hit_probability(shooter, target, rifle), 0.2, "default rifle range-end accuracy")
	target.pos = Vector2(12.0, 0.0)
	_close(world.combat_system.hit_probability(shooter, target, rifle), 0.4, "default rifle distance interpolation")
	shooter.stability = 0.4
	shooter.suppression = 50.0
	shooter.hp = 60.0
	shooter.style = 2
	target.posture = 1
	# Independently calculated from the contract's literal weapon and body values.
	_close(world.combat_system.hit_probability(shooter, target, rifle), 0.4 * 0.55 * 0.65 * 0.8 * 0.85 * float(Config.STYLE_ACCURACY[2]), "crouch, stability, suppression, injury and cautious style multiply once")
	shooter.stability = 0.8
	shooter.suppression = 25.0
	shooter.hp = 40.0
	shooter.style = 0
	target.pos = Vector2(6.0, 0.0)
	target.posture = 2
	var expected: float = 0.5 * 0.85 * 0.35 * 0.9 * 0.65 * float(Config.STYLE_ACCURACY[0])
	_close(world.combat_system.hit_probability(shooter, target, rifle), expected, "critical injury and prone silhouette use distinct factors")
	var projectile: Dictionary = world.combat_system.spawn_direct_projectile(world, shooter, target, rifle)
	_close(float(projectile.probability), expected, "real projectile uses the default formula without injection")
	var oracle := RandomNumberGenerator.new()
	oracle.seed = Config.SEED
	_check(bool(projectile.accurate) == (oracle.randf() < expected), "default firing decision consumes the formula's Bernoulli sample")
	world.projectiles.clear()
	shooter.stability = 1.0
	shooter.suppression = 0.0
	shooter.hp = 100.0
	shooter.style = 1
	var structure: Dictionary = State.building(1000, "crate", Rect2i(15, 0, 1, 1))
	structure.pos = Vector2(16.0, 0.0)
	# The gunner is 20 cells away; the actual MG muzzle is only 16 cells away.
	shooter.pos = Vector2(-4.0, 0.0)
	projectile = world.combat_system.spawn_direct_projectile(world, shooter, structure, Config.machine_gun(), -1.0, Vector2.ZERO)
	_close(float(projectile.probability), 0.355, "default MG formula measures muzzle range and full building volume")


func _cover_geometry(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	var target: Dictionary = State.unit(100, 1, Vector2(8.5, 5.5))
	world.units.append(shooter)
	world.units.append(target)
	var near: Dictionary = State.building(1000, "crate", Rect2i(6, 4, 2, 2))
	var far: Dictionary = State.building(1001, "sandbag", Rect2i(5, 5, 1, 1))
	near.screening_strength = 2.0
	far.screening_strength = 2.0
	world.buildings.append(near)
	world.buildings.append(far)
	var cover: Dictionary = world.cover_for(target, shooter.pos)
	_check(int(cover.building_id) == 1001 and Vector2i(cover.cell) == Vector2i(5, 5), "path preview starts at first incoming building")
	_check(cover.obstacles.size() == 2 and Vector2i(cover.obstacles[1].cell) == Vector2i(6, 5), "2x2 uses one effective cell and damage is assigned at the entrance")
	_close(float(cover.chance), 0.84, "two independent .6 obstacles aggregate to .84")
	_check(not bool(cover.blocked), "cover is not a wall")
	target.posture = 1
	_check(not bool(world.cover_for(target, shooter.pos).blocked), "crouching never changes a building category")
	target.posture = 0
	_close(float(world.cover_for(target, Vector2(8.5, 0.5)).chance), 0.0, "side fire receives no frontal cover")
	target.posture = 2
	var prone_chance: float = 0.9 * 2.0 / 2.35
	_close(float(world.cover_for(target, shooter.pos).chance), 1.0 - pow(1.0 - prone_chance, 2), "prone volume increases both path interception probabilities")
	_check(not bool(world.cover_for(target, shooter.pos).blocked), "prone cover remains probabilistic")
	_check(world.combat_system.has_line_of_fire(world, shooter, target), "prone behind cover remains a legal direct target")
	target.posture = 0
	target.pos = Vector2(15.5, 5.5)
	_close(float(world.cover_for(target, shooter.pos).chance), 0.84, "target distance does not change path cover")
	shooter.stability = 1.0
	var weapon: Dictionary = Config.rifle()
	weapon.accuracy_near = 2.0
	weapon.accuracy_far = 2.0
	_close(world.combat_system.hit_probability(shooter, target, weapon), 0.95, "P upper clamp")
	weapon.accuracy_near = 0.0
	weapon.accuracy_far = 0.0
	_close(world.combat_system.hit_probability(shooter, target, weapon), 0.02, "P lower clamp")
	near.hp = 1.0
	_close(float(world.cover_for(target, shooter.pos).chance), 0.84, "damaged cover preserves interception")
	near.hp = 0.0
	_close(float(world.cover_for(target, shooter.pos).chance), 0.6, "destroyed cover leaves other path cover active")
	far.hp = 0.0
	_close(float(world.cover_for(target, shooter.pos).chance), 0.0, "all destroyed cover stops protecting immediately")


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
	_close(float(target.hp), 100.0, "distant low obstacle can intercept a shot")
	_close(float(low.hp), 195.5, "intermediate cover takes interception damage")
	world.combat_system.spawn_direct_projectile(world, shooter, low, _fast_rifle(), 1.0)
	world.combat_system.advance_projectiles(world, DT)
	_close(float(low.hp), 191.0, "explicit low-building target can be damaged")
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


func _target_structure_visibility(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(100, 1, Vector2(32.5, 33.5))
	var target: Dictionary = State.building(1000, "wall", Rect2i(32, 34, 1, 1))
	shooter.target_id = int(target.id)
	shooter.style = 0
	shooter.stability = 1.0
	world.units.append(shooter)
	world.buildings.append(target)
	_check(bool(world.cover_for(shooter, target.pos).blocked), "adjacent target wall supplies complete path obstruction")
	_check(world.combat_system.has_line_of_fire(world, shooter, target), "a visible adjacent target wall cannot block an attack on itself")
	_tick(world, 40)
	_check(int(world.stats.rifle_shots) >= 1, "armed attacker aims then fires at its adjacent target wall")
	world.projectiles.clear()
	var intervening: Dictionary = State.building(1001, "wall", Rect2i(32, 35, 1, 1))
	var distant: Dictionary = State.building(1002, "wall", Rect2i(32, 36, 1, 1))
	world.buildings.append(intervening)
	world.buildings.append(distant)
	_check(not world.combat_system.has_line_of_fire(world, shooter, distant), "target exception preserves obstruction by a different high wall")
	# A low obstacle never becomes a wall when the attacker lies down.
	world.buildings.erase(target)
	world.buildings.erase(intervening)
	world.buildings.append(State.building(1003, "sandbag", Rect2i(32, 34, 1, 1)))
	shooter.posture = 2
	_check(world.combat_system.has_line_of_fire(world, shooter, distant), "prone attacker can target a wall beyond probabilistic cover")
	world.buildings.clear()
	world.buildings.append(target)
	shooter.pos = target.pos
	shooter.prev_pos = shooter.pos
	_check(not world.combat_system.has_line_of_fire(world, shooter, target), "attacker inside a high target wall still cannot fire")


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
	_close(float(heavy.suppression), 6.0, "heavy direct hit and near miss take half the maximum once")
	var impact: Dictionary = world.events[-1]
	_check(impact.type == "projectile_impact" and impact.material == "armor" and bool(impact.armor_absorbed), "nonpenetrating armor impact identifies metal feedback without removing actual damage")
	var mg: Dictionary = Config.machine_gun()
	mg.speed = 10000.0
	world.combat_system.spawn_direct_projectile(world, shooter, heavy, mg, 1.0)
	world.combat_system.advance_projectiles(world, DT)
	_close(float(heavy.hp), 121.5, "MG penetration matches heavy armor")
	impact = world.events[-1]
	_check(impact.material == "unit" and not bool(impact.armor_absorbed), "penetrating impact identifies body feedback")
	world.units.erase(heavy)
	var near: Dictionary = State.unit(101, 1, Vector2(6.5, 6.1))
	world.units.append(near)
	var distant: Dictionary = State.unit(102, 1, Vector2(15.5, 5.5))
	world.combat_system.spawn_direct_projectile(world, shooter, distant, Config.rifle(), 1.0)
	for i in range(12):
		world.combat_system.advance_projectiles(world, 0.01)
	_close(float(near.hp), 100.0, "near miss is not a body hit")
	_close(float(near.suppression), 4.0, "one projectile does not repeatedly apply near-miss suppression")


func _heavy_suppression_entries(factory: Callable) -> void:
	for kind in ["rifleman", "heavy"]:
		var scale: float = 0.5 if kind == "heavy" else 1.0
		for weapon_kind in ["rifle", "mg", "fragment"]:
			var world = _empty(factory)
			var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
			var aim: Dictionary = State.unit(101, 1, Vector2(15.5, 5.5))
			var near: Dictionary = State.unit(100, 1, Vector2(6.5, 6.1), kind)
			world.units.append(near)
			var weapon: Dictionary = Config.fragment() if weapon_kind == "fragment" else (Config.machine_gun() if weapon_kind == "mg" else Config.rifle())
			var near_gain: float = 2.0 if weapon_kind == "fragment" else (7.0 if weapon_kind == "mg" else 4.0)
			var projectile: Dictionary = world.combat_system.spawn_direct_projectile(world, shooter, aim, weapon, 1.0)
			for i in range(30):
				world.step_index += 1
				world.combat_system.advance_projectiles(world, DT)
			_close(float(near.hp), float(near.max_hp), "%s %s near miss does not injure" % [kind, weapon_kind])
			_close(float(near.suppression), near_gain * scale, "%s %s repeated flight applies near pressure once" % [kind, weapon_kind])
			# Use this same physical source for a later wound: max(near, hit), not their sum.
			world.combat_system._damage_unit(world, near, 1.0, projectile, true)
			world.combat_system._suppress(world, near, near_gain, projectile)
			_close(float(near.suppression), 12.0 * scale, "%s %s source upgrades near pressure to one hit maximum" % [kind, weapon_kind])
			var hit_world = _empty(factory)
			var victim: Dictionary = State.unit(100, 1, Vector2(8.5, 5.5), kind)
			hit_world.units.append(victim)
			weapon.speed = 10000.0
			hit_world.combat_system.spawn_direct_projectile(hit_world, shooter, victim, weapon, 1.0)
			hit_world.step_index += 1
			hit_world.combat_system.advance_projectiles(hit_world, DT)
			_check(float(victim.hp) < float(victim.max_hp), "%s %s actual direct-hit path injures" % [kind, weapon_kind])
			_close(float(victim.suppression), 12.0 * scale, "%s %s direct-hit pressure shares the heavy coefficient" % [kind, weapon_kind])
		var blast_world = _empty(factory)
		var exposed: Dictionary = State.unit(100, 1, Vector2(5.5, 5.5), kind)
		blast_world.units.append(exposed)
		blast_world.combat_system.explode(blast_world, Vector2(4.5, 5.5), 0)
		_close(float(exposed.suppression), 22.5 * scale, "%s blast and injury pressure share one scaled maximum" % kind)
		_check(blast_world.projectiles.size() == 24, "heavy blast pressure preserves real fragments")


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
	suppressed.units[0].posture = 2
	_tick(suppressed, 600)
	_check(int(suppressed.buildings[0].loaded) == 1, "healthy assistant loads while gunner is forced prone")
	_check(int(suppressed.stats.mortar_shots) == 0 and float(suppressed.buildings[0].aim_progress) == 0.0, "forced gunner cannot aim or fire")
	suppressed.units[0].forced_prone = false
	suppressed.units[0].posture = 0
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
	_check(bool(mortar.fire_requested) and int(mortar.loaded) == 1, "temporarily unavailable crew pause intent and preserve chambered shell")


func _reload_conservation(factory: Callable) -> void:
	var world = _empty(factory)
	var unit: Dictionary = State.unit(1,0,Vector2(2.5,5.5))
	unit.loaded=0; unit.reserve=45
	world.units.append(unit)
	_tick(world,1)
	_check(int(unit.reload_reserved)==30 and int(unit.reserve)==45,"reload reserves without removing spare ammunition")
	_tick(world,60)
	unit.forced_prone=true; unit.posture=2
	var progress: float = unit.reload_progress
	_tick(world,20)
	_check(float(unit.reload_progress)>progress,"stable forced prone on open ground can continue a personal reload")
	unit.posture_timer=1.0
	_tick(world,60)
	_close(float(unit.reload_progress),0.0,"interruption restarts the incomplete preparation stage")
	unit.posture_timer=0.0
	_tick(world,90)
	_check(int(unit.reload_stage)==1,"completed preparation stage is committed")
	unit.velocity=Vector2.RIGHT
	_tick(world,20)
	_close(float(unit.reload_progress),1.5,"movement pauses reload at the completed preparation boundary")
	unit.velocity=Vector2.ZERO
	_tick(world,90)
	_check(int(unit.loaded)==30 and int(unit.reserve)==15 and int(unit.reload_reserved)==0,"resumed insertion transfers ammunition exactly once")
	unit.loaded=0
	_tick(world,1)
	unit.job="treat"
	_tick(world,1)
	_check(int(unit.loaded)==0 and int(unit.reserve)==15 and int(unit.reload_reserved)==15,"incompatible work pauses reservation without consuming ammunition")
	world.combat_system._cancel_reload(unit)
	_check(int(unit.reserve)==15 and int(unit.reload_reserved)==0,"explicit cancellation releases only the reservation")
	unit.job="idle"
	_tick(world,1)
	unit.conscious=false
	_tick(world,1)
	_check(int(unit.loaded)==0 and int(unit.reserve)==15,"incapacitation preserves weapon inventory")
	var mg_world = _mortar_world(factory,1)
	var gun: Dictionary = mg_world.buildings[0]
	gun.kind="mg"; gun.loaded=0; gun.ammo=200; gun.fire_requested=false
	_tick(mg_world,1)
	_check(int(gun.reload_reserved)==100 and int(gun.ammo)==200,"MG belt reservation does not remove stock")
	_tick(mg_world,160)
	_check(int(gun.reload_stage)==1,"MG preparation stage is complete")
	mg_world.units[0].posture=2; mg_world.units[0].forced_prone=true
	_tick(mg_world,100)
	_close(float(gun.reload_progress),2.5,"incompatible prone gunner preserves completed MG preparation")
	mg_world.units[0].posture=0; mg_world.units[0].forced_prone=false
	_tick(mg_world,150)
	_check(int(gun.loaded)==100 and int(gun.ammo)==100 and int(gun.reload_reserved)==0,"belt completion transfers stock once")
	gun.loaded=0
	_tick(mg_world,1)
	_tick(mg_world,160)
	var replacement: Dictionary = State.unit(2,0,gun.crew_points[0])
	replacement.job="operate"; replacement.stage="station"; replacement.station_id=int(gun.id)
	mg_world.units.append(replacement); gun.crew.clear(); gun.crew.append(2)
	_tick(mg_world,1)
	_close(float(gun.reload_progress),2.5+DT,"replacement resumes the completed stage, redoing only incomplete work")
	_check(int(gun.ammo)==100 and int(gun.loaded)==0,"operator replacement creates no ammunition")


func _full_ammunition_budget(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	var target: Dictionary = State.building(1000, "wall", Rect2i(8, 5, 1, 1))
	target.hp = 1000000.0
	shooter.target_id = int(target.id)
	shooter.style = 0
	world.units.append(shooter)
	world.buildings.append(target)
	_check(int(shooter.loaded) + int(shooter.reserve) == 180, "new rifleman's complete finite ammunition budget is 180")
	var completed_reloads: int = 0
	var previous_reserve: int = shooter.reserve
	for i in range(3600):
		# Keep aim ready to isolate the real fire/reload/inventory cycle from recovery.
		shooter.stability = 1.0
		_tick(world, 1)
		if int(shooter.reserve) < previous_reserve:
			completed_reloads += 1
		previous_reserve = int(shooter.reserve)
		if int(shooter.loaded) + int(shooter.reserve) + int(world.stats.rifle_shots) != 180:
			_check(false, "every step conserves all 180 rifle rounds including reload reservations")
			break
	_check(completed_reloads == 5, "all five spare rifle magazines transfer exactly once")
	_check(int(world.stats.rifle_shots) == 180 and int(world.stats.projectile_serial) == 180, "complete ammunition budget creates exactly 180 real projectiles")
	_check(int(shooter.loaded) == 0 and int(shooter.reserve) == 0 and int(shooter.reload_reserved) == 0, "exhaustion leaves no phantom loaded, spare or reserved rifle rounds")
	_check(String(shooter.status) == "步枪弹药耗尽", "empty finite rifle stock reports exhaustion")
	_tick(world, 120)
	_check(int(world.stats.rifle_shots) == 180 and int(world.stats.projectile_serial) == 180, "exhausted rifle cannot create additional shots")
	_check(world.projectiles.is_empty(), "all 180 spent rifle projectiles eventually hit or expire")
	print("COMBAT_AMMUNITION rifle_shots=%d reloads=%d loaded=%d reserve=%d" % [int(world.stats.rifle_shots), completed_reloads, int(shooter.loaded), int(shooter.reserve)])


func _station_ammunition_ledger(world) -> int:
	var total: int = int(world.stats.mg_shots) + int(world.stats.mortar_shots) + int(world.stats.ammo_destroyed)
	for b in world.buildings:
		if b.kind in ["mg", "mortar"]:
			total += int(b.loaded) + int(b.ammo)
	for box in world.supplies:
		if not bool(box.delivered):
			total += int(box.amount)
	return total


func _destroyed_station_ammunition(factory: Callable) -> void:
	var world = factory.call()
	var gun: Dictionary = {}
	var mortar: Dictionary = {}
	for b in world.buildings:
		if b.kind == "mg" and gun.is_empty():
			gun = b
		elif b.kind == "mortar":
			mortar = b
	_check(_station_ammunition_ledger(world) == 1828, "default station stock is 1800 MG rounds plus 28 mortar shells")
	# Construct the valid state after one belt was spent and one actual crate delivered.
	gun.loaded = 0
	gun.ammo = int(world.supplies[0].amount)
	world.supplies[0].delivered = true
	world.stats.mg_shots = 100
	mortar.ammo = 3
	mortar.loaded = 1
	var operator: Dictionary = world.units[0]
	operator.pos = gun.crew_points[0]
	operator.prev_pos = operator.pos
	operator.job = "operate"
	operator.stage = "station"
	operator.station_id = int(gun.id)
	operator.posture_mode = 0
	gun.crew.append(int(operator.id))
	world.next_wave = Config.WAVE_TIMES.size()
	world.start_battle()
	world.step(DT)
	_check(int(gun.reload_reserved) == 100 and int(gun.ammo) == 200, "destruction fixture contains a real reserved but unconsumed MG belt")
	_check(_station_ammunition_ledger(world) == 1828, "belt reservation and chamber loading preserve the complete map ammunition budget")
	gun.hp = 0.0
	mortar.hp = 0.0
	world.step(DT)
	_check(bool(gun.destroyed) and bool(mortar.destroyed), "world finalization destroys both weapon stations")
	_check(int(world.stats.ammo_destroyed) == 204, "destroyed stock counts 200 MG rounds and all four shells, without counting the reserved belt twice")
	_check(int(gun.loaded) == 0 and int(gun.ammo) == 0 and int(gun.reload_reserved) == 0 and int(mortar.loaded) == 0 and int(mortar.ammo) == 0, "destroyed station stock and reload reservation clear")
	_check(gun.crew.is_empty() and int(operator.station_id) == -1, "destroyed MG releases its reserved operator")
	_check(_station_ammunition_ledger(world) == 1828, "station destruction conserves stock plus fired and destroyed ammunition")
	for i in range(120):
		world.step(DT)
	_check(int(world.stats.ammo_destroyed) == 204 and _station_ammunition_ledger(world) == 1828, "later world steps cannot recount destroyed ammunition")
	print("COMBAT_AMMUNITION map_budget=%d destroyed=%d" % [_station_ammunition_ledger(world), int(world.stats.ammo_destroyed)])


func _weapon_rules(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	var target: Dictionary = State.unit(100, 1, Vector2(10.5, 5.5))
	world.units.append(shooter)
	world.units.append(target)
	shooter.target_id = 100
	shooter.stability = 1.0
	target.job = "treat"
	_tick(world, 134)
	_check(int(world.stats.rifle_shots) == 0 and shooter.weapon_state == "aiming", "normal standing rifle performs a real 2.25 second aim")
	_tick(world, 1)
	_check(int(world.stats.rifle_shots) == 1, "normal rifle fires when aim completes")
	shooter.forced_prone = true
	shooter.posture=2
	shooter.posture_timer=.35
	_tick(world,20)
	_check(int(world.stats.rifle_shots)==1,"actual posture transition interrupts the ongoing burst")
	shooter.posture_timer=0.0
	_tick(world,180)
	_check(int(world.stats.rifle_shots)>1,"forced prone resumes open-ground aiming and shooting after transition")
	var fired: int = int(world.stats.rifle_shots)
	shooter.forced_prone = false
	target.pos = Vector2(40.5, 5.5)
	target.prev_pos = target.pos
	_tick(world, 240)
	_check(int(world.stats.rifle_shots) == fired and int(shooter.target_id) == 100, "out-of-range explicit target remains locked without firing")
	_check(shooter.weapon_state == "blocked" and shooter.status == "指定目标暂不可攻击，守位等待", "out-of-range forced target reports waiting instead of stale firing")
	target.pos = Vector2(10.5, 5.5)
	target.prev_pos = target.pos
	var obstruction: Dictionary = State.building(1000, "wall", Rect2i(6, 5, 1, 1))
	world.buildings.append(obstruction)
	_tick(world, 1)
	_check(int(shooter.target_id) == 100 and shooter.weapon_state == "blocked" and shooter.status == "指定目标暂不可攻击，守位等待" and int(world.stats.rifle_shots) == fired, "temporarily occluded forced target stays locked and reports waiting")
	obstruction.destroyed = true
	_tick(world, 1)
	_check(shooter.weapon_state == "aiming" and String(shooter.status).begins_with("瞄准") and int(shooter.target_id) == 100, "forced target resumes actual aim after obstruction clears")
	var moving = _empty(factory)
	var walker: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	walker.velocity = Vector2.RIGHT
	walker.stability = 0.15
	walker.target_id = 100
	target.pos = Vector2(10.5, 5.5)
	target.prev_pos = target.pos
	moving.units.append(walker)
	moving.units.append(target)
	_tick(moving, 179)
	_check(int(moving.stats.rifle_shots) == 0, "moving rifle still aims instead of instant low-threshold firing")
	_tick(moving, 1)
	_check(int(moving.stats.rifle_shots) == 1, "moving rifle can complete its longer low-precision aim")
	var mg_world = _mortar_world(factory, 1)
	var b: Dictionary = mg_world.buildings[0]
	b.kind = "mg"
	b.loaded = 100
	b.fire_requested = false
	mg_world.units[0].style = 0
	var enemy: Dictionary = State.unit(100, 1, Vector2(20.5, 28.5))
	enemy.job = "treat"
	mg_world.units.append(enemy)
	_tick(mg_world, 30)
	_check(int(mg_world.stats.mg_shots) == 0, "MG respects fixed 120 degree firing arc")
	enemy.pos = Vector2(20.5, 12.5)
	enemy.prev_pos = enemy.pos
	_tick(mg_world, 27)
	_check(int(mg_world.stats.mg_shots) == 1, "station MG aims then fires without intercepting itself")


func _machine_gun_preference(factory: Callable) -> void:
	for invalid in ["dead", "missing", "range", "arc", "wall"]:
		var world = _empty(factory)
		var gun: Dictionary = State.building(1000, "mg", Rect2i(10, 10, 1, 1))
		var operator: Dictionary = State.unit(1, 0, gun.crew_points[0])
		operator.job = "operate"
		operator.stage = "station"
		operator.station_id = int(gun.id)
		operator.stability = 1.0
		operator.style = 0
		gun.crew.append(1)
		var preferred: Dictionary = State.unit(100, 1, Vector2(14.5, 2.5))
		var available: Dictionary = State.unit(101, 1, Vector2(10.5, 3.5))
		preferred.job = "treat"
		available.job = "treat"
		world.units.append(operator)
		world.units.append(preferred)
		world.units.append(available)
		world.buildings.append(gun)
		gun.target_id = int(preferred.id)
		var selected: Dictionary = world.combat_system._choose_target(world, operator, Config.machine_gun(), gun)
		_check(int(selected.get("id", -1)) == int(preferred.id), "MG retains a valid explicit target ahead of nearer enemies")
		match invalid:
			"dead":
				preferred.hp = 0.0
				preferred.dead = true
			"missing": gun.target_id = 9999
			"range": preferred.pos = Vector2(10.5, -25.0)
			"arc": preferred.pos = Vector2(20.5, 10.5)
			"wall": world.buildings.append(State.building(1001, "wall", Rect2i(12, 6, 1, 1)))
		preferred.prev_pos = preferred.pos
		selected = world.combat_system._choose_target(world, operator, Config.machine_gun(), gun)
		if invalid in ["dead", "missing"]:
			_check(int(selected.get("id", -1)) == int(available.id) and int(gun.target_id) == -1, "MG terminal target clears lock and resumes guard")
		else:
			_check(selected.is_empty() and int(gun.target_id) == int(preferred.id), "MG %s target waits without silent retargeting" % invalid)
		_tick(world, 27)
		_check(int(world.stats.mg_shots) == (1 if invalid in ["dead", "missing"] else 0), "MG %s lock follows firing eligibility" % invalid)
		_check(int(operator.station_id) == int(gun.id) and gun.crew == [1], "MG target changes never release its operator")


func _unified_cover_boundaries(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	var target: Dictionary = State.unit(100, 1, Vector2(15.5, 5.5))
	var cover: Dictionary = State.building(1000, "crate", Rect2i(7, 4, 2, 2))
	cover.screening_strength = 2.0
	cover.hp = 100000.0
	world.units.append(shooter)
	world.units.append(target)
	world.buildings.append(cover)
	_close(world.combat_system.cover_probability(cover, 1.0, 0.5), 0.0, "touching shooter has zero cover obstruction")
	_close(world.combat_system.cover_probability(cover, 1.0, 1.5), 0.3, "shooter distance transition is linear")
	_close(world.combat_system.cover_probability(cover, 1.0, 2.5), 0.6, "normal shooter distance restores base cover")
	_close(world.combat_system.cover_probability(cover, 1.0, 100.0), 0.6, "distance never raises cover beyond its base")
	var bullet: Dictionary = world.combat_system.spawn_direct_projectile(world, shooter, target, Config.rifle(), 1.0)
	var oracle := RandomNumberGenerator.new()
	oracle.state = world.rng.state
	oracle.randf()
	for frame in range(60): world.combat_system.advance_projectiles(world, 0.01)
	_check(world.rng.state == oracle.state, "one multi-cell building consumes exactly one cover draw across frames")
	_check(bullet.cover_checked.size() == 1 and Vector2(bullet.start) == shooter.pos, "cover bookkeeping uses building identity and immutable original muzzle")
	# Identical unguided rays use the nearest potential victim, not target_id.
	var selected_seed: int = 0
	for seed_value in range(1, 1000):
		oracle.seed = seed_value
		var roll: float = oracle.randf()
		if roll > 0.62 and roll < 0.74: selected_seed = seed_value; break
	_check(selected_seed > 0, "unguided reference fixture has a discriminating cover roll")
	for posture in [0, 2]:
		var stray = _empty(factory)
		var victim: Dictionary = State.unit(100, 1, Vector2(15.5, 5.5))
		victim.posture = posture
		var obstacle: Dictionary = State.building(1000, "sandbag", Rect2i(7, 5, 1, 1))
		obstacle.screening_strength = 2.0
		stray.units.append(victim)
		stray.buildings.append(obstacle)
		var unguided: Dictionary = stray.combat_system.spawn_direct_projectile(stray, shooter, victim, _fast_rifle(), 1.0)
		unguided.target_id = -1
		stray.rng.seed = selected_seed
		stray.combat_system.advance_projectiles(stray, DT)
		_close(float(victim.hp), 82.0 if posture == 0 else 100.0, "unguided ray uses actual forward posture %d for cover" % posture)
	var wall: Dictionary = State.building(2000, "wall", Rect2i(5, 4, 1, 3))
	wall.height = 0.01
	world.buildings.clear()
	world.buildings.append(wall)
	for posture in [0, 1, 2]:
		target.posture = posture
		_check(not world.combat_system.has_line_of_fire(world, shooter, target), "fixed wall type blocks posture %d irrespective of height" % posture)
		world.combat_system.spawn_direct_projectile(world, shooter, target, _fast_rifle(), 1.0)
		world.combat_system.advance_projectiles(world, DT)
		_close(float(target.hp), 100.0, "fixed wall intercepts direct/stray paths")
	var downed: Dictionary = State.unit(101, 1, Vector2(3.5, 5.5))
	downed.conscious = false
	world.units.clear()
	world.units.append(shooter)
	world.units.append(downed)
	world.buildings.clear()
	_check(world.combat_system._choose_target(world, shooter, Config.rifle()).is_empty(), "automatic fire never selects the only visible unconscious enemy")
	shooter.target_id = int(downed.id)
	_check(world.combat_system._choose_target(world, shooter, Config.rifle()) == downed, "player can explicitly target an unconscious enemy")
	shooter.team = 1
	downed.team = 0
	_check(world.combat_system._choose_target(world, shooter, Config.rifle()).is_empty() and int(shooter.target_id) == -1, "AI discards a newly downed explicit intention between its slower evaluations")


func _weapon_cycles_and_muzzles(factory: Callable) -> void:
	for style in [0, 1, 2]:
		var world = _empty(factory)
		var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
		var target: Dictionary = State.unit(100, 1, Vector2(12.5, 5.5))
		shooter.style = style
		shooter.target_id = int(target.id)
		target.job = "treat"
		target.hp = 100000.0
		target.max_hp = target.hp
		world.units.append(shooter)
		world.units.append(target)
		var shots: Array[float] = []
		for frame in range(600):
			var before: int = int(world.stats.rifle_shots)
			shooter.stability = 1.0
			_tick(world, 1)
			if int(world.stats.rifle_shots) > before:
				shots.append(float(world.time_s))
				for event_index in range(world.events.size() - 1, -1, -1):
					var event: Dictionary = world.events[event_index]
					if event.type != "weapon_fired": continue
					var pose: Dictionary = Pose.aimed_rifle(shooter.pos, target.pos, int(shooter.posture))
					_check(Vector2(event.pos).distance_to(Vector2(pose.muzzle)) < 0.00001 and int(event.holder_id) == int(shooter.id), "shot origin and holder match shared rifle pose")
					break
		_check(shots.size() >= 2, "style %d produces repeated real shots" % style)
		if shots.size() < 2: continue
		_close(shots[0], float(Config.RIFLE_AIM_SECONDS[style]), "style %d first aim duration" % style, DT * 1.1)
		if style == 0:
			_close(shots[1] - shots[0], 0.125, "suppression uses mechanical firing rate after short aim", DT * 1.1)
		elif style == 1:
			_check(shots.size() >= 4, "normal style produces at least two three-round bursts")
			if shots.size() >= 4: _close(shots[3] - shots[0], 3.0, "normal complete round cycle is three seconds", DT * 2.1)
		else:
			_close(shots[1] - shots[0], 4.5, "cautious single-shot cycle trades time for precision", DT * 2.1)
	# A visual muzzle offset cannot spawn a bullet through an adjacent wall.
	var blocked = _empty(factory)
	var shooter: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	var target: Dictionary = State.unit(100, 1, Vector2(2.5, 1.5))
	blocked.buildings.append(State.building(1000, "wall", Rect2i(2, 4, 1, 1)))
	var pose: Dictionary = Pose.aimed_rifle(shooter.pos, target.pos, 0)
	var result: Dictionary = blocked.combat_system.spawn_direct_projectile(blocked, shooter, target, Config.rifle(), 1.0, pose.muzzle)
	_check(result.is_empty() and blocked.projectiles.is_empty() and blocked.events.is_empty(), "barrel crossing a wall cannot bypass it with a muzzle spawn offset")
	blocked.units.append(shooter)
	blocked.units.append(target)
	shooter.target_id = int(target.id)
	target.job = "treat"
	_tick(blocked, 20)
	_check(int(shooter.loaded) == 30 and int(blocked.stats.rifle_shots) == 0, "blocked muzzle cannot consume ammunition or create shots")
	var turning = _empty(factory)
	var tracker: Dictionary = State.unit(1, 0, Vector2(2.5, 5.5))
	var runner: Dictionary = State.unit(100, 1, Vector2(12.5, 5.5))
	tracker.target_id = int(runner.id)
	runner.job = "treat"
	turning.units.append(tracker)
	turning.units.append(runner)
	_tick(turning, 90)
	_check(float(tracker.aim_fraction) > 0.6, "aim accumulates before a large same-target turn")
	runner.pos = Vector2(-7.5, 5.5)
	runner.prev_pos = runner.pos
	_tick(turning, 1)
	_check(float(tracker.aim_fraction) < 0.1 and int(turning.stats.rifle_shots) == 0, "tracking a target behind the shooter loses aim progress instead of instantly swiveling into a shot")
	print("COMBAT_V2_CYCLES normal=3sec cautious=4.5sec muzzle_contract=true")


func _mortar_unit_target(factory: Callable) -> void:
	var world = _mortar_world(factory, 2)
	var mortar: Dictionary = world.buildings[0]
	mortar.fire_requested = false
	var target: Dictionary = State.unit(100, 1, Vector2(20.5, 8.5))
	target.job = "treat"
	world.units.append(target)
	var valid: Dictionary = world.combat_system.validate_station_attack(world, int(mortar.id), int(target.id))
	_check(bool(valid.ok) and not bool(mortar.fire_requested), "station target validation is pure")
	_check(bool(world.combat_system.request_station_attack(world, int(mortar.id), int(target.id)).ok), "mortar accepts an enemy unit target without releasing crew")
	_tick(world, 479)
	_check(int(world.stats.mortar_shots) == 0 and int(mortar.target_id) == int(target.id), "unit-target mortar preserves complete crew and aim duration")
	target.pos = Vector2(23.5, 8.5)
	target.prev_pos = target.pos
	_tick(world, 1)
	_check(int(world.stats.mortar_shots) == 1 and not bool(mortar.fire_requested), "unit-target command fires exactly one shell")
	if world.projectiles.is_empty(): return
	var shell: Dictionary = world.projectiles[0]
	var impact: Vector2 = shell.impact
	_check(impact.distance_to(target.pos) <= 1.0 + 0.001, "mortar samples the unit position at actual launch")
	var pose: Dictionary = Pose.station(mortar.pos, float(mortar.weapon_facing), "mortar")
	_check(Vector2(shell.start).distance_to(Vector2(pose.muzzle)) < 0.00001, "mortar starts from shared barrel muzzle")
	target.pos = Vector2(35.5, 8.5)
	target.prev_pos = target.pos
	_tick(world, 60)
	_check(Vector2(shell.impact) == impact and int(world.stats.mortar_shots) == 1, "airborne mortar never tracks and does not repeat a one-shot unit order")
	_check(mortar.crew == [1, 2] and int(world.units[0].station_id) == int(mortar.id), "unit-target mortar keeps both operators assigned")


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
	_check(bool(world.submit([1], "move", {"position": Vector2(26.5, 35.5)}).ok), "moving during personal reload is legal")
	world.start_battle()
	world.step()
	_check(int(u.reload_reserved)>0 and float(u.reload_progress)<=1.0, "move command pauses the incomplete reload stage and preserves reservation")
	for i in range(120):
		world.step()
	_check(String(u.job) == "idle" and int(u.reload_reserved)>0, "arrival preserves and resumes an ongoing personal reload")
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
		reference.combat_system.use_ray_cache = false
		reference.combat_system.use_ray_building_index = false
		reference.combat_system.use_geometry_cache = false
		reference.combat_system.use_low_muzzle_index = false
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
	worlds[1].combat_system.use_ray_cache = false
	worlds[1].combat_system.use_ray_building_index = false
	worlds[1].combat_system.use_geometry_cache = false
	worlds[1].combat_system.use_low_muzzle_index = false
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


func _v3_cover_intervals(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1,0,Vector2(2.5,5.5))
	var target: Dictionary = State.unit(100,1,Vector2(14.5,5.5))
	world.units.append(shooter); world.units.append(target)
	for x in range(6,10): world.buildings.append(State.building(1000+x,"sandbag",Rect2i(x,5,1,1)))
	var split: Dictionary = world.cover_for(target,shooter.pos)
	_check(split.obstacles.size()==1 and split.obstacles[0].members.size()==4,"adjacent identical cover cells merge into one ray interval")
	var chance: float = float(split.chance)
	world.buildings.clear(); world.buildings.append(State.building(1000,"sandbag",Rect2i(6,5,4,1)))
	_close(float(world.cover_for(target,shooter.pos).chance),chance,"one multi-cell entity equals four identical adjacent single-cell entities")
	world.buildings.clear()
	world.buildings.append(State.building(1000,"sandbag",Rect2i(6,5,1,1)))
	world.buildings.append(State.building(1001,"sandbag",Rect2i(10,5,1,1)))
	world.buildings.append(State.building(1002,"sandbag",Rect2i(6,3,5,1)))
	_check(world.cover_for(target,shooter.pos).obstacles.size()==2,"U-shaped connectivity outside the ray never merges separated crossings")
	world.buildings[1].rect=Rect2i(7,5,1,1); world.buildings[1].height=.9
	_check(world.cover_for(target,shooter.pos).obstacles.size()==2,"adjacent cover with a different height keeps independent trials")
	world.buildings.clear(); world.buildings.append(State.building(1000,"sandbag",Rect2i(6,5,1,1)))
	var graze: Array = world.combat_system._cover_segments(world,Vector2(5,6),Vector2(7,4))
	_check(graze.is_empty(),"zero-length corner contact is not a cover crossing")
	world.buildings.clear()
	for x in range(6,10):
		var bag: Dictionary = State.building(1000+x,"sandbag",Rect2i(x,5,1,1))
		bag.screening_strength=0.0; world.buildings.append(bag)
	var weapon: Dictionary = Config.rifle(); weapon.speed=10.0
	var bullet: Dictionary = world.combat_system.spawn_direct_projectile(world,shooter,target,weapon,1.0)
	for frame in range(37): world.combat_system.advance_projectiles(world,.01)
	_check(bullet.cover_intervals.size()==1,"slow projectile records the full merged interval at first entrance")
	world.buildings[1].destroyed=true
	for frame in range(40): world.combat_system.advance_projectiles(world,.01)
	_check(bullet.cover_intervals.size()==1,"destroying the middle after entry does not reroll the remaining previously tested interval")
	world.projectiles.clear()
	for building in world.buildings: building.destroyed=false; building.screening_strength=1000000.0
	bullet=world.combat_system.spawn_direct_projectile(world,shooter,target,_fast_rifle(),1.0)
	for building in world.buildings: building.destroyed=true
	world.combat_system.advance_projectiles(world,DT)
	_check(float(target.hp)<100.0 and bullet.cover_intervals.is_empty(),"a barrier destroyed before the projectile arrives cannot intercept it")
	print("COMBAT_V3_COVER merged_intervals=true gaps=true corner_graze=true cross_frame_destruction=true")


func _v3_body_exemptions(factory: Callable) -> void:
	for scenario in ["friend","enemy","target","far_friend","late_entry","left_local","diagonal","three_in_line","prefix"]:
		var world = _empty(factory)
		var shooter: Dictionary = State.unit(1,0,Vector2(2.5,5.5))
		var target: Dictionary = State.unit(100,1,Vector2(10.5,5.5))
		var body: Dictionary = State.unit(2,0,Vector2(3.5,5.5))
		world.units.append(shooter); world.units.append(target); world.units.append(body)
		if scenario in ["enemy","prefix"]: body.team=1
		if scenario=="target": target.pos=body.pos; target.prev_pos=target.pos; body.pos=Vector2(3.5,7.5); body.prev_pos=body.pos
		if scenario=="far_friend": body.pos=Vector2(4.5,5.5); body.prev_pos=body.pos
		if scenario=="late_entry": body.pos=Vector2(3.5,8.5); body.prev_pos=body.pos
		if scenario=="diagonal": body.pos=Vector2(3.5,6.5); body.prev_pos=body.pos; target.pos=Vector2(10.5,13.5); target.prev_pos=target.pos
		var next: Dictionary = {}
		if scenario=="three_in_line": next=State.unit(3,0,Vector2(4.5,5.5)); world.units.append(next)
		var muzzle: Vector2 = Vector2.INF
		if scenario=="prefix": body.pos=Vector2(3.0,5.5); body.prev_pos=body.pos; muzzle=Vector2(3.3,5.5)
		var bullet: Dictionary = world.combat_system.spawn_direct_projectile(world,shooter,target,_fast_rifle(),1.0,muzzle)
		if scenario=="late_entry": body.pos=Vector2(3.5,5.5); body.prev_pos=body.pos
		if scenario=="left_local": body.pos=Vector2(4.5,5.5); body.prev_pos=body.pos
		world.combat_system.advance_projectiles(world,DT)
		if scenario in ["friend","diagonal","target"]:
			_check(float(target.hp)<100.0 and float(body.hp)==100.0,"body exception "+scenario+" damages only original target")
		elif scenario=="three_in_line":
			_check(float(target.hp)==100.0 and float(body.hp)==100.0 and float(next.hp)<100.0,"local exception does not chain down a three-person line")
		else:
			_check(float(target.hp)==100.0 and float(body.hp)<100.0,"intermediate body remains a blocker: "+scenario)
		_check(world.projectiles.is_empty(),"one ordinary bullet cannot pass through its first actual victim: "+scenario)
	# Consciousness and carrying never make a body intangible.
	var stacked = _empty(factory)
	var shooter: Dictionary = State.unit(1,0,Vector2(2.5,5.5))
	var target: Dictionary = State.unit(100,1,Vector2(10.5,5.5))
	var carrier: Dictionary = State.unit(2,0,Vector2(6.5,5.5))
	var casualty: Dictionary = State.unit(3,0,carrier.pos)
	casualty.conscious=false; casualty.carrier_id=2; carrier.rescued_id=3
	# Equal radii create an exact tie, then the lower entity ID wins.
	carrier.posture=2
	stacked.units.append(shooter); stacked.units.append(target); stacked.units.append(carrier); stacked.units.append(casualty)
	stacked.combat_system.spawn_direct_projectile(stacked,shooter,target,_fast_rifle(),1.0)
	stacked.combat_system.advance_projectiles(stacked,DT)
	_check(float(carrier.hp)<100.0 and float(casualty.hp)==100.0 and float(target.hp)==100.0,"overlapping carried bodies tie by ID and only one receives damage")
	print("COMBAT_V3_BODIES local_friend_only=true original_target=true late_entry=true prefix=true carried_tie=true")


func _v3_query_and_styles(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1,0,Vector2(2.5,5.5))
	var target: Dictionary = State.unit(100,1,Vector2(16.5,5.5))
	shooter.stability=1.0
	world.units.append(shooter); world.units.append(target)
	world.buildings.append(State.building(1000,"sandbag",Rect2i(9,5,3,1)))
	world.buildings.append(State.building(1001,"sandbag",Rect2i(14,5,1,1)))
	var before: int = world.rng.state
	var units_before: Array = world.units.duplicate(true)
	var buildings_before: Array = world.buildings.duplicate(true)
	var stats_before: Dictionary = world.stats.duplicate(true)
	var events_before: Array = world.events.duplicate(true)
	var expected: Dictionary = world.combat_system.query_shot(world,1,100)
	for i in range(50): world.combat_system.query_shot(world,1,100,i%3)
	_check(world.rng.state==before and world.units==units_before and world.buildings==buildings_before and world.stats==stats_before and world.events==events_before,"repeated shot queries are pure and do not consume battle RNG")
	_check(bool(expected.ok) and expected.kind=="direct" and expected.segments.size()==2,"final probability query reports two physically separated cover intervals")
	var weapon: Dictionary = _fast_rifle()
	var pose: Dictionary = Pose.aimed_rifle(shooter.pos,target.pos,0)
	var hits: int = 0
	for i in range(5000):
		target.hp=100.0; target.suppression=0.0; target.bleed_rate=0.0
		for building in world.buildings: building.hp=1000000.0
		world.combat_system.spawn_direct_projectile(world,shooter,target,weapon,-1.0,pose.muzzle)
		world.combat_system.advance_projectiles(world,DT)
		if float(target.hp)<100.0: hits+=1
	_close(float(hits)/5000.0,float(expected.probability),"5000 real static projectiles agree with final shot preview",.03)
	var contact_world = _empty(factory)
	var contact_shooter: Dictionary = State.unit(1,0,Vector2(2.5,5.5))
	var contact_target: Dictionary = State.unit(100,1,Vector2(Pose.rifle(contact_shooter.pos,-PI/2.0).muzzle))
	contact_world.units.append(contact_shooter); contact_world.units.append(contact_target)
	var contact_preview: Dictionary = contact_world.combat_system.query_shot(contact_world,1,100)
	_close(float(contact_preview.probability),1.0,"original target touching muzzle/prefix cannot be incorrectly exempted or counted as a geometric miss")
	var contact_pose: Dictionary = Pose.aimed_rifle(contact_shooter.pos,contact_target.pos,0)
	contact_world.combat_system.spawn_direct_projectile(contact_world,contact_shooter,contact_target,_fast_rifle(),0.0,contact_pose.muzzle)
	contact_world.combat_system.advance_projectiles(contact_world,DT)
	_check(float(contact_target.hp)<100.0,"even an inaccurate round contacts an original target already covering the muzzle or prefix")
	world.buildings.clear(); shooter.posture=2
	_check(bool(world.combat_system.can_fire_pose(world,shooter,target).ok),"open-ground prone fire is geometrically legal")
	world.buildings.append(State.building(1002,"sandbag",Rect2i(3,5,1,1)))
	_check(not bool(world.combat_system.can_fire_pose(world,shooter,target).ok),"a nearby sandbag above a prone muzzle prevents outgoing fire")
	shooter.posture=0
	_check(bool(world.combat_system.can_fire_pose(world,shooter,target).ok),"standing gun barrel can clear the same low cover")
	shooter.loaded=0; shooter.hold_fire=true
	var not_ready: Dictionary = world.combat_system.query_shot(world,1,100)
	_check(not bool(not_ready.ready) and float(not_ready.probability)>0.0,"not-ready state remains separate from computed firing accuracy")
	world.buildings.clear()
	var rates: Array[float] = []
	for style in range(3): shooter.style=style; rates.append(world.combat_system.hit_probability(shooter,target,Config.rifle()))
	_check(rates[0]<rates[1]*.6 and rates[2]>rates[1]*1.3,"suppression accuracy is distinctly below normal and cautious distinctly above")
	_close(world.combat_system.mortar_coverage_probability(2.5,4.0,0.0),1.0,"current mortar scatter disk lies fully inside explosion range")
	_close(world.combat_system.mortar_coverage_probability(4.0,2.0,0.0),.25,"concentric disk coverage uses area ratio")
	_close(world.combat_system.mortar_coverage_probability(2.0,2.0,4.0),0.0,"disjoint mortar blast disks have zero coverage")
	print("COMBAT_V3_PREVIEW samples=5000 expected=%.5f observed=%.5f rng_pure=true style_probabilities=%s" % [float(expected.probability),float(hits)/5000.0,str(rates)])


func _v3_fire_control_and_preload(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1,0,Vector2(2.5,5.5))
	var target: Dictionary = State.unit(100,1,Vector2(8.5,5.5))
	var fallback: Dictionary = State.unit(101,1,Vector2(9.5,5.5))
	shooter.loaded=10; shooter.hold_fire=true
	target.job="treat"; fallback.job="treat"
	world.units.append(shooter); world.units.append(target); world.units.append(fallback)
	_tick(world,90)
	_check(int(shooter.reload_reserved)==0,"partial magazine waits a full idle delay")
	_tick(world,1)
	_check(int(shooter.reload_reserved)==20,"hold-fire permits idle magazine top-up even when enemies are visible")
	_tick(world,180)
	_check(int(shooter.loaded)==30 and int(shooter.reserve)==130 and int(world.stats.rifle_shots)==0,"idle top-up conserves ammunition and never fires while held")
	shooter.target_id=100; target.pos=Vector2(50,50); target.prev_pos=target.pos
	shooter.target_policy="strict"
	_check(world.combat_system._choose_target(world,shooter,Config.rifle()).is_empty(),"strict invalid preferred target waits")
	shooter.target_policy="priority"
	_check(int(world.combat_system._choose_target(world,shooter,Config.rifle()).get("id",-1))==101 and int(shooter.target_id)==100,"priority invalid preferred target temporarily attacks a legal fallback without losing intent")
	target.dead=true
	world.combat_system._choose_target(world,shooter,Config.rifle())
	_check(int(shooter.target_id)==-1,"terminal priority target clears its intention")
	var mortar_world = _mortar_world(factory,1)
	var mortar: Dictionary = mortar_world.buildings[0]
	mortar.fire_requested=false
	_tick(mortar_world,600)
	_check(int(mortar.loaded)==1 and int(mortar.ammo)==3 and int(mortar_world.stats.mortar_shots)==0,"idle mortar preloads one real shell without a fire command")
	mortar.fire_requested=true; mortar.hold_fire=true
	_tick(mortar_world,300)
	_check(int(mortar.loaded)==1 and bool(mortar.fire_requested) and int(mortar_world.stats.mortar_shots)==0,"mortar hold-fire suspends but preserves its bombardment command")
	mortar.hold_fire=false
	_tick(mortar_world,240)
	_check(int(mortar_world.stats.mortar_shots)==1 and not bool(mortar.fire_requested),"resuming mortar fires exactly one previously requested shell")
	var coverage_world = _mortar_world(factory,1)
	var artillery: Dictionary = coverage_world.buildings[0]
	coverage_world.units[0].stability=0.0
	artillery["mortar_gunner"]=int(coverage_world.units[0].id)
	var requested: Vector2 = artillery.fire_point
	artillery["mortar_aim_point"]=requested
	var subject: Vector2 = requested+Vector2(3.0,0)
	var covered: int = 0
	for i in range(5000):
		artillery.loaded=1; artillery.fire_requested=true; artillery.aim_progress=4.0-DT
		coverage_world.combat_system._ensure_weapon(artillery)
		coverage_world.combat_system._update_mortar(coverage_world,artillery,DT)
		_check(coverage_world.projectiles.size()==1,"mortar coverage sample launches one actual shell")
		if not coverage_world.projectiles.is_empty() and Vector2(coverage_world.projectiles[0].impact).distance_to(subject)<4.0: covered+=1
		coverage_world.projectiles.clear(); coverage_world.events.clear()
	var calculated: float = coverage_world.combat_system.mortar_coverage_probability(2.5,4.0,3.0)
	_close(float(covered)/5000.0,calculated,"5000 actual mortar shell endpoints match blast-coverage disk intersection",.03)
	print("COMBAT_V3_MORTAR samples=5000 expected=%.5f observed=%.5f" % [calculated,float(covered)/5000.0])
	print("COMBAT_V3_FIRE_CONTROL hold=true strict_priority=true idle_topup=true mortar_preload=true")


# A labelled isolated shooting range, never a victory fixture. Weapon stock is
# the normal finite 180 rounds. Only the stationary training dummy has extra HP.
func _v3_style_range_metrics(factory: Callable) -> void:
	for style in range(3):
		var world = _empty(factory)
		var shooter: Dictionary = State.unit(1,0,Vector2(8.5,10.5))
		var dummy: Dictionary = State.unit(100,1,Vector2(22.5,10.5))
		shooter.posture_mode=0; shooter.style=style; shooter.target_id=100; shooter.stability=1.0
		dummy.posture_mode=0; dummy.hold_fire=true; dummy.hp=100000.0; dummy.max_hp=100000.0
		world.units.append(shooter); world.units.append(dummy)
		world.unit_system.setup(world); dummy.ai_next=99999.0
		var hits: int = 0
		var pressure: float = 0.0
		for frame in range(3600):
			world.time_s+=DT; world.step_index+=1
			dummy.suppression=0.0; dummy.pressure_level=0; dummy.cower=false
			world.unit_system.update(world,DT)
			world.combat_system.update(world,DT)
			for event in world.events:
				if String(event.type)=="damage" and int(event.get("entity_id",-1))==100: hits+=1
			pressure+=float(dummy.suppression)
			world.events.clear()
		var shots: int = int(world.stats.rifle_shots)
		_check(int(shooter.loaded)+int(shooter.reserve)+shots==180,"style range preserves default ammunition stock")
		print("COMBAT_V3_STYLE_RANGE style=%d seconds=60 shots=%d hits=%d hit_per_shot=%.4f hits_per_minute=%d ammo_used=%d pressure=%.1f fixture=stationary_training_dummy" % [style,shots,hits,float(hits)/maxi(1,shots),hits,shots,pressure])



func _v3_query_replay_equivalence(factory: Callable) -> void:
	var with_preview = _empty(factory)
	var without_preview = _empty(factory)
	for world in [with_preview,without_preview]:
		var shooter: Dictionary = State.unit(1,0,Vector2(2.5,5.5))
		var target: Dictionary = State.unit(100,1,Vector2(16.5,5.5))
		shooter.target_id=100; shooter.stability=1.0
		target.job="treat"; target.hp=1000.0; target.max_hp=1000.0
		world.units.append(shooter); world.units.append(target)
		world.units.append(State.unit(2,0,Vector2(3.5,5.5)))
		world.units[2].hold_fire=true
		world.buildings.append(State.building(1000,"sandbag",Rect2i(8,5,2,1)))
	for frame in range(360):
		for n in range(2): with_preview.combat_system.query_shot(with_preview,1,100,n)
		_tick(with_preview,1); _tick(without_preview,1)
		for field in ["units","buildings","projectiles","events","stats"]:
			if with_preview.get(field)!=without_preview.get(field):
				_check(false,"hover/Alt query changes replay field %s at step %d" % [field,frame]); return
		if with_preview.rng.state!=without_preview.rng.state:
			_check(false,"hover/Alt query changes replay RNG at step %d" % frame); return
	print("COMBAT_V3_QUERY_REPLAY steps=360 with_hover_and_alt_equals_no_preview=true")


func _v3_wall_corner_consistency(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1,0,Vector2(2.5,2.5))
	var corner: Vector2 = Vector2(4,4)
	var initial: Dictionary = Pose.aimed_rifle(shooter.pos,corner,0)
	var target: Dictionary = State.unit(100,1,corner+Vector2.from_angle(float(initial.angle))*4.0)
	var wall: Dictionary = State.building(1000,"wall",Rect2i(4,3,1,1))
	world.units.assign([shooter,target]); world.buildings.append(wall)
	var pose: Dictionary = Pose.aimed_rifle(shooter.pos,target.pos,0)
	var interval: Vector2 = world.combat_system._segment_rect_interval(pose.muzzle,target.pos,Rect2(wall.rect))
	_check(not world.combat_system._positive_crossing(pose.muzzle,target.pos,interval),"reported exact wall-corner graze has no positive crossing")
	_check(world.combat_system.can_fire_pose(world,shooter,target).ok,"exact corner graze remains a legal firing pose")
	_check(world.combat_system.query_shot(world,1,100).ok,"shot preview does not treat the corner graze as a blocking wall")
	world.combat_system.spawn_direct_projectile(world,shooter,target,_fast_rifle(),1.0,pose.muzzle)
	world.combat_system.advance_projectiles(world,DT)
	_check(float(target.hp)<100.0 and float(wall.hp)==float(wall.max_hp),"real projectile passes the same zero-length corner contact")
	# Move slightly into the wall: this is a genuine crossing, not a graze.
	target.hp=100.0; target.pos.y-=.03; target.prev_pos=target.pos
	pose=Pose.aimed_rifle(shooter.pos,target.pos,0)
	_check(not world.combat_system.can_fire_pose(world,shooter,target).ok,"positive wall penetration still blocks the firing query")
	world.combat_system.spawn_direct_projectile(world,shooter,target,_fast_rifle(),1.0,pose.muzzle)
	world.combat_system.advance_projectiles(world,DT)
	_check(float(target.hp)==100.0 and float(wall.hp)<float(wall.max_hp),"real projectile and query agree on a genuine thin wall crossing")
	_check(world.combat_system._muzzle_clear(world,Vector2(3,3),Vector2(5,5)),"barrel touching only a wall corner is clear")
	_check(not world.combat_system._muzzle_clear(world,Vector2(4.5,3.5),Vector2(4.5,3.5)),"zero-length barrel strictly inside a wall remains blocked")
	_check(not world.combat_system.has_line_of_fire(world,{"pos":Vector2(4.5,3.5)},target),"muzzle truly inside a wall cannot aim outside it")
	print("COMBAT_V3_WALL_CORNER query_matches_real=true thin_crossing_blocks=true inside_wall_blocks=true")


func _v3_ray_cache_lifecycle(factory: Callable) -> void:
	var world = _empty(factory)
	var shooter: Dictionary = State.unit(1,0,Vector2(2.5,5.5))
	var target: Dictionary = State.unit(100,1,Vector2(14.5,5.5))
	world.units.assign([shooter,target])
	var barrier: Dictionary = State.building(1000,"sandbag",Rect2i(8,5,2,1))
	world.buildings.append(barrier)
	var weapon: Dictionary = Config.rifle(); weapon.speed=1.0
	var projectile: Dictionary = world.combat_system.spawn_direct_projectile(world,shooter,target,weapon,1.0)
	world.combat_system.advance_projectiles(world,DT)
	var revision: int = world.combat_system._static_revision
	var hits: int = world.combat_system._ray_cache_hits
	barrier.hp-=1.0
	world.combat_system.advance_projectiles(world,DT)
	_check(world.combat_system._static_revision==revision and world.combat_system._ray_cache_hits>hits,"nonterminal building HP damage reuses cached static rays")
	barrier.height=.9
	world.combat_system.advance_projectiles(world,DT)
	_check(world.combat_system._static_revision>revision,"height changes invalidate static interval and firing-geometry caches")
	world.projectiles.clear(); barrier.height=.8; barrier.hp=1.0
	weapon=_fast_rifle()
	world.combat_system.spawn_direct_projectile(world,shooter,target,weapon,1.0)
	world.combat_system.spawn_direct_projectile(world,shooter,target,weapon,1.0)
	barrier.screening_strength=1000000.0
	# Seed the static cache for both bullets, then a real first impact destroys
	# the barrier before the following bullet in this same advance pass.
	world.combat_system._prepare_queries(world)
	for bullet in world.projectiles:
		world.combat_system._projectile_cover_segments(world,bullet,bullet.start,Vector2(bullet.start)+Vector2(bullet.dir)*float(bullet.remaining))
	world.rng.seed=104729
	world.combat_system.advance_projectiles(world,DT)
	_check(float(barrier.hp)<=0.0 and float(target.hp)<100.0,"same-pass destruction invalidates previously primed following projectile rays")
	var other = _empty(factory)
	other.combat_system=world.combat_system
	other.units.assign([State.unit(1,0,shooter.pos),State.unit(100,1,target.pos)])
	other.buildings.append(State.building(1000,"wall",Rect2i(8,5,1,1)))
	other.combat_system.spawn_direct_projectile(other,other.units[0],other.units[1],_fast_rifle(),1.0)
	other.combat_system.advance_projectiles(other,DT)
	_check(float(other.units[1].hp)==100.0,"reusing a Combat instance with another World never reuses old building dictionaries")
	other.reset(); other.next_wave=3
	other.start_battle(); other.step()
	_check(other.combat_system._static_world_id==int(other.get_instance_id()),"World.reset rebuilds cache topology without storing it in replay state")
	print("COMBAT_V3_CACHE_LIFECYCLE hp_nonterminal_reuses=true attributes_invalidate=true same_pass_death=true world_reset=true")


func _v3_cover_query_context(factory: Callable) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 639171
	var count: int = 0
	for scene in range(8):
		var world = _equivalence_scene(factory,8210+scene)
		var context: Dictionary = world.combat_system.cover_query_context(world)
		for i in range(100):
			var u: Dictionary = State.unit(79,0,Vector2(random.randf_range(-6,25),random.randf_range(-6,25)))
			u.posture = i%3
			u.cower = i%11==0
			var source := Vector2(random.randf_range(-6,25),random.randf_range(-6,25))
			var expected: Dictionary = world.combat_system.cover_for(world,u,source)
			var actual: Dictionary = world.combat_system.cover_for_context(world,u,source,context)
			_check(actual==expected,"Scoped cover context returns identical full result scene %d ray %d" % [scene,i])
			var height: float = random.randf_range(.2,1.9)
			world.combat_system.use_low_muzzle_index = false
			var old_clear: bool = world.combat_system._low_muzzle_clear(world,source,Vector2(u.pos),height,-1,int(u.id))
			world.combat_system.use_low_muzzle_index = true
			world.combat_system._prepare_queries(world)
			var new_clear: bool = world.combat_system._low_muzzle_clear(world,source,Vector2(u.pos),height,-1,int(u.id))
			world.combat_system._queries_ready = false
			_check(old_clear==new_clear,"Nearby muzzle query matches merged full ray scene %d ray %d" % [scene,i])
			count+=1
	print("COMBAT_V3_COVER_CONTEXT rays=%d exact_full_result=true low_muzzle_reference=true" % count)
