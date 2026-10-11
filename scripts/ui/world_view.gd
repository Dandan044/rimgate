extends Node2D

const GRID: float = 64.0
const Presentation = preload("res://scripts/ui/presentation_state.gd")
const Ground = preload("res://scripts/ui/ground_view.gd")
var motion = Presentation.new()
var screen: Node
var world
var friendly: Texture2D
var enemy: Texture2D
var heavy: Texture2D
var props: Texture2D
var terrain: Texture2D
var effects: Array[Dictionary] = []
var visual_time: float = 0.0
var font: Font

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	friendly = load("res://assets/art/vector/friendly_atlas.svg")
	enemy = load("res://assets/art/vector/enemy_atlas.svg")
	heavy = load("res://assets/art/vector/heavy_atlas.svg")
	props = load("res://assets/art/vector/props_atlas.svg")
	font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/NotoSansCJKsc-Regular.otf"):
		font = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	var ground = Ground.new()
	ground.world = world
	ground.props = props
	ground.font = font
	ground.show_behind_parent = true
	add_child(ground)
	reset_presentation()

func tick(_dt: float) -> void:
	motion.capture(world)

func reset_presentation() -> void:
	motion.reset(world)

func set_running(running: bool) -> void:
	if world.phase in ["won", "lost"]: motion.finish_interval()
	else: motion.set_running(running)

func unit_position(unit: Dictionary) -> Vector2:
	return motion.unit_position(unit)

func advance_display(dt: float) -> void:
	if world.phase != "running": return
	motion.update_fraction(Engine.get_physics_interpolation_fraction())
	visual_time += dt
	for fx in effects:
		if motion.event_ready(fx.data): fx.age += dt
	for i in range(effects.size() - 1, -1, -1):
		if effects[i].age >= effects[i].life:
			effects.remove_at(i)
	queue_redraw()

func on_event(event: Dictionary) -> void:
	var kind: String = event.get("type", "")
	if kind in ["weapon_fired", "projectile_impact", "explosion", "damage", "building_destroyed"]:
		var duration: float = 0.16 if kind == "weapon_fired" else (1.2 if kind == "explosion" else 0.45)
		effects.append({"kind": kind, "age": 0.0, "life": duration, "pos": event.get("pos", Vector2.ZERO) * GRID, "data": event})
		if effects.size() > 160:
			effects.pop_front()

func _draw() -> void:
	if world == null:
		return
	_draw_station_ranges()
	var things: Array[Dictionary] = []
	for b in world.buildings:
		things.append({"y": b.pos.y, "kind": "building", "data": b})
	for u in world.units:
		if int(u.get("carrier_id", -1)) < 0:
			things.append({"y": unit_position(u).y, "kind": "unit", "data": u})
	things.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.y) < float(b.y))
	for box in world.supplies:
		if not box.get("delivered", false) and int(box.get("carried_by", -1)) < 0 and int(box.get("amount", 0)) > 0:
			var point: Vector2 = box.pos * GRID
			_prop(12 if box.kind == "mg_ammo" else 13, Rect2(point - Vector2(18, 14), Vector2(36, 28)))
	for thing in things:
		if thing.kind == "building":
			_draw_building(thing.data)
		else:
			_draw_unit(thing.data)
	_draw_projectiles()
	_draw_effects()
	_draw_orders()
	_draw_cover_preview()
	_draw_aim_preview()

func _draw_building(b: Dictionary) -> void:
	var point: Vector2 = b.pos * GRID
	var rect: Rect2 = Rect2(Vector2(b.rect.position) * GRID, Vector2(b.rect.size) * GRID)
	if b.destroyed:
		_prop(3, rect.grow(-3), Color(0.8, 0.8, 0.8, 0.8))
		return
	var selected: bool = int(screen.selected_building) == int(b.id)
	if selected:
		draw_rect(rect.grow(6), Color("b6ead6"), false, 2.5)
	match String(b.kind):
		"sandbag": _prop(0, rect.grow(8))
		"wall": _prop(1, Rect2(rect.position - Vector2(0, 22), rect.size + Vector2(0, 22)))
		"crate": _prop(2, rect.grow(6))
		"core":
			_prop(4, rect.grow(8))
			var pulse: float = 0.5 + 0.5 * sin(visual_time * 1.8)
			draw_arc(point, 48 + pulse * 3, 0, TAU, 48, Color(0.42, 0.93, 0.86, 0.4 + pulse * 0.2), 3, true)
		"mg", "mortar":
			_prop(6 if b.kind == "mg" else 8, rect.grow(10))
			draw_set_transform(point, float(b.facing))
			_prop(7 if b.kind == "mg" else 9, Rect2(-22, -17, 76, 34))
			draw_set_transform(Vector2.ZERO)
			for slot in range(int(b.capacity)):
				var active: bool = slot < world.projected_crew(int(b.id)).size()
				draw_circle(point + Vector2((slot - (float(b.capacity) - 1) * 0.5) * 16, 42), 5, Color("b9edd5") if active else Color("3e4943"))
			var ammo_text: String = "%d + %d" % [int(b.loaded), int(b.ammo)] if b.kind == "mg" else "%d 炮弹" % int(b.ammo)
			draw_string(font, point + Vector2(-44, 67), ammo_text, HORIZONTAL_ALIGNMENT_CENTER, 88, 16, Color("e9e7c9"))
	if selected or float(b.hp) < float(b.max_hp):
		_bar(point + Vector2(-30, -rect.size.y * 0.5 - 15), 60, float(b.hp) / float(b.max_hp), Color("8cceae"))

func _draw_unit(u: Dictionary) -> void:
	var point: Vector2 = unit_position(u) * GRID
	var is_selected: bool = screen.selected.has(int(u.id))
	var down: bool = not bool(u.conscious) or bool(u.dead)
	var facing: float = motion.unit_facing(u)
	if is_selected:
		draw_arc(point, 24, 0, TAU, 32, Color("c4ffe6"), 2.5, true)
	elif int(u.team) == 1 and int(screen.hover_enemy) == int(u.id):
		draw_arc(point, 24, 0, TAU, 32, Color("ffab88"), 2.5, true)
	draw_set_transform(point)
	draw_ellipse_shadow(Vector2(0, 2), Vector2(18, 8), Color(0.1, 0.15, 0.12, 0.32))
	draw_set_transform(Vector2.ZERO)
	var texture: Texture2D = friendly if int(u.team) == 0 else (heavy if u.kind == "heavy" and heavy != null else enemy)
	var posture: int = 2 if down else int(u.posture)
	var index: int = 0
	var angle: float = wrapf(facing, -PI, PI)
	var direction: int = 1
	if angle >= PI / 4 and angle < 3 * PI / 4: direction = 0
	elif angle >= -3 * PI / 4 and angle < -PI / 4: direction = 2
	elif absf(angle) >= 3 * PI / 4: direction = 3
	index = direction + (5 if posture == 1 else 0)
	if posture == 2:
		index = 9 if down else 4
	var frame: Rect2 = _character_region(texture, index)
	var body_size: Vector2 = Vector2(77, 77) if u.kind == "heavy" else Vector2(68, 68)
	var tint: Color = Color("9b9a8b") if u.dead else Color.WHITE
	var sway: float = sin(visual_time * 11 + float(u.id)) * 1.2 if u.velocity.length() > 0.1 and not down else 0.0
	var hands_busy: bool = int(u.get("crate_id", -1)) >= 0 or int(u.get("rescued_id", -1)) >= 0 or u.job == "treat"
	var has_weapon: bool = not down and not hands_busy and u.job != "operate"
	var weapon_behind: bool = posture != 2 and sin(facing) < -0.35
	if has_weapon and weapon_behind:
		_draw_rifle(point, facing, posture)
	if posture == 2:
		draw_set_transform(point, facing if not down else 0.0)
		draw_texture_rect_region(texture, Rect2(-body_size * 0.5, body_size), frame, tint)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect_region(texture, Rect2(point + Vector2(-body_size.x * 0.5, -body_size.y * 0.875 + sway), body_size), frame, tint)
	var carrying_crate: bool = false
	for box in world.supplies:
		if int(box.get("carried_by", -1)) == int(u.id): carrying_crate = true; break
	var rescued: Dictionary = world.entity(int(u.get("rescued_id", -1)))
	var carrying_person: bool = not rescued.is_empty() and int(rescued.get("carrier_id", -1)) == int(u.id)
	if has_weapon and not weapon_behind:
		_draw_rifle(point, facing, posture)
	if carrying_crate:
		_prop(12, Rect2(point + Vector2(-13, -31), Vector2(30, 24)))
	if carrying_person:
		draw_texture_rect_region(friendly, Rect2(point + Vector2(-31, -58), Vector2(62, 62)), _character_region(friendly, 9))
	if float(u.bleed_rate) > 0.0:
		draw_circle(point + Vector2(21, -26), 5, Color("ca6255"))
	if u.dead:
		draw_line(point + Vector2(-6, -6), point + Vector2(6, 6), Color("e1d8c7"), 2)
		draw_line(point + Vector2(6, -6), point + Vector2(-6, 6), Color("e1d8c7"), 2)
	elif not u.conscious:
		draw_line(point + Vector2(-7, -17), point + Vector2(7, -17), Color("f3d399"), 4)
		draw_line(point + Vector2(0, -24), point + Vector2(0, -10), Color("f3d399"), 4)
	if int(u.team) == 0 or is_selected or int(screen.hover_enemy) == int(u.id):
		if not u.dead:
			_bar(point + Vector2(-21, -62 if posture < 2 else -32), 42, float(u.hp) / float(u.max_hp), Color("88c8ad") if u.conscious else Color("dfb775"))
		if float(u.suppression) > 1 and not u.dead:
			_bar(point + Vector2(-21, -56 if posture < 2 else -26), 42, float(u.suppression) / 100.0, Color("e6b56b"), 2)
	if int(u.team) == 0:
		draw_string(font, point + Vector2(-10, 20), "%02d" % int(u.id), HORIZONTAL_ALIGNMENT_CENTER, 20, 16, Color("e6f7de"))
	if is_selected and int(screen.hover_enemy) >= 0:
		var foe: Dictionary = world.entity(int(screen.hover_enemy))
		if not foe.is_empty():
			var cover: Dictionary = world.cover_for(u, foe.pos)
			var chance: float = float(cover.get("chance", 0.0))
			var blocked: bool = bool(cover.get("blocked", false))
			var text: String = "完全遮挡" if blocked else "掩护 %d%%" % int(chance * 100)
			draw_string(font, point + Vector2(-50, -64), text, HORIZONTAL_ALIGNMENT_CENTER, 100, 15, Color("d0edc1"))

func _draw_rifle(point: Vector2, facing: float, posture: int) -> void:
	var hand := Vector2(-sin(facing) * 18, -17 + cos(facing) * 7)
	if posture == 2:
		hand = Vector2.from_angle(facing) * 12 + Vector2(-sin(facing), cos(facing)) * 9
	draw_set_transform(point + hand, facing)
	_prop(10, Rect2(-15.625, -20, 40, 40))
	draw_set_transform(Vector2.ZERO)

func _draw_station_ranges() -> void:
	for b in world.stations():
		if b.destroyed or (int(screen.selected_building) != int(b.id) and not screen.has_selected_crew(int(b.id))):
			continue
		var point: Vector2 = b.pos * GRID
		if b.kind == "mg":
			var radius: float = 32 * GRID
			draw_arc(point, radius, float(b.facing) - PI / 3, float(b.facing) + PI / 3, 48, Color(0.75, 0.87, 0.66, 0.25), 2, true)
			for angle in [float(b.facing) - PI / 3, float(b.facing) + PI / 3]:
				draw_line(point, point + Vector2.from_angle(angle) * radius, Color(0.75, 0.87, 0.66, 0.22), 2)
		else:
			draw_arc(point, 8 * GRID, 0, TAU, 64, Color(0.91, 0.75, 0.47, 0.4), 2, true)
			draw_arc(point, 40 * GRID, 0, TAU, 96, Color(0.75, 0.87, 0.66, 0.22), 2, true)

func _draw_projectiles() -> void:
	for projectile in motion.current_projectiles.values():
		if not motion.projectile_visible(projectile): continue
		var point: Vector2 = motion.projectile_position(projectile) * GRID
		var kind: String = projectile.get("kind", "bullet")
		if kind == "mortar":
			var progress: float = motion.projectile_age(projectile) / 3.0
			var lift: float = sin(clampf(progress, 0, 1) * PI) * 150
			draw_circle(point, 7, Color(0.1, 0.15, 0.12, 0.3))
			_prop(11, Rect2(point + Vector2(-12, -lift - 8), Vector2(24, 16)))
		else:
			var velocity: Vector2 = projectile.get("velocity", projectile.get("dir", Vector2.RIGHT))
			if velocity.length() < 0.01: velocity = Vector2.RIGHT
			var color: Color = Color("f8d585") if kind != "fragment" else Color("d8bb9c")
			draw_line(point - velocity.normalized() * (20 if kind != "fragment" else 9), point, color, 1.8 if kind != "fragment" else 1.2, true)

func _draw_effects() -> void:
	for fx in effects:
		if not motion.event_ready(fx.data): continue
		var progress: float = float(fx.age) / float(fx.life)
		var point: Vector2 = fx.pos
		var alpha: float = 1.0 - progress
		match String(fx.kind):
			"weapon_fired":
				draw_circle(point, 9 * alpha, Color(1.0, 0.85, 0.49, alpha))
			"explosion":
				if progress < 0.25:
					draw_circle(point, 35 + progress * 200, Color(1, 0.75, 0.34, alpha * 0.7))
				draw_arc(point, 20 + progress * 230, 0, TAU, 48, Color(0.94, 0.85, 0.66, alpha * 0.7), 4 * alpha + 1, true)
				for i in range(7):
					var off: Vector2 = Vector2.from_angle(float(i) * 2.39) * progress * 85
					draw_circle(point + off + Vector2(0, -progress * 30), 15 + progress * 38, Color(0.24, 0.27, 0.23, alpha * 0.28))
			"damage":
				draw_arc(point, 12 + progress * 10, 0, TAU, 12, Color(0.86, 0.31, 0.23, alpha * 0.8), 2, true)
			_:
				for i in range(4):
					var direction: Vector2 = Vector2.from_angle(float(i) * 1.57 + 0.4)
					draw_line(point + direction * progress * 4, point + direction * (6 + progress * 19), Color(0.95, 0.87, 0.61, alpha), 1.5, true)

func _draw_orders() -> void:
	for id in screen.selected:
		var u: Dictionary = world.entity(int(id))
		if u.is_empty(): continue
		var goal: Vector2 = u.get("goal", u.pos)
		for order in world.pending_orders:
			if order.ids.has(id) and order.kind == "move": goal = order.data.position
		if u.pos.distance_to(goal) > 0.2:
			draw_dashed_line(unit_position(u) * GRID, goal * GRID, Color(0.75, 0.93, 0.79, 0.6), 1.5, 12)
			draw_arc(goal * GRID, 9, 0, TAU, 16, Color("c4f1cf"), 2, true)

func _draw_aim_preview() -> void:
	if int(screen.aim_station) < 0: return
	var point: Vector2 = screen.mouse_world() * GRID
	var dispersion: float = 2.5
	var crew: Array[int] = world.projected_crew(int(screen.aim_station))
	if not crew.is_empty():
		var gunner: Dictionary = world.entity(crew[0])
		if not gunner.is_empty():
			dispersion -= 1.5 * clampf(float(gunner.stability), 0.0, 1.0)
	draw_circle(point, 4 * GRID, Color(1, 0.5, 0.29, 0.08))
	draw_arc(point, 4 * GRID, 0, TAU, 64, Color(1, 0.68, 0.45, 0.8), 2, true)
	draw_arc(point, 10 * GRID, 0, TAU, 96, Color(0.97, 0.75, 0.51, 0.35), 2, true)
	draw_arc(point, dispersion * GRID, 0, TAU, 48, Color(0.98, 0.93, 0.71, 0.7), 2, true)
	draw_line(point - Vector2(14, 0), point + Vector2(14, 0), Color("fff3bc"), 2)
	draw_line(point - Vector2(0, 14), point + Vector2(0, 14), Color("fff3bc"), 2)

func _draw_cover_preview() -> void:
	if screen.selected.is_empty() or screen.aim_station >= 0 or screen.hover_enemy >= 0:
		return
	if screen._over_hud(screen.get_viewport().get_mouse_position()): return
	var foe: Dictionary = screen.cover_reference()
	if foe.is_empty(): return
	var u: Dictionary = world.entity(int(screen.selected[0]))
	if u.is_empty() or not u.conscious or u.dead: return
	var preview: Dictionary = u.duplicate()
	preview.pos = screen.mouse_world()
	var cover: Dictionary = world.cover_for(preview, foe.pos)
	var chance: float = float(cover.get("chance", 0.0))
	var blocked: bool = bool(cover.get("blocked", false))
	var point: Vector2 = preview.pos * GRID
	var color: Color = Color("b6eccb") if chance > 0 or blocked else Color("e3c596")
	draw_arc(point, 23, 0, TAU, 32, color, 2, true)
	var direction: Vector2 = (foe.pos - preview.pos).normalized()
	draw_line(point + direction * 30, point + direction * 70, color, 2, true)
	if int(cover.get("building_id", -1)) >= 0:
		draw_rect(Rect2(Vector2(cover.cell) * GRID, Vector2.ONE * GRID), Color(color, 0.16))
	var label: String = "落点完全遮挡" if blocked else "落点拦截 %d%%" % int(chance * 100)
	draw_string(font, point + Vector2(-65, 46), label, HORIZONTAL_ALIGNMENT_CENTER, 130, 16, color)

func _character_region(texture: Texture2D, index: int) -> Rect2:
	var size: Vector2 = texture.get_size()
	var width: float = size.x / 5.0
	var height: float = size.y / 2.0
	return Rect2((index % 5) * width, int(index / 5) * height, width, height)

func _prop(index: int, destination: Rect2, tint: Color = Color.WHITE) -> void:
	if props == null:
		return
	var size: Vector2 = props.get_size() / 4.0
	var source: Rect2 = Rect2(Vector2(index % 4, int(index / 4)) * size, size)
	draw_texture_rect_region(props, destination, source, tint)

func _terrain_tile(index: int, destination: Rect2) -> void:
	if terrain == null: return
	var cell: Vector2 = Vector2(terrain.get_width() / 3.0, terrain.get_height())
	draw_texture_rect_region(terrain, destination, Rect2(Vector2(index * cell.x, 0), cell))

func _terrain_area(index: int, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_terrain_tile(index, Rect2(x * GRID, y * GRID, GRID, GRID))

func _bar(point: Vector2, width: float, value: float, color: Color, height: float = 4) -> void:
	draw_rect(Rect2(point, Vector2(width, height)), Color(0.1, 0.15, 0.13, 0.8))
	draw_rect(Rect2(point, Vector2(width * clampf(value, 0, 1), height)), color)

func draw_ellipse_shadow(center: Vector2, radii: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(24):
		points.append(center + Vector2(cos(float(i) / 24 * TAU) * radii.x, sin(float(i) / 24 * TAU) * radii.y))
	draw_colored_polygon(points, color)
