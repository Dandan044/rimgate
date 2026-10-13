extends RefCounted

const Presentation = preload("res://scripts/ui/presentation_state.gd")
const State = preload("res://scripts/sim/state.gd")
const Config = preload("res://scripts/sim/battle_config.gd")
const Weapon = preload("res://scripts/sim/weapon_pose.gd")
const PawnArt = preload("res://scripts/ui/pawn_art.gd")
const EnvironmentArt = preload("res://scripts/ui/environment_art.gd")

func run(make_world: Callable) -> Array[String]:
	var failures: Array[String] = []
	var world = make_world.call()
	var presentation = Presentation.new()
	presentation.reset(world)
	var unit: Dictionary = world.entity(1)
	var start: Vector2 = unit.pos
	world.start_battle()
	world.submit([1], "move", {"position": start + Vector2(3, 0)})
	presentation.set_running(true)
	world.step()
	presentation.capture(world)
	var end: Vector2 = unit.pos
	var rng_before: int = world.rng.state
	var time_before: float = world.time_s
	presentation.update_fraction(0.25)
	var early: Vector2 = presentation.unit_position(unit)
	presentation.update_fraction(0.75)
	var late: Vector2 = presentation.unit_position(unit)
	if not (early.x > start.x and early.x < late.x and late.x < end.x):
		failures.append("Display frames must progress between actual simulation positions")
	if world.rng.state != rng_before or world.time_s != time_before or unit.pos != end:
		failures.append("Drawing samples must not modify battle state or RNG")
	presentation.set_running(false)
	var paused_position: Vector2 = presentation.unit_position(unit)
	for fraction in [0.0, 0.2, 0.9, 1.0]:
		presentation.update_fraction(fraction)
		if presentation.unit_position(unit) != paused_position:
			failures.append("Paused world must stay at its last displayed position")
	presentation.set_running(true)
	if presentation.unit_position(unit) != end:
		failures.append("Resuming must not replay stale movement history")
	unit.pos += Vector2(10, 0)
	presentation.capture(world)
	presentation.update_fraction(0.5)
	if presentation.unit_position(unit) != unit.pos:
		failures.append("Teleport must reset display history")
	unit.carrier_id = 2
	unit.pos += Vector2(0.5, 0)
	presentation.capture(world)
	if presentation.unit_position(unit) != unit.pos:
		failures.append("Pickup and drop must reset display history")
	world.reset()
	presentation.reset(world)
	if presentation.unit_position(world.entity(1)) != world.entity(1).pos:
		failures.append("Restart must discard positions from previous battle")
	var projectile := {"id": 9000, "pos": Vector2(3, 2), "prev_pos": Vector2(2, 2), "age": 0.2}
	world.projectiles.append(projectile)
	presentation.set_running(true)
	presentation.capture(world)
	presentation.update_fraction(0.5)
	if not presentation.projectile_position(projectile).is_equal_approx(Vector2(2.5, 2)):
		failures.append("New projectile must interpolate from its actual swept origin")
	world.projectiles.clear()
	presentation.capture(world)
	presentation.capture(world)
	if not presentation.current_projectiles.is_empty() or not presentation.previous_projectiles.is_empty():
		failures.append("Expired projectile history must be released")
	_terminal_segment(make_world, failures)
	_explosion_display(make_world, failures)
	_display_rates(make_world, failures)
	_weapon_alignment(make_world, failures)
	_modular_art(make_world, failures)
	_adjacency_cache(make_world, failures)
	return failures

func _modular_art(make_world: Callable, failures: Array[String]) -> void:
	var world=make_world.call()
	var art=PawnArt.new();art.setup()
	if not art.ready:failures.append("V3 modular pawn component assets must all load")
	if art.features.size()!=6 or art.enemy_outfits.size()!=3:failures.append("V3 requires six facial states and three fixed masked enemy types")
	var unit: Dictionary=world.entity(1)
	var rng_state: int=world.rng.state
	var profile:=art.profile(unit)
	for key in ["face","features","hair","body"]:
		var changed:=unit.duplicate(true)
		var expected:=profile.duplicate(true)
		expected[key]=posmod(int(profile[key])+1,3 if key in ["face","body"] else 6)
		changed.appearance_profile={"face":profile.face,"features":profile.features,"hair":profile.hair,"body":profile.body}
		changed.appearance_profile[key]=expected[key]
		var result:=art.profile(changed)
		for stable_key in ["face","features","hair","body","top","legs","vest","helmet"]:
			if result[stable_key]!=expected[stable_key]:failures.append("Changing %s must not replace independent %s" %[key,stable_key])
	if is_equal_approx(art._rig_width(0,.1)/art._rig_width(1,.1),art._rig_width(0,.6)/art._rig_width(1,.6)):
		failures.append("Body rigs must change shoulder/waist contours locally, rather than uniform x stretching")
	unit.weapon_state="aiming"
	if art.expression_for(unit,2.0)!="aim":failures.append("Aiming must drive the focused facial state")
	unit.cower=true
	if art.expression_for(unit,2.0)!="panic":failures.append("Cowering must take facial priority over aiming")
	if art.expression_for(unit,2.0,false,true)!="hurt" or art.expression_for(unit,2.0,true,true)!="closed":
		failures.append("Injury and unconscious facial state priorities must remain deterministic")
	unit.cower=false;unit.weapon_state="idle";unit.pressure_level=0
	var paused_expression:=art.expression_for(unit,3.1)
	for repeat in range(30):
		if art.expression_for(unit,3.1)!=paused_expression:failures.append("Frozen visual time must freeze natural blinking")
	for facing in [PI*.5,0.0,-PI*.5,PI]:
		if art.direction_for(facing) not in [0,1,2,3]:failures.append("All cardinal directions need an explicit sprite view")
	if world.rng.state!=rng_state:failures.append("Appearance combinations, blinking and rig queries must not consume battle randomness")

func _adjacency_cache(make_world: Callable, failures: Array[String]) -> void:
	var world=make_world.call()
	var art=EnvironmentArt.new();art.setup()
	if not art.ready:failures.append("Approved terrain/building art resources must load before gameplay")
	for kind in ["sandbag","wall"]:
		var texture: Texture2D=art.textures[kind+"_connections"]
		if texture.get_size()!=Vector2(512,1536):failures.append("%s must bake all 16 neighbor masks and three stable variants" %kind)
		for mask in range(16):
			world.buildings.clear();world.buildings.append(State.building(1000,kind,Rect2i(8,8,1,1)))
			for i in range(4):
				if mask&(1<<i):world.buildings.append(State.building(1001+i,kind,Rect2i(Vector2i(8,8)+art.DIRECTIONS[i],Vector2i.ONE)))
			art.rebuild(world)
			if art.mask_at(Vector2i(8,8))!=mask:failures.append("%s four-way mask %d is not represented" %[kind,mask])
	world.buildings.clear()
	for x in range(5):world.buildings.append(State.building(1000+x,"sandbag",Rect2i(8+x,8,1,1)))
	art.rebuild(world)
	var before_hp: float=float(world.buildings[0].hp)
	world.buildings[2].destroyed=true
	art.destroyed(world,1002)
	if art.mask_at(Vector2i(9,8))!=8 or art.mask_at(Vector2i(11,8))!=2:failures.append("Destroyed middle cell must open both adjacent visual ends")
	if art.last_updated_cells.size()!=5:failures.append("One-cell destruction must only invalidate the cell plus four neighbors")
	if world.buildings[0].hp!=before_hp or world.buildings.size()!=5:failures.append("Visual connections must preserve separate real building hit points/entities")

func _weapon_alignment(make_world: Callable, failures: Array[String]) -> void:
	var world = make_world.call()
	var presentation = Presentation.new()
	var unit: Dictionary = world.entity(1)
	unit["weapon_facing"] = PI - 0.1
	presentation.reset(world)
	presentation.set_running(true)
	unit.weapon_facing = -PI + 0.1
	presentation.capture(world)
	presentation.update_fraction(0.5)
	if absf(absf(presentation.weapon_facing(unit)) - PI) > 0.001:
		failures.append("Weapon rotation must interpolate across angle wrap without spinning")
	var rng_state: int = world.rng.state
	for posture in [0, 1, 2]:
		for i in range(8):
			var angle: float = float(i) * TAU / 8.0
			var pose: Dictionary = Weapon.rifle(Vector2(20.5, 20.5), angle, posture)
			var visible_tip: Vector2 = Vector2(pose.anchor) + Vector2.from_angle(angle) * (21.25 / 64.0)
			if not visible_tip.is_equal_approx(Vector2(pose.muzzle)):
				failures.append("Displayed rifle barrel tip must match the shared simulation muzzle")
	for kind in ["mg", "mortar"]:
		var pose: Dictionary = Weapon.station(Vector2(20.5, 22.5), -PI * 0.75, kind)
		if Vector2(pose.muzzle).distance_to(Vector2(pose.anchor)) < 0.5:
			failures.append("Station muzzle must extend beyond the pivot")
	if world.rng.state != rng_state:
		failures.append("Weapon display transforms must not consume simulation randomness")

func _terminal_segment(make_world: Callable, failures: Array[String]) -> void:
	var world = make_world.call()
	world.units.clear(); world.buildings.clear(); world.projectiles.clear(); world.events.clear()
	world.units.append(State.unit(1, 0, Vector2(2, 5)))
	world.units.append(State.unit(100, 1, Vector2(3, 5)))
	var presentation = Presentation.new()
	presentation.reset(world)
	presentation.set_running(true)
	var projectile: Dictionary = world.combat_system.spawn_direct_projectile(world, world.units[0], world.units[1], Config.rifle(), 1.0)
	world.step_index += 1
	world.combat_system.advance_projectiles(world, Config.FIXED_DT)
	presentation.capture(world)
	if not world.projectiles.is_empty() or not presentation.current_projectiles.has(projectile.id):
		failures.append("A projectile born and hitting in one tick must retain its terminal display segment")
		return
	var terminal: Dictionary = presentation.current_projectiles[projectile.id]
	var impact_event: Dictionary = {}
	for event in world.events:
		if event.type == "projectile_impact": impact_event = event
	presentation.update_fraction(float(terminal.fraction) * 0.5)
	var point: Vector2 = presentation.projectile_position(terminal)
	if not point.is_equal_approx(Vector2(terminal.prev_pos).lerp(Vector2(terminal.pos), 0.5)) or not presentation.projectile_visible(terminal):
		failures.append("Terminal trajectory must reach the actual collision point at its sub-tick time")
	if presentation.event_ready(impact_event):
		failures.append("Impact effect must wait until the displayed projectile reaches its collision")
	presentation.update_fraction(float(terminal.fraction))
	if presentation.projectile_visible(terminal) or not presentation.event_ready(impact_event):
		failures.append("Terminal tracer and impact must exchange visibility at the same time")
	presentation.set_running(false); presentation.set_running(true)
	presentation.update_fraction(0.1)
	if presentation.projectile_visible(terminal) or not presentation.event_ready(impact_event):
		failures.append("Resume before another fixed tick must not replay terminal lifecycle")
	world.step_index += 1
	world.combat_system.advance_projectiles(world, Config.FIXED_DT)
	presentation.capture(world)
	if presentation.current_projectiles.has(projectile.id):
		failures.append("Terminal projectile must not survive into the next display interval")
	world.reset(); presentation.reset(world)
	if not presentation.current_projectiles.is_empty():
		failures.append("Restart must discard terminal trajectories")

func _explosion_display(make_world: Callable, failures: Array[String]) -> void:
	var world = make_world.call()
	world.units.clear(); world.buildings.clear(); world.projectiles.clear(); world.events.clear()
	var presentation = Presentation.new()
	presentation.reset(world); presentation.set_running(true)
	world.step_index = 1
	world.projectiles.append({"id": 9001, "kind": "mortar", "weapon_kind": "mortar", "team": 0, "shooter_id": 1, "start": Vector2(3, 5), "impact": Vector2(6, 5), "pos": Vector2(5.99, 5), "prev_pos": Vector2(5.99, 5), "velocity": Vector2.RIGHT, "dir": Vector2.RIGHT, "age": 3.0 - Config.FIXED_DT * 0.5, "life": Config.FIXED_DT * 0.5, "arc_height": 0.0, "born_step": 0})
	world.combat_system.advance_projectiles(world, Config.FIXED_DT)
	presentation.capture(world)
	var explosion: Dictionary = {}
	for event in world.events:
		if event.type == "explosion": explosion = event
	presentation.update_fraction(0.25)
	if presentation.event_ready(explosion): failures.append("Explosion must wait for shell touchdown")
	for projectile in presentation.current_projectiles.values():
		if projectile.kind == "fragment" and presentation.projectile_visible(projectile):
			failures.append("Fragments must not appear ahead of shell touchdown")
	presentation.update_fraction(0.75)
	if not presentation.event_ready(explosion): failures.append("Explosion must appear after shell touchdown")
	var visible_fragments := 0
	for projectile in presentation.current_projectiles.values():
		if projectile.kind == "fragment" and presentation.projectile_visible(projectile): visible_fragments += 1
	if visible_fragments != 24: failures.append("All actual explosion fragments must appear after touchdown")
	presentation.set_running(false); presentation.set_running(true)
	presentation.update_fraction(0.1)
	if not presentation.event_ready(explosion): failures.append("Resume must not hide an already displayed explosion")
	presentation.capture(world); presentation.update_fraction(0.1)
	presentation.finish_interval(); presentation.update_fraction(0.0)
	if not presentation.event_ready(explosion) or presentation.fraction != 1.0:
		failures.append("Battle result must complete the final display interval before freezing")
	if presentation.projectile_visible(presentation.current_projectiles[9001]):
		failures.append("Final shell must not stay suspended after the battle ends")

func _display_rates(make_world: Callable, failures: Array[String]) -> void:
	for physics_rate in [15, 60]:
		for display_rate in [30, 144]:
			var world = make_world.call()
			world.units.resize(1)
			var unit: Dictionary = world.units[0]
			var start: Vector2 = unit.pos
			var presentation = Presentation.new()
			presentation.reset(world); presentation.set_running(true)
			world.start_battle()
			world.submit([1], "move", {"position": start + Vector2(4, 0)})
			var interval := 1.0 / float(physics_rate)
			world.step(interval); presentation.capture(world)
			var next_capture := interval
			var last: Vector2 = start
			for frame in range(1, display_rate + 1):
				var render_time: float = float(frame) / float(display_rate)
				while render_time + 0.000001 >= next_capture:
					world.step(interval); presentation.capture(world); next_capture += interval
				presentation.update_fraction((render_time - (next_capture - interval)) / interval)
				var point: Vector2 = presentation.unit_position(unit)
				if point.x <= last.x or point.distance_to(last) > 2.5 / float(display_rate) + 0.0001:
					failures.append("Movement must remain continuous at physics %d Hz / display %d FPS" % [physics_rate, display_rate])
					break
				last = point
			if absf(last.x - start.x - 2.5) > 0.001:
				failures.append("Display sampling must preserve travel distance across update rates")
