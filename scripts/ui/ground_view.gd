extends Node2D

const GRID := 64.0
# Fixed decoration positions are independent of simulation RNG and navigation.
const GRASS_SPOTS: Array[Vector3] = [
	Vector3(3.8, 4.4, 0.82), Vector3(6.1, 5.7, 1.05),
	Vector3(21.9, 4.3, 0.9), Vector3(27.6, 6.0, 1.18),
	Vector3(34.8, 3.7, 0.78), Vector3(39.4, 7.8, 0.96),
	Vector3(55.8, 4.2, 1.1), Vector3(60.6, 7.4, 0.8),
	Vector3(4.5, 11.8, 1.02), Vector3(6.8, 15.2, 0.85),
	Vector3(21.2, 12.9, 1.05), Vector3(29.3, 10.7, 0.82),
	Vector3(36.2, 14.7, 1.1), Vector3(54.8, 12.2, 0.95),
	Vector3(60.4, 15.8, 1.16), Vector3(18.7, 16.2, 0.85),
	Vector3(26.8, 15.6, 0.9), Vector3(38.7, 17.4, 0.86),
	Vector3(3.3, 29.7, 0.88), Vector3(6.0, 36.2, 1.12),
	Vector3(17.9, 32.8, 0.82), Vector3(19.3, 42.7, 1.03),
	Vector3(55.9, 28.8, 1.08), Vector3(58.3, 34.9, 0.8),
	Vector3(53.7, 42.4, 0.91), Vector3(61.2, 45.1, 1.14),
	Vector3(10.6, 45.7, 0.84),
]
const STONE_SPOTS: Array[Vector3] = [
	Vector3(5.4, 8.9, 0.58), Vector3(23.1, 6.8, 0.7),
	Vector3(38.6, 11.3, 0.46), Vector3(57.2, 6.2, 0.62),
	Vector3(60.3, 24.4, 0.53), Vector3(6.7, 33.9, 0.7),
	Vector3(17.3, 44.1, 0.55), Vector3(57.8, 41.2, 0.6),
]
var world
var props: Texture2D
var font: Font
var grass: Texture2D = preload("res://assets/art/vector/grass_01.svg")

func _draw() -> void:
	# This CanvasItem has no process callback or redraw requests: Godot retains
	# the static draw commands while the camera and combat layers keep moving.
	draw_rect(Rect2(0, 0, 4096, 3072), Color("7b8568"))
	# Large, subdued patches keep the flat-colour map readable at tactical zoom.
	for i in range(46):
		var center := Vector2(110 + (i * 787) % 3840, 90 + (i * 463) % 2850)
		var radius := Vector2(70 + (i * 29) % 110, 35 + (i * 17) % 60)
		var patch := PackedVector2Array()
		for corner in range(10):
			var angle: float = float(corner) * TAU / 10.0
			patch.append(center + Vector2(cos(angle), sin(angle)) * radius * (0.85 + 0.15 * sin(float(i + corner * 3))))
		draw_colored_polygon(patch, Color(0.39, 0.43, 0.32, 0.1) if i % 2 == 0 else Color(0.66, 0.67, 0.48, 0.11))
	for area in [Rect2i(9, 0, 9, 20), Rect2i(43, 0, 9, 20), Rect2i(0, 18, 15, 7)]:
		draw_rect(Rect2(Vector2(area.position) * GRID, Vector2(area.size) * GRID), Color("92947c"))
		var road: Rect2 = Rect2(Vector2(area.position) * GRID, Vector2(area.size) * GRID)
		for offset in [-0.22, 0.22]:
			var middle: Vector2 = road.get_center()
			if area.size.y > area.size.x:
				draw_line(Vector2(middle.x + road.size.x * offset, road.position.y), Vector2(middle.x + road.size.x * offset, road.end.y), Color(0.39, 0.4, 0.31, 0.12), 13, true)
			else:
				draw_line(Vector2(road.position.x, middle.y + road.size.y * offset), Vector2(road.end.x, middle.y + road.size.y * offset), Color(0.39, 0.4, 0.31, 0.12), 13, true)
	var apron := Rect2(23 * GRID, 27 * GRID, 22 * GRID, 17 * GRID)
	draw_rect(apron, Color("a8ae99"))
	draw_line(apron.position + Vector2(2, 2), Vector2(apron.end.x, apron.position.y) + Vector2(-2, 2), Color("c0c4ab"), 3)
	draw_line(Vector2(apron.end.x, apron.position.y), apron.end, Color(0.28, 0.35, 0.3, 0.16), 5)
	draw_rect(apron, Color("949e85"), false, 2)
	for x in range(25, 46, 2):
		draw_line(Vector2(x * GRID, 27 * GRID), Vector2(x * GRID, 44 * GRID), Color(0.37, 0.4, 0.34, 0.06), 1)
	for y in range(29, 45, 2):
		draw_line(Vector2(23 * GRID, y * GRID), Vector2(45 * GRID, y * GRID), Color(0.37, 0.4, 0.34, 0.06), 1)
	# Sparse accents avoid the roads, weapon positions and logistics apron.
	for spot in GRASS_SPOTS:
		var point := Vector2(spot.x, spot.y) * GRID
		draw_texture_rect(grass, Rect2(point - Vector2(32, 50) * spot.z, Vector2.ONE * GRID * spot.z), false, Color(1, 1, 1, 0.72))
	for spot in STONE_SPOTS:
		var size := Vector2.ONE * GRID * spot.z
		_prop(15, Rect2(Vector2(spot.x, spot.y) * GRID - size * 0.5, size), Color(0.8, 0.86, 0.78, 0.78))
	var med := Rect2(38 * GRID, 39 * GRID, 6 * GRID, 4 * GRID)
	draw_rect(med, Color("8a9d8a"))
	draw_rect(med.grow(-6), Color("bec7a5"), false, 3)
	for point in world.medical_slots:
		_prop(14, Rect2(point * GRID - Vector2(30, 24), Vector2(60, 48)))
	draw_string(font, Vector2(38 * GRID + 10, 39 * GRID + 28), "战地救护", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("ececd9"))
	draw_string(font, Vector2(24 * GRID, 28 * GRID), "弹药补给", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("e8e6cf"))
	draw_rect(Rect2(1, 1, 4094, 3070), Color("555e49"), false, 5)

func _prop(index: int, destination: Rect2, tint: Color = Color.WHITE) -> void:
	if props == null: return
	var cell: Vector2 = props.get_size() / 4.0
	draw_texture_rect_region(props, destination, Rect2(Vector2(index % 4, int(index / 4)) * cell, cell), tint)
