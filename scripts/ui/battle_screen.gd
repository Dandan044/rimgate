extends Node2D

const World = preload("res://scripts/sim/world.gd")
const Config = preload("res://scripts/sim/battle_config.gd")
const WorldView = preload("res://scripts/ui/world_view.gd")
const MinimapView = preload("res://scripts/ui/minimap.gd")
const WeaponPose = preload("res://scripts/sim/weapon_pose.gd")
const GRID: float = 64.0
const INK: Color = Color("1c2929")
const TEXT: Color = Color("e8edda")
const MUTED: Color = Color("a5b8aa")
const ACCENT: Color = Color("9cdbbf")

var world = World.new()
var selected: Array[int] = []
var selected_building: int = -1
var inspected_enemy: int = -1
var hover_enemy: int = -1
var last_hover_enemy: int = -1
var aim_station: int = -1
var camera: Camera2D
var view: Node2D
var hud: Control
var top: PanelContainer
var bottom: PanelContainer
var inspector: PanelContainer
var minimap: Control
var state_label: Label
var timer_label: Label
var core_label: Label
var wave_label: Label
var title_label: Label
var combat_state_label: Label
var combat_progress: ProgressBar
var alert_button: Button
var info_label: RichTextLabel
var selection_label: Label
var toast_label: Label
var start_button: Button
var pause_button: Button
var fire_button: Button
var draft_button: Button
var posture_option: OptionButton
var style_option: OptionButton
var unit_buttons: Array[Button] = []
var health_bars: Array[ProgressBar] = []
var popup: PopupMenu
var popup_actions: Dictionary = {}
var pause_overlay: Control
var result_overlay: Control
var result_label: RichTextLabel
var last_event_serial: int = 0
var toast_time: float = 0.0
var refresh_time: float = 0.0
var drag_start: Vector2
var drag_current: Vector2
var selecting: bool = false
var panning: bool = false
var audio_streams: Dictionary = {}
var audio_players: Array[AudioStreamPlayer2D] = []
var sound_index: int = 0
var pending_sounds: Array[Dictionary] = []
var voice_priority: Dictionary = {}
var voice_age: Dictionary = {}
var last_right_event: int = -1
var popup_revision: int = 0
var step_audio_at: Dictionary = {}
var reload_active: Dictionary = {}
var ui_font: Font
var review_capture_path: String = ""
var review_time: float = -1.0
var review_quit: bool = false
var review_captured: bool = false
var review_wait: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Context menus use the same viewport coordinates as tactical input, including
	# stretched windows and Windows display scaling.
	get_viewport().gui_embed_subwindows = true
	RenderingServer.set_default_clear_color(Color("172423"))
	ui_font = load("res://assets/fonts/NotoSansCJKsc-Regular.otf") if ResourceLoader.exists("res://assets/fonts/NotoSansCJKsc-Regular.otf") else ThemeDB.fallback_font
	camera = Camera2D.new()
	camera.position = Vector2(32, 33) * GRID
	camera.zoom = Vector2.ONE * 0.42
	add_child(camera)
	var listener := AudioListener2D.new()
	camera.add_child(listener)
	listener.make_current()
	view = WorldView.new()
	view.screen = self
	view.world = world
	add_child(view)
	_build_hud()
	_load_audio()
	get_viewport().size_changed.connect(_layout_hud)
	_layout_hud()
	_sync_pause()
	_refresh_hud()
	_parse_review_args()
	if world.phase == "preparing":
		show_toast("准备阶段：右键工事安排人员，点击“开始防守”推进。", 7)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-mode="):
			var qa_script = load("res://scripts/qa/runtime_check.gd")
			if qa_script != null:
				var qa_node = qa_script.new()
				add_child(qa_node)
				qa_node.setup(self)
			break

func _physics_process(_delta: float) -> void:
	if world.phase == "running":
		world.step(Config.FIXED_DT)
		view.tick(Config.FIXED_DT)
		_sync_pause()

func _process(delta: float) -> void:
	var movement: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): movement.y -= 1
	if Input.is_physical_key_pressed(KEY_S): movement.y += 1
	if Input.is_physical_key_pressed(KEY_A): movement.x -= 1
	if Input.is_physical_key_pressed(KEY_D): movement.x += 1
	if not movement.is_zero_approx():
		camera.position += movement.normalized() * 700 * delta / camera.zoom.x
		_clamp_camera()
	hover_enemy = -1
	if not _over_hud(get_viewport().get_mouse_position()):
		var hovered: Dictionary = _pick_unit(mouse_world())
		if not hovered.is_empty() and int(hovered.team) == 1:
			hover_enemy = int(hovered.id)
			last_hover_enemy = hover_enemy
	_check_events()
	toast_time = maxf(0, toast_time - delta)
	toast_label.visible = toast_time > 0
	refresh_time += delta
	if refresh_time >= 0.1:
		refresh_time = 0
		_refresh_hud()
	view.advance_display(delta)
	_flush_sounds(delta)
	view.queue_redraw()
	minimap.queue_redraw()
	if review_capture_path != "" and not review_captured:
		review_wait += delta
		if review_wait > 0.5 and (review_time < 0 or world.time_s >= review_time):
			review_captured = true
			capture_review_frame(review_capture_path)

func _input(event: InputEvent) -> void:
	# Receive tactical right clicks before an open context menu consumes them.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_dispatch_right_click(event.position, event.get_instance_id())

func _popup_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		popup.set_input_as_handled()
		if event.pressed: _dispatch_right_click(event.position + Vector2(popup.position), event.get_instance_id())

func _dispatch_right_click(point: Vector2, event_id: int) -> void:
	if event_id == last_right_event: return
	last_right_event = event_id
	if _over_hud(point) or pause_overlay.visible or result_overlay.visible: return
	popup.hide()
	popup_revision += 1
	popup_actions.clear()
	aim_station = -1
	selecting = false
	_right_click(viewport_to_grid(point), point)
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_pause()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if aim_station >= 0:
				aim_station = -1
				show_toast("已取消轰击瞄点")
			else:
				_open_pause_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			_begin_fire()
		elif event.keycode == KEY_X:
			_send("stop")
		elif event.keycode == KEY_1 or event.keycode == KEY_2 or event.keycode == KEY_3 or event.keycode == KEY_4 or event.keycode == KEY_5 or event.keycode == KEY_6:
			_select_unit(int(event.keycode - KEY_0), event.shift_pressed)
	if event is InputEventMouseButton:
		var mouse: Vector2 = event.position
		var grid_point: Vector2 = viewport_to_grid(mouse)
		if OS.get_cmdline_user_args().has("--qa-mode=input") and event.pressed:
			print("UI_INPUT button=", event.button_index, " viewport=", mouse, " grid=", grid_point, " live_cursor=", get_viewport().get_mouse_position(), " over_hud=", _over_hud(mouse))
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(mouse, 1.13)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(mouse, 1.0 / 1.13)
			return
		if _over_hud(mouse) or pause_overlay.visible or result_overlay.visible:
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_dispatch_right_click(mouse, event.get_instance_id())
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if aim_station >= 0:
					_fire_at(grid_point)
					return
				drag_start = mouse
				drag_current = mouse
				selecting = true
			elif selecting:
				selecting = false
				_finish_selection(mouse, event.shift_pressed)
	if event is InputEventMouseMotion:
		if panning:
			camera.position -= event.relative / camera.zoom
			_clamp_camera()
		if selecting:
			drag_current = event.position
			hud.queue_redraw()

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud_overlay)
	layer.add_child(hud)
	var theme: Theme = Theme.new()
	theme.default_font = ui_font
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color("ffffff"))
	theme.set_color("font_disabled_color", "Button", Color("65746a"))
	theme.set_stylebox("normal", "Button", _style(Color("31443d"), Color("53695b"), 6))
	theme.set_stylebox("hover", "Button", _style(Color("48604e"), ACCENT, 6))
	theme.set_stylebox("pressed", "Button", _style(Color("5a7660"), Color("c1ebcf"), 6))
	theme.set_stylebox("disabled", "Button", _style(Color("26372f"), Color("3e4e42"), 6))
	theme.set_stylebox("panel", "PopupMenu", _style(INK, Color("6c8975"), 8))
	theme.set_stylebox("normal", "OptionButton", _style(Color("31443d"), Color("53695b"), 6))
	theme.set_stylebox("hover", "OptionButton", _style(Color("48604e"), ACCENT, 6))
	hud.theme = theme
	top = _panel(hud)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	top.add_child(row)
	var brand: VBoxContainer = VBoxContainer.new()
	row.add_child(brand)
	var name_label: Label = _label("RIMGATE", 22, ACCENT)
	brand.add_child(name_label)
	brand.add_child(_label("防线试验  /  COMBAT DEMO", 11, MUTED))
	state_label = _label("准备部署", 16, TEXT)
	row.add_child(state_label)
	timer_label = _label("00:00 / 08:00", 20, TEXT)
	row.add_child(timer_label)
	core_label = _label("设施 1000 / 1000", 16, ACCENT)
	row.add_child(core_label)
	wave_label = _label("第 1 波 · 00:30", 14, MUTED)
	wave_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(wave_label)
	start_button = _button("开始防守", _start, "pause")
	row.add_child(start_button)
	pause_button = _button("暂停 [Space]", _toggle_pause, "pause")
	row.add_child(pause_button)
	row.add_child(_button("菜单", _open_pause_menu))
	bottom = _panel(hud)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	bottom.add_child(stack)
	var people: HBoxContainer = HBoxContainer.new()
	people.add_theme_constant_override("separation", 8)
	stack.add_child(people)
	for id in range(1, 7):
		var card: Button = _button("%02d\n待命" % id, _unit_card_pressed.bind(id))
		card.custom_minimum_size = Vector2(112, 62)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		people.add_child(card)
		unit_buttons.append(card)
		var health := ProgressBar.new()
		health.show_percentage = false
		health.mouse_filter = Control.MOUSE_FILTER_IGNORE
		health.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		health.offset_left = 9; health.offset_right = -9
		health.offset_top = -7; health.offset_bottom = -4
		health.add_theme_stylebox_override("background", _style(Color("1d2c29"), Color.TRANSPARENT, 2, 0))
		health.add_theme_stylebox_override("fill", _style(Color("8ac6a9"), Color.TRANSPARENT, 2, 0))
		card.add_child(health)
		health_bars.append(health)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	stack.add_child(actions)
	selection_label = _label("请选择守军", 14, MUTED)
	selection_label.custom_minimum_size.x = 110
	actions.add_child(selection_label)
	draft_button = _button("解除征召", _toggle_draft)
	actions.add_child(draft_button)
	actions.add_child(_button("停止 [X]", _stop, "stop"))
	posture_option = OptionButton.new()
	posture_option.focus_mode = Control.FOCUS_NONE
	posture_option.custom_minimum_size = Vector2(124, 36)
	for text in ["自动姿态", "站立", "蹲伏", "卧倒"]: posture_option.add_item(text)
	for index in range(1, 4):
		posture_option.set_item_icon(index, load("res://assets/icons/%s.svg" % ["stand", "crouch", "prone"][index - 1]))
	posture_option.item_selected.connect(func(index: int) -> void: _send("posture", {"value": index - 1}))
	actions.add_child(posture_option)
	style_option = OptionButton.new()
	style_option.focus_mode = Control.FOCUS_NONE
	style_option.custom_minimum_size = Vector2(124, 36)
	for text in ["压制作战", "常规作战", "谨慎作战"]: style_option.add_item(text)
	style_option.select(1)
	for index in range(3):
		style_option.set_item_icon(index, load("res://assets/icons/%s.svg" % ["suppress", "normal", "cautious"][index]))
	style_option.item_selected.connect(func(index: int) -> void: _send("style", {"value": index}))
	actions.add_child(style_option)
	fire_button = _button("轰击 [F]", _begin_fire, "attack")
	actions.add_child(fire_button)
	var instruction: Label = _label("左键 / 框选  ·  Shift 增选  ·  右键移动 / 操控 / 救援  ·  WASD / 中键拖动  ·  滚轮缩放", 13, MUTED)
	stack.add_child(instruction)
	alert_button = _button("", _locate_alert)
	alert_button.custom_minimum_size.y = 24
	alert_button.add_theme_font_size_override("font_size", 13)
	alert_button.visible = false
	stack.add_child(alert_button)
	inspector = _panel(hud)
	var detail: VBoxContainer = VBoxContainer.new()
	detail.add_theme_constant_override("separation", 8)
	inspector.add_child(detail)
	title_label = _label("守住核心设施", 19, ACCENT)
	detail.add_child(title_label)
	combat_state_label = _label("战场待命", 16, Color("d4dcbe"))
	detail.add_child(combat_state_label)
	combat_progress = ProgressBar.new()
	combat_progress.show_percentage = false
	combat_progress.custom_minimum_size.y = 5
	combat_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_progress.add_theme_stylebox_override("background", _style(Color("162724"), Color.TRANSPARENT, 2, 0))
	combat_progress.add_theme_stylebox_override("fill", _style(ACCENT, Color.TRANSPARENT, 2, 0))
	detail.add_child(combat_progress)
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = false
	info_label.scroll_active = false
	info_label.custom_minimum_size = Vector2(0, 210)
	info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_label.add_theme_color_override("default_color", TEXT)
	info_label.add_theme_font_size_override("normal_font_size", 14)
	detail.add_child(info_label)
	minimap = MinimapView.new()
	minimap.screen = self
	minimap.custom_minimum_size = Vector2(300, 225)
	hud.add_child(minimap)
	toast_label = _label("", 16, Color("f3dfad"))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(toast_label)
	popup = PopupMenu.new()
	popup.theme = theme
	popup.exclusive = false
	popup.id_pressed.connect(_popup_pressed)
	popup.window_input.connect(_popup_input)
	add_child(popup)
	pause_overlay = _make_modal("指挥暂停", false)
	result_overlay = _make_modal("守卫结果", true)

func _make_modal(title: String, result: bool) -> Control:
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0.035, 0.07, 0.065, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	hud.add_child(overlay)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel: PanelContainer = _panel(center)
	panel.custom_minimum_size = Vector2(510, 370 if result else 240)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	box.add_child(_label(title, 26, ACCENT))
	if result:
		result_label = RichTextLabel.new()
		result_label.bbcode_enabled = true
		result_label.fit_content = true
		result_label.custom_minimum_size.y = 195
		box.add_child(result_label)
	else:
		box.add_child(_label("世界时间已冻结。可以继续调整命令与镜头。", 15, MUTED))
		box.add_child(_button("返回战场", func() -> void: pause_overlay.hide()))
	box.add_child(_button("重新部署", _restart))
	box.add_child(_button("退出游戏", func() -> void: get_tree().quit()))
	return overlay

func _panel(parent: Node) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("20302d"), Color("4c6355"), 8, 14))
	parent.add_child(panel)
	return panel

func _style(fill: Color, border: Color, radius: int = 6, margin: int = 10) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

func _button(text: String, callback: Callable, icon_name: String = "") -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 35
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	if icon_name != "" and ResourceLoader.exists("res://assets/icons/%s.svg" % icon_name):
		button.icon = load("res://assets/icons/%s.svg" % icon_name)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 18)
	return button

func _label(text: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _layout_hud() -> void:
	var size: Vector2 = get_viewport_rect().size
	top.position = Vector2(12, 10)
	top.size = Vector2(size.x - 24, 66)
	bottom.position = Vector2(12, size.y - 218)
	bottom.size = Vector2(size.x - 354, 206)
	inspector.position = Vector2(size.x - 330, 88)
	inspector.size = Vector2(318, 360)
	minimap.position = Vector2(size.x - 330, size.y - 254)
	minimap.size = Vector2(318, 242)
	toast_label.position = Vector2(20, size.y - 252)
	toast_label.size = Vector2(size.x - 374, 28)
	if size.x < 1420:
		for card in unit_buttons:
			card.custom_minimum_size.x = 92
		selection_label.custom_minimum_size.x = 75
		posture_option.custom_minimum_size.x = 110
		style_option.custom_minimum_size.x = 110

func _refresh_hud() -> void:
	var phase_name: Dictionary = {"preparing": "准备部署", "running": "防守进行中", "paused": "指挥暂停", "won": "守卫成功", "lost": "防线失守"}
	state_label.text = phase_name.get(world.phase, world.phase)
	# Fixed-step accumulation may reach 480 as 479.999999999892.
	var elapsed_seconds := int(floor(world.time_s + 0.000001))
	timer_label.text = "%02d:%02d / 08:00" % [elapsed_seconds / 60, elapsed_seconds % 60]
	var core: Dictionary = world.core()
	core_label.text = "设施 %d / %d" % [int(maxf(0, core.hp)), int(core.max_hp)]
	if world.next_wave < Config.WAVE_TIMES.size():
		var remaining: int = maxi(0, int(ceil(Config.WAVE_TIMES[world.next_wave] - world.time_s)))
		var direction: String = ["北侧 A", "北侧 A/B · 西侧 C", "北侧 A/B · 西侧 C · 重装"][world.next_wave]
		wave_label.text = "第 %d 波 · %02d:%02d" % [world.next_wave + 1, remaining / 60, remaining % 60]
		if remaining <= 15: wave_label.text += "  " + direction
	else:
		wave_label.text = "最终攻势 · 坚持至 08:00"
	start_button.visible = world.phase == "preparing"
	pause_button.visible = world.phase != "preparing"
	pause_button.text = "继续 [Space]" if world.phase == "paused" else "暂停 [Space]"
	pause_button.disabled = world.phase in ["won", "lost"]
	selection_label.text = "%d 人已选中" % selected.size() if not selected.is_empty() else "请选择守军"
	draft_button.disabled = selected.is_empty()
	if not selected.is_empty():
		var u: Dictionary = world.entity(selected[0])
		if not u.is_empty():
			draft_button.text = "解除征召" if bool(_projected_value(int(u.id), "draft", u.drafted)) else "征召"
			posture_option.select(int(_projected_value(int(u.id), "posture", u.posture_mode)) + 1)
			style_option.select(int(_projected_value(int(u.id), "style", u.style)))
	posture_option.disabled = selected.is_empty()
	style_option.disabled = selected.is_empty()
	fire_button.disabled = _selected_mortar() < 0
	for i in range(unit_buttons.size()):
		var u: Dictionary = world.entity(i + 1)
		if u.is_empty(): continue
		var status: String = "阵亡" if u.dead else ("昏迷" if not u.conscious else String(u.status))
		var weapon_holder: Dictionary = _display_weapon_holder(u)
		if u.conscious and not u.dead and u.job == "operate" and u.stage == "station": status = String(weapon_holder.get("status", status))
		var ready_ammo: int = int(weapon_holder.get("loaded", 0))
		if weapon_holder.get("kind", "") == "mortar": ready_ammo += int(weapon_holder.get("ammo", 0))
		var pending: String = ""
		for order in world.pending_orders:
			if order.ids.has(i + 1): pending = " · 待执行"
		unit_buttons[i].text = "%02d  %d%%  · %d发\n%s%s" % [i + 1, int(maxf(0, u.hp) / u.max_hp * 100), ready_ammo, status, pending]
		health_bars[i].value = maxf(0, u.hp) / u.max_hp * 100
		var icon_name: String = ""
		if not u.conscious and not u.dead: icon_name = "downed"
		elif u.job == "rout": icon_name = "rout"
		elif float(u.bleed_rate) > 0: icon_name = "bleed"
		elif "阻" in String(u.status): icon_name = "blocked"
		unit_buttons[i].icon = load("res://assets/icons/%s.svg" % icon_name) if icon_name != "" else null
		unit_buttons[i].modulate = Color("b8efd2") if selected.has(i + 1) else (Color("8a8d80") if u.dead else Color.WHITE)
		unit_buttons[i].tooltip_text = "%s %d + %d  /  绷带 %d  /  压制 %d\n%s" % ["步枪" if weapon_holder.has("team") else String(weapon_holder.name), int(weapon_holder.loaded), int(weapon_holder.get("ammo", weapon_holder.get("reserve", 0))), int(u.bandages), int(u.suppression), u.status]
	for holder in world.units + world.buildings:
		var reloading: bool = float(holder.get("reload_progress", 0.0)) > 0
		if reloading and not reload_active.get(int(holder.id), false):
			var name: String = "reload_mg_01" if holder.get("kind", "") == "mg" else ("mortar_load_01" if holder.get("kind", "") == "mortar" else "reload")
			_play_sound(name, -19, holder.pos, 2)
		reload_active[int(holder.id)] = reloading
	var critical: Dictionary = _critical_unit()
	alert_button.visible = not critical.is_empty()
	if not critical.is_empty():
		alert_button.text = "⚠ %02d · %s  [点击定位]" % [int(critical.id), "伤员持续出血" if critical.bleed_rate > 0 else ("昏迷等待救援" if not critical.conscious else "弹药耗尽")]
	_refresh_inspector()
	if world.phase in ["won", "lost"]:
		result_overlay.show()
		var awake: int = 0
		var down: int = 0
		var dead: int = 0
		for u in world.units:
			if int(u.team) != 0: continue
			if u.dead: dead += 1
			elif u.conscious: awake += 1
			else: down += 1
		result_label.text = "[font_size=25][color=%s]%s[/color][/font_size]\n\n%s\n守卫时间  %02d:%02d\n核心耐久  %d / 1000\n清醒 %d   昏迷 %d   阵亡 %d\n步枪弹 %d   机枪弹 %d   炮弹 %d\n同阵营误伤（双方） %d" % ["#b9e2c2" if world.phase == "won" else "#edae91", "守卫成功" if world.phase == "won" else "防线失守", world.result_reason, elapsed_seconds / 60, elapsed_seconds % 60, maxi(0, int(core.hp)), awake, down, dead, int(world.stats.rifle_shots), int(world.stats.mg_shots), int(world.stats.mortar_shots), int(world.stats.friendly_fire)]

func _refresh_inspector() -> void:
	var b: Dictionary = world.entity(selected_building) if selected_building >= 0 else {}
	if not b.is_empty():
		title_label.text = String(b.name)
		_refresh_combat_status(b)
		var crew: Array[int] = world.projected_crew(int(b.id))
		info_label.text = "耐久  [color=#b4dfbd]%d / %d[/color]\n" % [maxi(0, int(b.hp)), int(b.max_hp)]
		if int(b.capacity) > 0:
			info_label.text += "岗位  %d / %d  %s\n状态  %s\n" % [crew.size(), int(b.capacity), str(crew), b.status]
			info_label.text += "弹药  %d 已装 / %d 备用\n" % [int(b.loaded), int(b.ammo)] if b.kind == "mg" else "炮弹库存  %d / %d\n" % [int(b.ammo), int(b.ammo_capacity)]
			info_label.text += "待交付预约  %d\n\n" % int(b.supply_reserved)
			info_label.text += "右键工事：操控 / 搬运补给\n右键敌人：指定工事目标\n" + ("按 F 指定地面落点\n单次命令发射一枚炮弹" if b.kind == "mortar" else "固定射界 120°，枪身随目标转向")
		else:
			if b.get("barrier_type", "") == "wall": info_label.text += "墙体 · 完全阻挡直射\n禁止穿行和翻越\n\n"
			else: info_label.text += "高度  %.2f  /  单格屏蔽量 %.2f\n\n" % [float(b.height), float(b.get("screening_strength", b.screen_volume * 4.0))]
			info_label.text += "耐久归零后失去遮挡与掩护。\n右键可以显式攻击建筑。"
		return
	var u: Dictionary = world.entity(selected[0]) if not selected.is_empty() else world.entity(inspected_enemy)
	if not u.is_empty():
		_refresh_combat_status(u)
		title_label.text = ("守军 %02d" % int(u.id)) if int(u.team) == 0 else ("重装步兵" if u.kind == "heavy" else ("侧翼队员" if u.kind == "flanker" else "敌方射手"))
		var pose: String = ["站立", "蹲伏", "卧倒"][clampi(int(u.posture), 0, 2)]
		info_label.text = "生命  [color=#b4dfbd]%d / %d[/color]\n压制  %d / 100  ·  稳定 %d%%\n姿态  %s  ·  %s\n步枪  %d / %d 发\n出血  [color=#e8b296]%.2f / 秒[/color]\n绷带  %d  ·  护甲 %.0f\n当前  %s\n" % [maxi(0, int(u.hp)), int(u.max_hp), int(u.suppression), int(u.stability * 100), pose, "自动" if int(u.posture_mode) < 0 else "锁定", int(u.loaded), int(u.reserve), float(u.bleed_rate), int(u.bandages), float(u.armor), u.status]
		var holder: Dictionary = _display_weapon_holder(u)
		if int(holder.id) != int(u.id):
			info_label.text = info_label.text.replace("步枪  %d / %d 发" % [int(u.loaded), int(u.reserve)], "%s  %d + %d 发" % [String(holder.name), int(holder.loaded), int(holder.ammo)])
		if hover_enemy >= 0 and int(u.team) == 0:
			var foe: Dictionary = world.entity(hover_enemy)
			var cover: Dictionary = world.cover_for(u, Vector2(WeaponPose.aimed_rifle(foe.pos, u.pos, int(foe.posture)).muzzle))
			info_label.text += "\n来自悬停敌人的保护：\n" + ("完全遮挡" if cover.get("blocked", false) else "掩体拦截 %d%%" % int(float(cover.get("chance", 0)) * 100))
		else:
			info_label.text += "\n悬停敌人查看对应方向掩护。\n征召单位不会自行换位找掩体。"
		return
	title_label.text = "守住核心设施"
	combat_state_label.text = "实时战斗 · 随时暂停指挥"
	combat_progress.visible = false
	info_label.text = "[color=#b7d5bd]6 人 · 2 挺机枪 · 1 门迫击炮[/color]\n\n所有设施已经预置。安排人员操作重武器，及时从补给点搬弹；救人和止血同样占用人手。\n\n坚持 8 分钟即可完成守卫。\n\n[color=#e4bb87]炮击和流弹能够伤害友军。[/color]\n救护区药品：%d" % int(world.medical_stock)

func _display_weapon_holder(unit: Dictionary) -> Dictionary:
	if unit.get("job", "") == "operate":
		var station: Dictionary = world.entity(int(unit.get("station_id", -1)))
		if not station.is_empty(): return station
	return unit

func _refresh_combat_status(source: Dictionary) -> void:
	var holder: Dictionary = _display_weapon_holder(source) if source.has("team") else source
	var state: String = String(holder.get("weapon_state", "idle"))
	var labels := {"idle": "待命", "aiming": "瞄准", "firing": "射击", "recovering": "射后恢复", "reloading": "装填", "blocked": "目标受阻"}
	combat_state_label.text = String(labels.get(state, state)) + "  ·  " + String(holder.get("status", ""))
	var target: Dictionary = world.entity(int(holder.get("target_id", -1)))
	if not target.is_empty(): combat_state_label.text += "\n锁定目标 %s" % String(target.get("name", target.id))
	combat_progress.visible = state in ["aiming", "reloading"] or holder.get("stage", "") == "treatment"
	var progress: float = float(holder.get("aim_fraction", 0.0))
	if state == "reloading": progress = float(holder.get("reload_progress", 0.0)) / (5.0 if holder.get("kind", "") == "mg" else (10.0 if holder.get("kind", "") == "mortar" else 3.0))
	if holder.get("stage", "") == "treatment": progress = float(holder.get("job_timer", 0.0)) / 6.0
	combat_progress.value = clampf(progress, 0, 1) * 100.0

func _critical_unit() -> Dictionary:
	var best: Dictionary = {}
	var score: float = 0.0
	for unit in world.units:
		if unit.team != 0 or unit.dead: continue
		var holder: Dictionary = _display_weapon_holder(unit)
		var empty: bool = int(holder.loaded) == 0 and int(holder.get("reserve", holder.get("ammo", 0))) == 0
		var urgency: float = (1000.0 if not unit.conscious else 0.0) + float(unit.bleed_rate) * 100.0 + (20.0 if empty else 0.0)
		if urgency > score: score = urgency; best = unit
	return best

func _locate_alert() -> void:
	var unit: Dictionary = _critical_unit()
	if not unit.is_empty(): _unit_card_pressed(int(unit.id))

func mouse_world() -> Vector2:
	return get_global_mouse_position() / GRID

func _pick_unit(point: Vector2) -> Dictionary:
	var nearest: Dictionary = {}
	var distance: float = 0.72
	for u in world.units:
		if int(u.get("carrier_id", -1)) >= 0: continue
		var d: float = view.unit_position(u).distance_to(point)
		if d < distance:
			distance = d
			nearest = u
	return nearest

func _pick_building(point: Vector2) -> Dictionary:
	for b in world.buildings:
		if Rect2(b.rect).has_point(point) and not b.destroyed:
			return b
	return {}

func _finish_selection(mouse: Vector2, additive: bool) -> void:
	var grid_point: Vector2 = viewport_to_grid(mouse)
	if not additive:
		selected.clear()
		selected_building = -1
		inspected_enemy = -1
	if drag_start.distance_to(mouse) > 7:
		var box: Rect2 = Rect2(drag_start, mouse - drag_start).abs()
		for u in world.units:
			if int(u.team) == 0 and not u.dead and box.has_point(get_viewport().get_canvas_transform() * (view.unit_position(u) * GRID)):
				if not selected.has(int(u.id)): selected.append(int(u.id))
	else:
		var u: Dictionary = _pick_unit(grid_point)
		if not u.is_empty():
			if int(u.team) == 0:
				if additive and selected.has(int(u.id)): selected.erase(int(u.id))
				else: selected.append(int(u.id))
			else: inspected_enemy = int(u.id)
		else:
			var b: Dictionary = _pick_building(grid_point)
			if not b.is_empty(): selected_building = int(b.id)
	_refresh_hud()
	hud.queue_redraw()

func _select_unit(id: int, additive: bool = false) -> void:
	if not additive: selected.clear()
	if not selected.has(id): selected.append(id)
	selected_building = -1
	inspected_enemy = -1
	_refresh_hud()

func _unit_card_pressed(id: int) -> void:
	_select_unit(id, Input.is_key_pressed(KEY_SHIFT))
	var u: Dictionary = world.entity(id)
	if not u.is_empty():
		camera.position = u.pos * GRID
		_clamp_camera()

func _right_click(point: Vector2, screen_point: Vector2) -> void:
	popup.hide()
	popup_revision += 1
	popup_actions.clear()
	var u: Dictionary = _pick_unit(point)
	if not u.is_empty():
		if int(u.team) == 1:
			var chosen_station: Dictionary = world.entity(selected_building)
			if not chosen_station.is_empty() and int(chosen_station.get("capacity", 0)) > 0:
				var response: Dictionary = world.submit_station_attack(selected_building, int(u.id))
				show_toast("工事攻击命令已安排" if response.get("ok", false) else String(response.get("reason", "工事无法攻击")), 3)
				if response.get("ok", false): _play_sound("order")
				_refresh_hud()
				return
			for id in selected:
				var friendly: Dictionary = world.entity(id)
				var station: Dictionary = world.entity(int(friendly.station_id))
				if not station.is_empty() and station.kind == "mortar":
					show_toast("请先选中迫击炮，再右键敌人；F可轰击地面")
					return
			_send("attack", {"target_id": u.id})
		else:
			popup.clear(); popup_actions.clear()
			_menu_item("现场急救", "treat", {"target_id": u.id}, u.dead or selected.is_empty(), "需要一名清醒人员和绷带")
			if not u.conscious and not u.dead:
				_menu_item("救援至救护区", "rescue", {"target_id": u.id}, selected.is_empty(), "搬运期间不能开火，伤员仍会出血")
			_show_popup(screen_point)
		return
	var b: Dictionary = _pick_building(point)
	if not b.is_empty():
		selected_building = int(b.id)
		popup.clear(); popup_actions.clear()
		if int(b.capacity) > 0:
			var crew: Array[int] = world.projected_crew(int(b.id))
			_menu_item("操控 %s（%d/%d）" % [b.name, crew.size(), int(b.capacity)], "operate", {"target_id": b.id}, crew.size() >= int(b.capacity) or selected.is_empty(), "岗位已满" if crew.size() >= int(b.capacity) else "安排选中人员加入岗位")
			_menu_item("搬运一箱补给", "resupply", {"target_id": b.id}, selected.is_empty(), "安排一名选中人员从补给点搬运相应弹药")
			if b.kind == "mortar":
				_menu_item("轰击地面 [F]", "aim", {"target_id": b.id}, crew.is_empty(), "需要已安排的炮手")
		_menu_item("攻击建筑", "attack", {"target_id": b.id}, selected.is_empty(), "也可以攻击己方建筑，请注意误伤")
		_refresh_hud()
		_show_popup(screen_point)
		return
	selected_building = -1
	_send("move", {"position": Vector2(Vector2i(point.floor())) + Vector2.ONE * 0.5})

func _menu_item(text: String, kind: String, data: Dictionary, disabled: bool, tooltip: String) -> void:
	var id: int = popup.item_count
	popup.add_item(text, id)
	var icons: Dictionary = {"operate": "operate", "resupply": "move", "rescue": "rescue", "treat": "treat", "attack": "attack", "aim": "attack"}
	if icons.has(kind): popup.set_item_icon(id, load("res://assets/icons/%s.svg" % icons[kind]))
	popup.set_item_disabled(id, disabled)
	popup.set_item_tooltip(id, tooltip)
	popup_actions[id] = {"kind": kind, "data": data}

func _show_popup(point: Vector2) -> void:
	# Finish this mouse event's focus change before opening the replacement
	# embedded window. Otherwise Popup schedules a focus-loss hide of the new menu.
	_open_context_deferred.call_deferred(point, popup_revision)

func _open_context_deferred(point: Vector2, revision: int) -> void:
	if revision != popup_revision or popup_actions.is_empty(): return
	popup.position = Vector2i(point)
	popup.reset_size()
	popup.popup()

func _popup_pressed(id: int) -> void:
	if not popup_actions.has(id): return
	var action: Dictionary = popup_actions[id]
	if action.kind == "aim":
		aim_station = int(action.data.target_id)
		show_toast("左键指定轰击落点，右键取消。橙圈为冲击波，外圈为弹片危险范围。", 6)
		return
	var ids: Array[int] = selected.duplicate()
	if action.kind == "operate":
		var station: Dictionary = world.entity(int(action.data.target_id))
		var free: int = int(station.capacity) - world.projected_crew(int(station.id)).size()
		ids.clear()
		for selected_id in selected:
			if free <= 0: break
			if not world.projected_crew(int(station.id)).has(selected_id):
				ids.append(selected_id)
				free -= 1
	elif action.kind in ["resupply", "rescue", "treat"] and ids.size() > 1:
		ids = [ids[0]]
	_send(action.kind, action.data, ids)

func _send(kind: String, data: Dictionary = {}, ids: Array = []) -> bool:
	var use_ids: Array = selected if ids.is_empty() else ids
	if use_ids.is_empty():
		show_toast("请先选中一名可行动的守军")
		return false
	var response: Dictionary = world.submit(use_ids, kind, data)
	if response.get("ok", false):
		_play_sound("order")
		show_toast("命令已安排，继续后执行" if world.phase in ["preparing", "paused"] else "命令已下达", 2)
	else:
		show_toast(String(response.get("reason", "命令无法执行")), 4)
	_refresh_hud()
	return bool(response.get("ok", false))

func _selected_mortar() -> int:
	var b: Dictionary = world.entity(selected_building) if selected_building >= 0 else {}
	if not b.is_empty() and b.kind == "mortar" and not b.destroyed:
		return int(b.id)
	for id in selected:
		var station_id: int = world.projected_station_for(id)
		b = world.entity(station_id)
		if not b.is_empty() and b.kind == "mortar" and not b.destroyed: return station_id
	return -1

func has_selected_crew(station_id: int) -> bool:
	for id in selected:
		if world.projected_station_for(id) == station_id: return true
	return false

func cover_reference() -> Dictionary:
	for id in [hover_enemy, inspected_enemy, last_hover_enemy]:
		var target: Dictionary = world.entity(id)
		if not target.is_empty() and target.has("team") and not target.dead:
			return target
	return {}

func _begin_fire() -> void:
	var station_id: int = _selected_mortar()
	if station_id < 0:
		show_toast("先选中迫击炮或它的操作人员")
		return
	if world.projected_crew(station_id).is_empty():
		show_toast("请先为迫击炮安排操作人员")
		return
	aim_station = station_id
	show_toast("左键选择落点 · 右键取消 · 炮击会伤害友军", 7)

func _fire_at(point: Vector2) -> void:
	var station_id: int = aim_station
	var crew: Array[int] = world.projected_crew(station_id)
	if _send("fire", {"position": point, "target_id": station_id}, crew):
		aim_station = -1

func _stop() -> void:
	_send("stop")

func _toggle_draft() -> void:
	if selected.is_empty(): return
	var u: Dictionary = world.entity(selected[0])
	_send("draft", {"value": not bool(_projected_value(int(u.id), "draft", u.drafted))})

func _projected_value(id: int, kind: String, current: Variant) -> Variant:
	var value: Variant = current
	for order in world.pending_orders:
		if order.kind == kind and order.ids.has(id): value = order.data.get("value", value)
	return value

func _start() -> void:
	world.start_battle()
	_sync_pause()
	_refresh_hud()
	show_toast("防守已开始，按 Space 可随时暂停指挥。", 4)

func _toggle_pause() -> void:
	if world.phase == "preparing":
		show_toast("请点击“开始防守”启动战斗")
		return
	world.set_paused(world.phase != "paused")
	_sync_pause()
	_refresh_hud()

func _sync_pause() -> void:
	view.set_running(world.phase == "running")
	get_tree().paused = world.phase != "running"
	for index in range(audio_players.size()):
		audio_players[index].stream_paused = world.phase in ["preparing", "paused"] and int(voice_priority.get(index, 0)) < 5

func _open_pause_menu() -> void:
	if result_overlay.visible: return
	if pause_overlay.visible:
		pause_overlay.hide()
		return
	world.set_paused(true)
	_sync_pause()
	pause_overlay.show()

func _restart() -> void:
	for player in audio_players: player.stop()
	world.reset()
	selected.clear()
	selected_building = -1
	inspected_enemy = -1
	last_hover_enemy = -1
	aim_station = -1
	last_event_serial = 0
	view.effects.clear()
	view.visual_time = 0
	view.reset_presentation()
	reload_active.clear()
	step_audio_at.clear()
	pending_sounds.clear()
	voice_priority.clear()
	voice_age.clear()
	popup.hide()
	popup_revision += 1
	selecting = false
	panning = false
	pause_overlay.hide()
	result_overlay.hide()
	camera.position = Vector2(32, 33) * GRID
	camera.zoom = Vector2.ONE * 0.42
	_sync_pause()
	_refresh_hud()
	show_toast("已重新部署，准备阶段可以先安排岗位。", 5)

func show_toast(text: String, duration: float = 3) -> void:
	toast_label.text = text
	toast_time = duration
	toast_label.show()

func _check_events() -> void:
	for event in world.events:
		if int(event.serial) <= last_event_serial: continue
		last_event_serial = int(event.serial)
		view.on_event(event)
		match String(event.type):
			"weapon_fired":
				var kind: String = event.get("weapon_kind", event.get("kind", "rifle"))
				_queue_sound(event, "mortar" if kind == "mortar" else ("mg_%d" % (int(event.serial) % 2 + 1) if kind == "mg" else "rifle_%d" % (int(event.serial) % 2 + 1)), -15, 2)
			"explosion": _queue_sound(event, "explosion_%d" % (int(event.serial) % 2 + 1), -7, 4)
			"projectile_impact":
				var entity: Dictionary = world.entity(int(event.get("entity_id", -1)))
				var material: String = String(event.get("material", "ground"))
				var name: String = "impact"
				if material == "sandbag" or entity.get("kind", "") == "sandbag": name = "impact_sand_01"
				elif material == "concrete" or entity.get("kind", "") == "wall": name = "impact_wall_01"
				elif material in ["metal", "armor"]: name = "impact_metal_01"
				elif material == "unit": name = "hit"
				_queue_sound(event, name, -23, 1)
			"damage":
				if int(event.get("target_team", 1)) == 0 and String(event.get("weapon_kind", "")) in ["blast", "melee"]:
					_queue_sound(event, "hit", -23, 2)
			"unit_state_changed":
				if event.get("state", "") in ["unconscious", "routed"]:
					var unit: Dictionary = world.entity(int(event.get("unit_id", -1)))
					if unit.get("team", 1) == 0:
						_play_sound("alert", -10, Vector2.INF, 9)
						show_toast("守军 %02d %s" % [int(unit.id), "倒地，需要救援" if event.state == "unconscious" else "溃逃，暂时无法征召"], 5)
			"unit_action_stage":
				var stage: String = String(event.get("stage", ""))
				if stage == "treatment": _queue_sound(event, "bandage_01", -17, 3)
				elif stage in ["station", "pickup_patient", "drop_patient"]: _queue_sound(event, "station_handle_01", -21, 2)
			"wave_started":
				show_toast("第 %d 波敌人来袭，请检查前沿与侧翼！" % int(event.get("wave", 1)), 5)
				_play_sound("alert", -9, Vector2.INF, 9)
			"order_rejected": show_toast(String(event.get("reason", "命令不可执行")), 4)
			"battle_ended": _play_sound("victory" if event.get("result", "lost") == "won" else "defeat", -6, Vector2.INF, 10)

func _queue_sound(event: Dictionary, name: String, volume: float, priority: int) -> void:
	pending_sounds.append({"event": event, "name": name, "volume": volume, "priority": priority})
	if pending_sounds.size() > 128: pending_sounds.pop_front()

func _flush_sounds(delta: float) -> void:
	for index in range(audio_players.size()):
		voice_age[index] = float(voice_age.get(index, 0.0)) + delta
	if world.phase == "paused" or world.phase == "preparing": return
	if world.phase == "running":
		for unit in world.units:
			if not unit.conscious or unit.dead or unit.velocity.length_squared() < 0.1: continue
			if world.time_s < float(step_audio_at.get(int(unit.id), 0.0)): continue
			step_audio_at[int(unit.id)] = world.time_s + (0.48 if int(unit.posture) == 0 else 0.7)
			var concrete: bool = Rect2(23, 27, 22, 17).has_point(unit.pos)
			var footstep: String = "step_concrete_01" if concrete else ("step_01" if (int(unit.id) + int(world.step_index)) % 2 == 0 else "step_02")
			_play_sound(footstep, -31, unit.pos, 0, int(unit.id) + int(world.step_index))
	for index in range(pending_sounds.size() - 1, -1, -1):
		var sound: Dictionary = pending_sounds[index]
		if not view.motion.event_ready(sound.event): continue
		_play_sound(sound.name, sound.volume, sound.event.get("pos", Vector2.INF), sound.priority, int(sound.event.get("serial", 0)))
		pending_sounds.remove_at(index)

func _load_audio() -> void:
	for name in ["rifle_1", "rifle_2", "mg_1", "mg_2", "mortar", "explosion_1", "explosion_2", "impact", "hit", "reload", "order", "alert", "victory", "defeat", "bandage_01", "station_handle_01", "step_01", "step_02", "step_concrete_01", "impact_metal_01", "impact_sand_01", "impact_wall_01", "reload_mg_01", "mortar_load_01"]:
		var path: String = "res://assets/audio/%s.wav" % name
		if ResourceLoader.exists(path): audio_streams[name] = load(path)
	for i in range(24):
		var player := AudioStreamPlayer2D.new()
		player.max_distance = 3200.0
		player.attenuation = 1.2
		player.panning_strength = 1.1
		add_child(player)
		audio_players.append(player)

func _play_sound(name: String, volume: float = -13, position: Vector2 = Vector2.INF, priority: int = 5, variation: int = 0) -> void:
	if not audio_streams.has(name) or audio_players.is_empty(): return
	var choice: int = -1
	var lowest: int = 100
	var oldest: float = -1.0
	for offset in range(audio_players.size()):
		var index: int = (sound_index + offset) % audio_players.size()
		if not audio_players[index].playing: choice = index; break
		var current_priority: int = int(voice_priority.get(index, 0))
		var age: float = float(voice_age.get(index, 0.0))
		if current_priority <= priority and (current_priority < lowest or (current_priority == lowest and age > oldest)):
			choice = index; lowest = current_priority; oldest = age
	if choice < 0: return
	var player: AudioStreamPlayer2D = audio_players[choice]
	sound_index += 1
	voice_priority[choice] = priority
	voice_age[choice] = 0.0
	player.position = camera.position if position == Vector2.INF else position * GRID
	player.stream = audio_streams[name]
	player.volume_db = volume
	player.pitch_scale = 1.0 if variation == 0 else 0.97 + float((variation * 17) % 7) * 0.01
	player.play()
	player.stream_paused = world.phase in ["preparing", "paused"] and priority < 5

func _over_hud(point: Vector2) -> bool:
	return top.get_global_rect().has_point(point) or bottom.get_global_rect().has_point(point) or inspector.get_global_rect().has_point(point) or minimap.get_global_rect().has_point(point)

func _zoom_at(point: Vector2, factor: float) -> void:
	var before: Vector2 = viewport_to_grid(point) * GRID
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, 0.24, 1.2)
	camera.force_update_scroll()
	var after: Vector2 = viewport_to_grid(point) * GRID
	camera.position += before - after
	_clamp_camera()

func viewport_to_grid(point: Vector2) -> Vector2:
	return (get_viewport().get_canvas_transform().affine_inverse() * point) / GRID

func _clamp_camera() -> void:
	camera.position.x = clampf(camera.position.x, 0, Config.MAP_SIZE.x * GRID)
	camera.position.y = clampf(camera.position.y, 0, Config.MAP_SIZE.y * GRID)

func _draw_hud_overlay() -> void:
	if selecting and drag_start.distance_to(drag_current) > 7:
		var rect: Rect2 = Rect2(drag_start, drag_current - drag_start).abs()
		hud.draw_rect(rect, Color(0.65, 0.9, 0.75, 0.12))
		hud.draw_rect(rect, Color("b8ebcb"), false, 1.5)

func apply_review_orders() -> void:
	world.submit([1], "operate", {"target_id": world.stations()[0].id})
	world.submit([2], "operate", {"target_id": world.stations()[1].id})
	world.submit([3, 4], "operate", {"target_id": world.stations()[2].id})
	world.submit([5], "move", {"position": Vector2(25.5, 22.5)})
	world.submit([6], "move", {"position": Vector2(36.5, 22.5)})
	selected = [1, 2, 3, 4, 5, 6]
	world.start_battle()
	_sync_pause()

func capture_review_frame(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var result: Error = image.save_png(path)
	print("REVIEW_CAPTURE ", path, " result=", result, " sim_time=", world.time_s)
	if review_quit: get_tree().quit(int(result))

func _parse_review_args() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--review-auto": apply_review_orders()
		elif argument.begins_with("--review-capture="): review_capture_path = argument.trim_prefix("--review-capture=")
		elif argument.begins_with("--review-time="): review_time = float(argument.trim_prefix("--review-time="))
		elif argument.begins_with("--review-zoom="): camera.zoom = Vector2.ONE * clampf(float(argument.trim_prefix("--review-zoom=")), 0.24, 1.2)
		elif argument.begins_with("--review-center="):
			var center: PackedStringArray = argument.trim_prefix("--review-center=").split(",")
			if center.size() == 2: camera.position = Vector2(float(center[0]), float(center[1])) * GRID
		elif argument == "--review-quit": review_quit = true

func _exit_tree() -> void:
	for player in audio_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	audio_streams.clear()
