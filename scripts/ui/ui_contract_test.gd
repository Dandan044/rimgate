extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("UI CHECK: " + label)

func _run() -> void:
	var Screen = load("res://scripts/ui/battle_screen.gd")
	var screen = Screen.new()
	root.add_child(screen)
	await process_frame
	# This contract suite verifies commands and imported sound resources. Audio is
	# exercised by the rendered game, avoiding headless driver playback handles.
	for player in screen.audio_players:
		player.queue_free()
	screen.audio_players.clear()
	_check(screen.world.phase == "preparing" and paused, "initial preparation is paused")
	_check(screen.unit_buttons.size() == 6, "six friendly unit cards")
	screen._select_unit(1)
	_check(screen.selected == [1], "unit card selects correct id")
	var first_station: Dictionary = screen.world.stations()[0]
	screen._right_click(first_station.pos, Vector2(300, 300))
	_check(not screen.popup.is_item_disabled(0), "available gun can be operated")
	screen._popup_pressed(0)
	_check(screen.world.projected_crew(int(first_station.id)) == [1], "paused operate command reserves a station")
	screen._select_unit(2)
	screen._right_click(first_station.pos, Vector2(300, 300))
	_check(screen.popup.is_item_disabled(0), "full gun command is disabled")
	screen.popup.hide()
	screen.posture_option.item_selected.emit(3)
	_check(int(screen._projected_value(2, "posture", -1)) == 2, "posture option queues prone")
	screen._refresh_hud()
	_check(screen.posture_option.selected == 3, "paused HUD displays projected posture")
	screen.style_option.item_selected.emit(2)
	_check(int(screen._projected_value(2, "style", 1)) == 2, "combat style queues cautious")
	var mortar: Dictionary = screen.world.stations()[2]
	screen.selected.assign([3, 4])
	screen.selected_building = int(mortar.id)
	screen._send("operate", {"target_id": mortar.id})
	screen._begin_fire()
	_check(screen.aim_station == int(mortar.id), "mortar aim can use paused reservations")
	screen._fire_at(Vector2(32.5, 12.5))
	_check(screen.aim_station < 0, "valid bombardment exits targeting mode")
	_check(screen.world.pending_orders[-1].kind == "fire", "bombardment is a station subcommand")
	screen._restart()
	_check(screen.world.pending_orders.is_empty() and screen.selected.is_empty(), "restart clears orders and selection")
	_check(screen.world.projected_crew(int(screen.world.stations()[0].id)).is_empty(), "restart clears crew reservations")
	_check(screen.view.friendly != null and screen.view.enemy != null and screen.view.heavy != null and screen.view.props != null, "all original vector atlases connected")
	_check(screen.audio_streams.size() == 14, "all fourteen original sound effects imported")
	print("UI_CONTRACT_TEST: ", 16 - failures.size(), "/16 passed; failures=", failures)
	for player in screen.audio_players:
		player.stop()
		player.stream = null
	await create_timer(0.2, true).timeout
	screen.queue_free()
	await process_frame
	call_deferred("quit", 0 if failures.is_empty() else 1)
