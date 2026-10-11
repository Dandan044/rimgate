extends RefCounted

# Coordinates used for drawing never become authoritative simulation state.
var previous_units: Dictionary = {}
var current_units: Dictionary = {}
var previous_projectiles: Dictionary = {}
var current_projectiles: Dictionary = {}
var fraction: float = 1.0
var frozen: bool = true
var step: int = 0
var waiting_for_capture: bool = false

func reset(world) -> void:
	current_units.clear()
	current_projectiles.clear()
	previous_units.clear()
	previous_projectiles.clear()
	step = int(world.step_index)
	capture(world)
	previous_units = current_units.duplicate()
	previous_projectiles = current_projectiles.duplicate()
	fraction = 1.0
	frozen = true

func capture(world) -> void:
	waiting_for_capture = false
	step = int(world.step_index)
	previous_units = current_units
	previous_projectiles = current_projectiles
	current_units = {}
	current_projectiles = {}
	for unit in world.units:
		var id: int = int(unit.id)
		var state := {"pos": Vector2(unit.pos), "facing": float(unit.facing), "carrier": int(unit.get("carrier_id", -1))}
		current_units[id] = state
		var prior: Dictionary = previous_units.get(id, state)
		# Spawn, pickup/drop and teleport must not sweep through intervening space.
		if prior.carrier != state.carrier or Vector2(prior.pos).distance_squared_to(state.pos) > 2.25:
			previous_units[id] = state
	for projectile in world.projectiles:
		var id: int = int(projectile.id)
		var state: Dictionary = projectile.duplicate()
		state["age"] = float(projectile.get("age", 0.0))
		state["terminal"] = false
		state["visible_from"] = 0.0
		if projectile.get("kind", "") == "fragment" and int(projectile.get("born_step", -1)) == step:
			for terminal in world.combat_system.finished_projectiles:
				if terminal.reason == "ground" and Vector2(terminal.pos).is_equal_approx(Vector2(projectile.pos)):
					state.visible_from = float(terminal.fraction)
		current_projectiles[id] = state
		if not previous_projectiles.has(id):
			previous_projectiles[id] = {"pos": Vector2(projectile.get("prev_pos", projectile.pos)), "age": maxf(0.0, state.age - 1.0 / 60.0)}
	for terminal in world.combat_system.finished_projectiles:
		if int(terminal.step) != step: continue
		var id: int = int(terminal.id)
		var state: Dictionary = terminal.duplicate()
		state["terminal"] = true
		current_projectiles[id] = state
		previous_projectiles[id] = {"pos": Vector2(state.prev_pos), "age": float(state.prev_age)}

func set_running(running: bool) -> void:
	if running and frozen:
		previous_units = current_units.duplicate()
		previous_projectiles = current_projectiles.duplicate()
		fraction = 1.0
		waiting_for_capture = true
	frozen = not running

func update_fraction(value: float) -> void:
	if not frozen and not waiting_for_capture:
		fraction = clampf(value, 0.0, 1.0)

func finish_interval() -> void:
	# A result freezes the completed final tick, unlike an explicit player pause.
	fraction = 1.0
	frozen = true
	waiting_for_capture = true

func unit_position(unit: Dictionary) -> Vector2:
	return _position(previous_units, current_units, int(unit.id), unit.pos)

func unit_facing(unit: Dictionary) -> float:
	var current: Dictionary = current_units.get(int(unit.id), {})
	if current.is_empty(): return float(unit.facing)
	var previous: Dictionary = previous_units.get(int(unit.id), current)
	return lerp_angle(float(previous.facing), float(current.facing), fraction)

func projectile_position(projectile: Dictionary) -> Vector2:
	var id: int = int(projectile.id)
	var current: Dictionary = current_projectiles.get(id, projectile)
	var previous: Dictionary = previous_projectiles.get(id, current)
	return Vector2(previous.pos).lerp(Vector2(current.pos), _projectile_fraction(current))

func projectile_visible(projectile: Dictionary) -> bool:
	if fraction < float(projectile.get("visible_from", 0.0)): return false
	return not projectile.get("terminal", false) or fraction < float(projectile.fraction)

func event_ready(event: Dictionary) -> bool:
	if int(event.get("step", 0)) < step: return true
	if event.get("type", "") == "weapon_fired": return true
	var projectile: Dictionary = current_projectiles.get(int(event.get("projectile_id", -1)), {})
	if projectile.is_empty() and event.get("type", "") == "explosion":
		for terminal in current_projectiles.values():
			if terminal.get("reason", "") == "ground" and Vector2(terminal.pos).is_equal_approx(Vector2(event.pos)):
				return fraction >= float(terminal.fraction)
	return fraction >= float(projectile.get("fraction", 1.0))

func _projectile_fraction(projectile: Dictionary) -> float:
	return clampf(fraction / maxf(0.00001, float(projectile.get("fraction", 1.0))), 0.0, 1.0)

func projectile_age(projectile: Dictionary) -> float:
	var current: Dictionary = current_projectiles.get(int(projectile.id), {})
	if current.is_empty(): return float(projectile.get("age", 0.0))
	var previous: Dictionary = previous_projectiles.get(int(projectile.id), current)
	return lerpf(float(previous.age), float(current.age), _projectile_fraction(current))

func _position(previous: Dictionary, current: Dictionary, id: int, fallback: Vector2) -> Vector2:
	if not current.has(id): return fallback
	var to: Dictionary = current[id]
	var from: Dictionary = previous.get(id, to)
	return Vector2(from.pos).lerp(to.pos, fraction)
