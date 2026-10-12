extends Node2D

const GRID: float = 64.0
const Presentation = preload("res://scripts/ui/presentation_state.gd")
const Ground = preload("res://scripts/ui/ground_view.gd")
const Weapon = preload("res://scripts/sim/weapon_pose.gd")
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
		var duration: float = 0.13 if kind == "weapon_fired" else (1.2 if kind == "explosion" else (0.18 if kind == "damage" else 0.4))
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
	_draw_unit_aims()

func _draw_building(b: Dictionary) -> void:
	var point: Vector2 = b.pos * GRID
	var rect: Rect2 = Rect2(Vector2(b.rect.position) * GRID, Vector2(b.rect.size) * GRID)
	if b.destroyed:
		_prop(3, rect.grow(-3), Color(0.8, 0.8, 0.8, 0.8))
		return
	var selected: bool = int(screen.selected_building) == int(b.id)
	# Ground contact shadows use the same lower-right light direction as the atlas.
	if b.kind == "sandbag":
		draw_ellipse_shadow(rect.get_center() + Vector2(5, 19), Vector2(rect.size.x * 0.48, 11), Color(0.12, 0.19, 0.16, 0.22))
	else:
		draw_rect(Rect2(rect.position + Vector2(5, 7), rect.size), Color(0.12, 0.19, 0.16, 0.14))
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
			var weapon_angle: float = float(b.get("weapon_facing", b.facing))
			var pose: Dictionary = Weapon.station(b.pos, weapon_angle, b.kind)
			var kick: float = _recoil(int(b.id))
			draw_set_transform(Vector2(pose.anchor) * GRID - Vector2.from_angle(weapon_angle) * kick, weapon_angle)
			_prop(7 if b.kind == "mg" else 9, pose.sprite_rect)
			draw_set_transform(Vector2.ZERO)
			for slot in range(int(b.capacity)):
				var active: bool = slot < world.projected_crew(int(b.id)).size()
				draw_circle(point + Vector2((slot - (float(b.capacity) - 1) * 0.5) * 16, 42), 5, Color("b9edd5") if active else Color("3e4943"))
			var ammo_text: String = "%d + %d" % [int(b.loaded), int(b.ammo)] if b.kind == "mg" else "%d 炮弹" % int(b.ammo)
			var zoom: float = screen.camera.zoom.x
			# Crew and their IDs occupy the south side of a station. Keep stock above
			# the weapon so an occupied post remains as readable as an empty one.
			_screen_text(point - Vector2(0, maxf(68, 25 / zoom)), ammo_text, maxf(96, 88 * zoom), maxi(13, int(16 * zoom)), Color("e9e7c9"))
	if selected or float(b.hp) < float(b.max_hp):
		_bar(point + Vector2(-30, -rect.size.y * 0.5 - 15), 60, float(b.hp) / float(b.max_hp), Color("8cceae"))

func _draw_unit(u: Dictionary) -> void:
	var point: Vector2 = unit_position(u) * GRID
	var is_selected: bool = screen.selected.has(int(u.id))
	var down: bool = not bool(u.conscious) or bool(u.dead)
	var facing: float = motion.weapon_facing(u) if String(u.get("weapon_state", "idle")) in ["aiming", "firing", "recovering"] else motion.unit_facing(u)
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
	var damage_flash: float = _damage_flash(int(u.id))
	var tint: Color = (Color("9b9a8b") if u.dead else Color.WHITE).lerp(Color(1.0, 0.28, 0.24, 1.0), damage_flash * 0.72)
	# Injury shake is entirely visual; it never changes the foot point or hit box.
	var body_offset: Vector2 = Vector2(sin(visual_time * 115.0 + int(u.id)) * 2.0, cos(visual_time * 93.0 + int(u.id)) * 0.8) * damage_flash
	var working: bool = u.job == "treat" and u.stage == "treatment"
	var work_dip: float = 4.0 + sin(visual_time * 8.0) * 1.4 if working else 0.0
	var sway: float = sin(visual_time * 11 + float(u.id)) * 1.2 if u.velocity.length() > 0.1 and not down else 0.0
	var hands_busy: bool = int(u.get("crate_id", -1)) >= 0 or int(u.get("rescued_id", -1)) >= 0 or u.job == "treat"
	var has_weapon: bool = not down and not hands_busy and u.job != "operate"
	var weapon_behind: bool = posture != 2 and sin(facing) < -0.35
	if has_weapon and weapon_behind:
		_draw_rifle(point + body_offset, facing, posture, int(u.id))
	if posture == 2:
		draw_set_transform(point + body_offset, facing if not down else 0.0)
		draw_texture_rect_region(texture, Rect2(-body_size * 0.5, body_size), frame, tint)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect_region(texture, Rect2(point + body_offset + Vector2(-body_size.x * 0.5, -body_size.y * 0.875 + sway + work_dip), body_size), frame, tint)
	var carrying_crate: bool = false
	for box in world.supplies:
		if int(box.get("carried_by", -1)) == int(u.id): carrying_crate = true; break
	var rescued: Dictionary = world.entity(int(u.get("rescued_id", -1)))
	var carrying_person: bool = not rescued.is_empty() and int(rescued.get("carrier_id", -1)) == int(u.id)
	if has_weapon and not weapon_behind:
		_draw_rifle(point + body_offset, facing, posture, int(u.id))
	if working:
		var hands := point + Vector2(0, -20 + work_dip)
		draw_line(hands + Vector2(-10, 0), hands + Vector2(8, sin(visual_time * 10.0) * 3.0), Color("d4d4b5"), 5, true)
		draw_rect(Rect2(hands + Vector2(0, -4), Vector2(10, 7)), Color("edf0dc"))
		_progress_at(point, float(u.job_timer) / 6.0, "止血", Color("c5dfb7"))
	elif u.job == "operate" and u.stage == "station":
		var station: Dictionary = world.entity(int(u.station_id))
		if not station.is_empty():
			var toward: Vector2 = (Vector2(station.pos) * GRID - point).normalized()
			var grip: Vector2 = point + Vector2(0, -17)
			draw_line(grip - Vector2(7, 0), grip + toward * 15.0 + Vector2(4, 0), Color("acb99c"), 4, true)
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
			_unit_bar(point + Vector2(0, -62 if posture < 2 else -32), float(u.hp) / float(u.max_hp), Color("88c8ad") if u.conscious else Color("dfb775"))
		if float(u.suppression) > 1 and not u.dead:
			_unit_bar(point + Vector2(0, -62 if posture < 2 else -32), float(u.suppression) / 100.0, Color("e6b56b"), true)
	if int(u.team) == 0:
		_screen_text(point + Vector2(0, maxf(20, 12 / screen.camera.zoom.x)), "%02d" % int(u.id), 40, maxi(13, int(16 * screen.camera.zoom.x)), Color("e6f7de"))
	if is_selected and int(screen.hover_enemy) >= 0:
		var foe: Dictionary = world.entity(int(screen.hover_enemy))
		if not foe.is_empty():
			var cover: Dictionary = world.cover_for(u, _incoming_muzzle(foe, u.pos))
			var chance: float = float(cover.get("chance", 0.0))
			var blocked: bool = bool(cover.get("blocked", false))
			var text: String = "完全遮挡" if blocked else "掩护 %d%%" % int(chance * 100)
			_screen_text(point + Vector2(0, -62 if posture < 2 else -32) - Vector2(0, 5 / screen.camera.zoom.x), text, 180, maxi(12, int(15 * screen.camera.zoom.x)), Color("d0edc1"))

func _draw_rifle(point: Vector2, facing: float, posture: int, holder_id: int) -> void:
	var pose: Dictionary = Weapon.rifle(point / GRID, facing, posture)
	draw_set_transform(Vector2(pose.anchor) * GRID - Vector2.from_angle(facing) * _recoil(holder_id), facing)
	_prop(10, pose.sprite_rect)
	draw_set_transform(Vector2.ZERO)

func _recoil(holder_id: int) -> float:
	var kick: float = 0.0
	for fx in effects:
		if fx.kind != "weapon_fired" or not motion.event_ready(fx.data): continue
		if int(fx.data.get("holder_id", fx.data.get("entity_id", -1))) == holder_id:
			kick = maxf(kick, 4.0 * sin(clampf(float(fx.age) / float(fx.life), 0, 1) * PI))
	return kick

func _damage_flash(unit_id: int) -> float:
	var flash: float = 0.0
	for fx in effects:
		if fx.kind == "damage" and int(fx.data.get("entity_id", -1)) == unit_id and motion.event_ready(fx.data):
			flash = maxf(flash, 1.0 - float(fx.age) / float(fx.life))
	return flash

func _progress_at(point: Vector2, value: float, label: String, color: Color) -> void:
	_bar(point + Vector2(-21, -72), 42, value, color, 3)
	_screen_text(point + Vector2(0, -80), label, 100, 12, color)

func _draw_unit_aims() -> void:
	for u in world.units:
		if not u.conscious or u.dead or u.job == "operate": continue
		if not screen.selected.has(int(u.id)) and int(screen.hover_enemy) != int(u.id): continue
		if String(u.get("weapon_state", "idle")) != "aiming": continue
		_draw_aim_cone(unit_position(u) * GRID, motion.weapon_facing(u), float(u.get("aim_fraction", 0.0)), float(u.stability), int(u.style))
	for b in world.stations():
		if int(screen.selected_building) != int(b.id) and not screen.has_selected_crew(int(b.id)): continue
		if b.destroyed or String(b.get("weapon_state", "idle")) != "aiming": continue
		var crew: Array[int] = world.projected_crew(int(b.id))
		var gunner: Dictionary = world.entity(crew[0]) if not crew.is_empty() else {}
		_draw_aim_cone(Vector2(b.pos) * GRID, float(b.get("weapon_facing", b.facing)), float(b.get("aim_fraction", 0.0)), float(gunner.get("stability", 0.0)), int(gunner.get("style", 1)))

func _draw_aim_cone(point: Vector2, direction: float, progress: float, stability: float, style: int) -> void:
	var width: float = lerpf(0.36, 0.035, clampf(progress, 0, 1)) + (1.0 - clampf(stability, 0, 1)) * 0.12
	var length: float = 120.0
	var color: Color = [Color("e1b679"), Color("b9dbbc"), Color("a3d4d1")][clampi(style, 0, 2)]
	var points := PackedVector2Array([point])
	for i in range(17): points.append(point + Vector2.from_angle(direction - width + width * 2 * i / 16.0) * length)
	draw_colored_polygon(points, Color(color, 0.075))
	draw_line(point, points[1], Color(color, 0.32), 1.2, true)
	draw_line(point, points[points.size() - 1], Color(color, 0.32), 1.2, true)
	draw_arc(point, 30, direction - PI * 0.5, direction - PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 32, Color(color, 0.65), 2, true)

func _draw_station_ranges() -> void:
	for b in world.stations():
		var show_crew_range: bool = screen.selected.size() == 1 and screen.has_selected_crew(int(b.id))
		if b.destroyed or (int(screen.selected_building) != int(b.id) and not show_crew_range):
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
			var trail: float = 20.0 if kind != "fragment" else 9.0
			if projectile.has("start"): trail = minf(trail, point.distance_to(Vector2(projectile.start) * GRID))
			draw_line(point - velocity.normalized() * trail, point, color, 1.8 if kind != "fragment" else 1.2, true)

func _draw_effects() -> void:
	for fx in effects:
		if not motion.event_ready(fx.data): continue
		var progress: float = float(fx.age) / float(fx.life)
		var point: Vector2 = fx.pos
		var alpha: float = 1.0 - progress
		match String(fx.kind):
			"weapon_fired":
				if progress < 0.5:
					var facing: float = Vector2(fx.data.get("aim_dir", fx.data.get("dir", Vector2.RIGHT))).angle()
					draw_set_transform(point, facing)
					var flame := PackedVector2Array([Vector2(-3, -3), Vector2(8, -5), Vector2(18, 0), Vector2(8, 5), Vector2(-3, 3)])
					draw_colored_polygon(flame, Color(1.0, 0.68, 0.26, alpha * 0.85))
					draw_circle(Vector2(3, 0), 4.0, Color(1.0, 0.94, 0.7, alpha))
					draw_set_transform(Vector2.ZERO)
			"explosion":
				if progress < 0.25:
					draw_circle(point, 35 + progress * 200, Color(1, 0.75, 0.34, alpha * 0.7))
				draw_arc(point, 20 + progress * 230, 0, TAU, 48, Color(0.94, 0.85, 0.66, alpha * 0.7), 4 * alpha + 1, true)
				for i in range(7):
					var off: Vector2 = Vector2.from_angle(float(i) * 2.39) * progress * 85
					draw_circle(point + off + Vector2(0, -progress * 30), 15 + progress * 38, Color(0.24, 0.27, 0.23, alpha * 0.28))
			"damage":
				if not world.entity(int(fx.data.get("entity_id", -1))).has("team"):
					draw_arc(point, 12 + progress * 10, 0, TAU, 12, Color(0.86, 0.31, 0.23, alpha * 0.6), 2, true)
			"projectile_impact":
				var material: String = String(fx.data.get("material", "ground"))
				if material in ["metal", "armor"]:
					for i in range(6):
						var direction := Vector2.from_angle(float(i) * 1.05 + float(fx.data.get("serial", 0)) * 0.17)
						draw_line(point + direction * progress * 5, point + direction * (5 + progress * 25), Color(0.98, 0.88, 0.62, alpha), 1.5, true)
				elif material == "concrete":
					for i in range(5):
						var offset := Vector2.from_angle(float(i) * 2.39) * progress * 20.0
						draw_rect(Rect2(point + offset, Vector2(3.5, 2.5)), Color(0.72, 0.76, 0.69, alpha * 0.9))
				elif material == "unit":
					for i in range(3):
						var offset := Vector2.from_angle(float(i) * 2.1) * progress * 12.0
						draw_circle(point + offset, 2.5 * alpha, Color(0.65, 0.24, 0.2, alpha * 0.65))
				else:
					var dust := Color(0.67, 0.59, 0.4, alpha * 0.32) if material == "sandbag" else Color(0.48, 0.4, 0.3, alpha * 0.35)
					for i in range(4):
						var offset := Vector2.from_angle(float(i) * 2.39) * progress * 15.0
						draw_circle(point + offset + Vector2(0, -progress * 8), 3.0 + progress * 7.0, dust)
			_:
				for i in range(4):
					var direction: Vector2 = Vector2.from_angle(float(i) * 1.57 + 0.4)
					draw_line(point + direction * progress * 4, point + direction * (6 + progress * 19), Color(0.95, 0.87, 0.61, alpha), 1.5, true)

func _draw_orders() -> void:
	for id in screen.selected:
		var u: Dictionary = world.entity(int(id))
		if u.is_empty(): continue
		if u.job != "operate": _draw_forced_target(u, unit_position(u) * GRID)
		var goal: Vector2 = u.get("goal", u.pos)
		for order in world.pending_orders:
			if order.ids.has(id) and order.kind == "move": goal = order.data.position
		if u.pos.distance_to(goal) > 0.2:
			draw_dashed_line(unit_position(u) * GRID, goal * GRID, Color(0.75, 0.93, 0.79, 0.6), 1.5, 12)
			draw_arc(goal * GRID, 9, 0, TAU, 16, Color("c4f1cf"), 2, true)
	var station: Dictionary = world.entity(int(screen.selected_building))
	if not station.is_empty() and int(station.get("capacity", 0)) > 0:
		_draw_forced_target(station, Vector2(station.pos) * GRID)

func _draw_forced_target(holder: Dictionary, origin: Vector2) -> void:
	var target: Dictionary = world.entity(int(holder.get("target_id", -1)))
	if target.is_empty() or target.get("dead", false) or target.get("destroyed", false): return
	var destination: Vector2 = (unit_position(target) if target.has("team") else Vector2(target.pos)) * GRID
	draw_dashed_line(origin, destination, Color(0.96, 0.61, 0.42, 0.32), 1.3, 10)
	draw_arc(destination, 28, 0, TAU, 24, Color(1.0, 0.67, 0.43, 0.75), 2, true)
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(destination + direction * 22, destination + direction * 34, Color("f7bd87"), 2, true)

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
	preview.pos = Vector2(Vector2i(screen.mouse_world().floor())) + Vector2.ONE * 0.5
	var point: Vector2 = preview.pos * GRID
	if not world.unit_system.destination_available(world, preview.pos, int(u.id)):
		draw_rect(Rect2(point - Vector2.ONE * 32.0, Vector2.ONE * GRID), Color(0.8, 0.39, 0.29, 0.2))
		_screen_text(point + Vector2(0, 46), "不可停留 / 已占用", 180, 12, Color("ebad8e"))
		return
	var cover: Dictionary = world.cover_for(preview, _incoming_muzzle(foe, preview.pos))
	var chance: float = float(cover.get("chance", 0.0))
	var blocked: bool = bool(cover.get("blocked", false))
	var color: Color = Color("b6eccb") if chance > 0 or blocked else Color("e3c596")
	draw_arc(point, 23, 0, TAU, 32, color, 2, true)
	var direction: Vector2 = (foe.pos - preview.pos).normalized()
	draw_line(point + direction * 30, point + direction * 70, color, 2, true)
	for obstacle in cover.get("obstacles", []):
		if float(obstacle.get("chance", 0.0)) > 0.0:
			draw_rect(Rect2(Vector2(obstacle.cell) * GRID, Vector2.ONE * GRID), Color(color, 0.16))
	var label: String = "落点完全遮挡" if blocked else "落点拦截 %d%%" % int(chance * 100)
	_screen_text(point + Vector2(0, maxf(46, 24 / screen.camera.zoom.x)), label, 180, maxi(12, int(16 * screen.camera.zoom.x)), color)

func _incoming_muzzle(shooter: Dictionary, destination: Vector2) -> Vector2:
	return Vector2(Weapon.aimed_rifle(shooter.pos, destination, int(shooter.posture)).muzzle)

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

func _screen_text(anchor: Vector2, text: String, width: float, size: int, color: Color) -> void:
	draw_set_transform(anchor, 0, Vector2.ONE / screen.camera.zoom.x)
	draw_string(font, Vector2(-width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)
	draw_set_transform(Vector2.ZERO)

func _unit_bar(anchor: Vector2, value: float, color: Color, suppression: bool = false) -> void:
	var zoom: float = screen.camera.zoom.x
	var width: float = maxf(28, 42 * zoom)
	var height: float = maxf(3, 4 * zoom)
	draw_set_transform(anchor, 0, Vector2.ONE / zoom)
	_bar(Vector2(-width * 0.5, height + 2 if suppression else 0), width, value, color, 2 if suppression else height)
	draw_set_transform(Vector2.ZERO)

func draw_ellipse_shadow(center: Vector2, radii: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(24):
		points.append(center + Vector2(cos(float(i) / 24 * TAU) * radii.x, sin(float(i) / 24 * TAU) * radii.y))
	draw_colored_polygon(points, color)
