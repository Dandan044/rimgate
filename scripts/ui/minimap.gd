extends Control

var screen: Node

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	if screen == null: return
	draw_style_box(screen._style(Color("24352f"), Color("59705b"), 8, 8), Rect2(Vector2.ZERO, size))
	var rect: Rect2 = Rect2(12, 28, size.x - 24, size.y - 40)
	draw_rect(rect, Color("727d66"))
	var scale_factor: Vector2 = rect.size / Vector2(64, 48)
	for b in screen.world.buildings:
		var block: Rect2 = Rect2(rect.position + Vector2(b.rect.position) * scale_factor, Vector2(b.rect.size) * scale_factor)
		draw_rect(block.grow(1), Color("3b524b") if b.destroyed else (Color("b5eedc") if b.kind == "core" else Color("ded1a7")))
	for u in screen.world.units:
		if u.dead: continue
		var point: Vector2 = rect.position + u.pos * scale_factor
		draw_circle(point, 2.8 if u.team == 0 else 2.2, Color("c7f7dc") if u.team == 0 else Color("f2a47c"))
	var viewport_size: Vector2 = screen.get_viewport_rect().size / screen.camera.zoom / 64.0
	var view_rect: Rect2 = Rect2(rect.position + (screen.camera.position / 64.0 - viewport_size * 0.5) * scale_factor, viewport_size * scale_factor)
	draw_rect(view_rect.intersection(rect), Color(0.85, 0.98, 0.83, 0.8), false, 1.2)
	draw_string(screen.ui_font, Vector2(13, 19), "战术地图 · 点击定位", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c0d9bd"))
	for point in [Vector2(13, 1), Vector2(47, 1), Vector2(1, 21)]:
		draw_circle(rect.position + point * scale_factor, 3.5, Color("e6b875"))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var rect: Rect2 = Rect2(12, 28, size.x - 24, size.y - 40)
		if rect.has_point(event.position):
			screen.camera.position = (event.position - rect.position) / rect.size * Vector2(64, 48) * 64
			screen._clamp_camera()
			accept_event()
