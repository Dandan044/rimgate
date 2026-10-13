extends Node

# Opt-in real exported-game Viewport QA. Fixtures are only UI evidence.
# The production release template forbids external path/script overrides.
const Screen = preload("res://scripts/ui/battle_screen.gd")
const State = preload("res://scripts/sim/state.gd")
var screen
var checks: Array[Dictionary] = []
var report := "res://build/qa/v0.3.0/ui-input-v3.json"
var capture := "res://build/qa/v0.3.0/ui-v3"

var root: Window:
 get: return get_tree().root
var process_frame: Signal:
 get: return get_tree().process_frame

func setup(target = null) -> void:
 screen = target
 call_deferred("_run")

func create_timer(seconds: float, always: bool = true) -> SceneTreeTimer:
 return get_tree().create_timer(seconds,always)

func quit(code: int) -> void:
 get_tree().quit(code)

func _check(condition: bool, name: String) -> void:
 checks.append({"check": name, "passed": condition})
 print("UI_V3 ",name," = ",condition)
 if not condition:
  print("UI_V3_DIAGNOSTIC primary=",screen._primary_id()," building=",screen.selected_building," hover=",screen.hover_enemy," cursor=",screen._cursor_position()," grid=",screen.mouse_world()," canvas=",root.get_canvas_transform()," popup=",screen.popup.visible," shot_key=",screen.shot_cache_key," shot=",screen.shot_label.text)
  push_error(name)

func _point(grid: Vector2) -> Vector2:
 screen.camera.force_update_scroll()
 return root.get_canvas_transform() * (grid * 64.0)

func _mouse(point: Vector2, button: MouseButton, pressed: bool, shift: bool = false) -> void:
 var event := InputEventMouseButton.new()
 event.position = point; event.global_position = point; event.button_index = button; event.pressed = pressed; event.shift_pressed = shift
 root.push_input(event, true)
 await process_frame
 await process_frame

func _click(point: Vector2, button: MouseButton, shift: bool = false) -> void:
 await _mouse(point,button,true,shift); await _mouse(point,button,false,shift)

func _motion(point: Vector2, buttons: int = 0) -> void:
 var event := InputEventMouseMotion.new()
 event.position = point; event.global_position = point; event.button_mask = buttons
 root.push_input(event,true)
 await process_frame
 await process_frame

func _key(code: Key, pressed: bool = true, shift: bool = false) -> void:
 var event := InputEventKey.new(); event.keycode = code; event.pressed = pressed; event.shift_pressed = shift
 root.push_input(event,true)
 await process_frame

func _option(option: OptionButton, index: int) -> void:
 await _click(option.get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
 option.get_popup().set_focused_item(index)
 await _key(KEY_ENTER)
 await _key(KEY_ENTER,false)
 await process_frame

func _screenshot(suffix: String) -> void:
 if DisplayServer.get_name() == "headless": return
 await RenderingServer.frame_post_draw
 var path := ProjectSettings.globalize_path(capture + suffix + ".png")
 var image := root.get_texture().get_image()
 var error := image.save_png(path)
 _check(error == OK,"rendered screenshot saved " + suffix)

func _run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
  elif arg.begins_with("--capture="): capture = arg.trim_prefix("--capture=")
 if screen == null:
  screen = Screen.new(); root.add_child(screen)
 await process_frame; await process_frame
 for player in screen.audio_players: player.queue_free()
 screen.audio_players.clear()
 _check(screen.top.size.y <= 46 and screen.bottom.size.y <= 114,"compact top and bottom bars retain 44/112 logical pixels")
 _check(not screen.minimap.visible and not screen.inspector.visible,"minimap collapsed and empty details hidden by default")
 await _click(screen.minimap_toggle.get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
 _check(screen.minimap.visible,"actual map toggle opens collapsed minimap")
 await _click(screen.minimap_toggle.get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
 await _mouse(_point(Vector2(23,34)),MOUSE_BUTTON_LEFT,true)
 await _motion(_point(Vector2(40,37)),MOUSE_BUTTON_MASK_LEFT)
 await _mouse(_point(Vector2(40,37)),MOUSE_BUTTON_LEFT,false)
 _check(screen.selected.size() == 6 and screen._primary_id() == 1,"actual box selection chooses minimum-ID primary")
 await _click(_point(screen.world.entity(1).pos),MOUSE_BUTTON_LEFT)
 var shifted := InputEventMouseButton.new(); shifted.position = _point(screen.world.entity(2).pos); shifted.global_position = shifted.position; shifted.button_index = MOUSE_BUTTON_LEFT; shifted.pressed = true; shifted.shift_pressed = true
 root.push_input(shifted,true); await process_frame
 shifted = shifted.duplicate(); shifted.pressed = false; root.push_input(shifted,true); await process_frame
 _check(screen.selected == [1,2] and screen._primary_id() == 2,"actual additive pawn click makes the last clicked pawn primary")
 # A station is an exclusive left selection; additive pawn selection must
 # restore personal controls rather than silently retaining that station.
 var selected_station: Dictionary = screen.world.stations()[0]
 await _click(_point(selected_station.pos),MOUSE_BUTTON_LEFT)
 await _click(_point(screen.world.entity(1).pos),MOUSE_BUTTON_LEFT,true)
 _check(screen.selected == [1] and screen.selected_building < 0,"Shift pawn selection clears the prior left-selected station")
 await _option(screen.fire_control_option,1)
 _check(screen.world.pending_orders.back().kind == "fire_control" and screen.world.pending_orders.back().ids == [1],"controls after Shift pawn selection change the pawn instead of the old station")
 await _click(_point(selected_station.pos),MOUSE_BUTTON_LEFT)
 await _mouse(_point(Vector2(23,34)),MOUSE_BUTTON_LEFT,true,true)
 await _motion(_point(Vector2(40,37)),MOUSE_BUTTON_MASK_LEFT)
 await _mouse(_point(Vector2(40,37)),MOUSE_BUTTON_LEFT,false,true)
 _check(screen.selected.size() == 6 and screen.selected_building < 0,"additive box selection also clears the old station")
 screen._restart(); screen._select_unit(1)
 var context_enemy: Dictionary = State.unit(902,1,Vector2(20.5,17.5)); screen.world.units.append(context_enemy); screen.world.unit_system._ensure_unit(context_enemy)
 screen.camera.position = Vector2(25,25)*64.0; screen.camera.zoom = Vector2.ONE*.5; screen.camera.force_update_scroll()
 await _click(_point(screen.world.stations()[0].pos),MOUSE_BUTTON_RIGHT)
 _check(screen.selected == [1] and screen.selected_building < 0 and screen.popup.visible,"right station context preserves the personnel selection")
 await _click(_point(context_enemy.pos),MOUSE_BUTTON_RIGHT)
 _check(screen.world.pending_orders.back().kind == "attack" and screen.world.pending_orders.back().ids == [1],"enemy click after a station context menu remains a personal attack")
 await _click(_point(screen.world.stations()[0].pos),MOUSE_BUTTON_RIGHT)
 screen.popup.set_focused_item(0); await _key(KEY_ENTER); await _key(KEY_ENTER,false)
 _check(screen.world.projected_crew(int(screen.world.stations()[0].id)) == [1],"context operate action still uses its own target station data")
 await _click(_point(screen.world.stations()[0].pos),MOUSE_BUTTON_LEFT)
 await _click(_point(context_enemy.pos),MOUSE_BUTTON_RIGHT)
 _check(screen.world.pending_orders.back().kind == "station_attack", "only explicit left station selection routes enemy clicks to station attack")
 screen._restart()
 await _key(KEY_1); await _key(KEY_2,true,true); await _key(KEY_3,true,true)
 _check(screen.selected == [1,2,3] and screen._primary_id() == 3,"actual keyboard multi-selection keeps last selected primary")
 var center := Vector2(28.5,31.5)
 var start := _point(center)
 var end := _point(center + Vector2(6.0,0.0))
 var before: int = screen.world.pending_orders.size()
 await _mouse(start,MOUSE_BUTTON_RIGHT,true)
 _check(screen.right_dragging and screen.world.pending_orders.size() == before,"right press previews without submitting")
 await create_timer(.12,true).timeout
 await _motion(end,MOUSE_BUTTON_MASK_RIGHT)
 _check(screen.formation_preview.get("ok",false) and screen.formation_preview.allocations.size() == 3,"actual drag displays complete repaired cell allocation")
 await _screenshot("-formation-1600x900")
 var preview: Dictionary = screen.formation_preview.get("allocations",{}).duplicate(true)
 await _mouse(end,MOUSE_BUTTON_RIGHT,false)
 var order: Dictionary = screen.world.pending_orders.back()
 _check(order.kind == "move" and order.data.has("formation") and absf(float(order.data.formation.spacing)-3.0) < .00001,"right release commits axis and spacing from drag")
 _check(var_to_bytes(preview) == var_to_bytes(order.data._allocations),"paused queued per-unit allocation exactly matches displayed preview")
 _check(absf(float(order.data.formation.facing)+PI/2.0) < .00001,"formation facing points from original squad toward destination")
 var frozen := var_to_bytes(screen.world.units)
 await create_timer(.12,true).timeout
 _check(frozen == var_to_bytes(screen.world.units),"paused formation does not move or repair after submission")
 var short_point := _point(Vector2(28.5,30.5))
 await _mouse(short_point,MOUSE_BUTTON_RIGHT,true)
 await _motion(short_point+Vector2(7,0),MOUSE_BUTTON_MASK_RIGHT)
 await _mouse(short_point+Vector2(7,0),MOUSE_BUTTON_RIGHT,false)
 _check(not screen.world.pending_orders.back().data.has("formation") and screen.world.pending_orders.back().data._allocations.size()==3,"seven-screen-pixel right drag remains a short group click")
 # Replace this short click with the already-reviewed long formation before
 # running; the next assertion compares the original explicit preview.
 await _mouse(start,MOUSE_BUTTON_RIGHT,true); await _motion(end,MOUSE_BUTTON_MASK_RIGHT); await _mouse(end,MOUSE_BUTTON_RIGHT,false)
 screen.world.next_wave = 3; screen._start()
 for tick in range(500): screen.world.step()
 screen._toggle_pause()
 var arrived := true
 for id in [1,2,3]: arrived = arrived and screen.world.entity(id).pos == preview[id].goal
 _check(arrived,"resumed units execute the same paused formation cells")
 before = screen.world.pending_orders.size()
 await _click(screen.unit_buttons[0].get_global_rect().get_center(),MOUSE_BUTTON_RIGHT)
 _check(screen.world.pending_orders.size() == before and not screen.right_dragging,"HUD right click never leaks a movement command")
 var station: Dictionary = screen.world.stations()[0]
 screen.camera.position = Vector2(27,27)*64.0; screen.camera.force_update_scroll()
 await _click(_point(station.pos),MOUSE_BUTTON_RIGHT)
 _check(screen.popup.visible,"actual right click opens interactive station menu")
 await _click(_point(Vector2(30.5,32.5)),MOUSE_BUTTON_RIGHT)
 _check(not screen.popup.visible and screen.world.pending_orders.back().kind == "move","next right click closes menu and queues a new ground command")
 await _click(_point(screen.world.entity(4).pos),MOUSE_BUTTON_RIGHT)
 await _click(_point(station.pos),MOUSE_BUTTON_RIGHT)
 _check(screen.popup.visible and screen.popup_actions[0].kind == "operate","continuous right click replaces one interaction menu with another")
 screen.aim_station = int(screen.world.stations()[2].id)
 await _click(_point(Vector2(30.5,32.5)),MOUSE_BUTTON_RIGHT)
 _check(screen.aim_station < 0 and screen.world.pending_orders.back().kind == "move","new right click replaces bombardment targeting mode")
 screen._restart()
 await _key(KEY_1)
 await _option(screen.fire_control_option,1)
 _check(screen.world.pending_orders.back().kind == "fire_control" and bool(screen.world.pending_orders.back().data.value),"actual fire-control dropdown queues personal hold-fire")
 await _key(KEY_2,true,true)
 _check(screen.fire_control_option.selected == 2,"mixed personal fire controls show explicit Mixed")
 screen._send("posture",{"value":2},[1]); screen._send("style",{"value":2},[1]); screen._send("target_policy",{"value":"priority"},[1]); screen._refresh_hud()
 _check(screen.posture_option.selected == 4 and screen.style_option.selected == 3 and screen.target_policy_option.selected == 2,"mixed posture, style and target policy never display a false common setting")
 screen._select_unit(1)
 screen._right_click(screen.world.stations()[0].pos,Vector2(300,300)); screen._popup_pressed(0); screen.popup.hide()
 screen.selected.clear(); screen.selected_building = int(screen.world.stations()[0].id); screen._refresh_hud()
 await _option(screen.fire_control_option,1)
 await _option(screen.target_policy_option,1)
 _check(screen.world.pending_orders.back().kind == "station_control" and screen.world.pending_orders.back().data.hold_fire and screen.world.pending_orders.back().data.target_policy == "priority","station dropdown independently queues hold-fire and priority")
 _check(not screen.world.entity(1).hold_fire,"paused operator personal state is not overwritten by station fire controls")
 screen._restart(); screen._select_unit(1)
 var unit: Dictionary = screen.world.entity(1)
 unit.pos = Vector2(28.5,31.5); unit.prev_pos = unit.pos; unit.hp = 60.0; unit.bleed_rate = .5; unit.stability = 1.0
 var enemy: Dictionary = State.unit(901,1,Vector2(28.5,26.5)); enemy.ai_next = INF; screen.world.units.append(enemy); screen.world.unit_system._ensure_unit(enemy)
 screen._refresh_hud()
 _check(screen.info_label.text.contains("预计死亡 2:00") and screen.unit_buttons[0].text.contains("死2:00"),"details and squad card show HP / current bleeding death ETA")
 screen.camera.position = Vector2(28.5,29)*64.0; screen.camera.zoom = Vector2.ONE*.65; screen.camera.force_update_scroll()
 var rng_before: int = screen.world.rng.state
 await _motion(_point(enemy.pos))
 await create_timer(.12,true).timeout
 _check(screen.shot_panel.visible and screen.shot_label.text.contains("最终单发命中率"),"actual enemy hover shows final probability from shared combat query")
 await _click(screen.unit_buttons[1].get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
 await _option(screen.fire_control_option,1)
 await _motion(_point(enemy.pos)); await create_timer(.12,true).timeout
 _check(screen.shot_cache_key.begins_with("2:901:") and screen.shot_label.text.contains("守军02") and not screen.shot_label.text.contains("守军01"),"paused control changes then card selection invalidate the old shooter's cached preview")
 _check(screen.fire_control_option.selected == 1 and not screen.world.entity(2).hold_fire,"paused fire controls project the pending order without pretending its future state has executed")
 await _click(screen.unit_buttons[0].get_global_rect().get_center(),MOUSE_BUTTON_LEFT)
 await _motion(_point(enemy.pos)); await create_timer(.12,true).timeout
 await _key(KEY_ALT)
 _check(screen.shot_label.text.contains("距离基础精度") and screen.shot_label.text.contains("贴近友军豁免"),"actual Alt key expands precision and exemption details")
 _check(screen.world.rng.state == rng_before,"hover and Alt preview consume no combat randomness")
 var query_count: int = screen.shot_query_count
 for repetition in range(100): screen._update_shot_preview()
 _check(screen.shot_query_count - query_count <= 1,"repeated hover refresh is throttled to ten queries per second")
 await _screenshot("-alt-1600x900")
 var blocker: Dictionary = screen.world.entity(2); blocker.pos = Vector2(28.5,28.5); blocker.prev_pos = blocker.pos
 screen.world.entity(3).pos = Vector2(29.5,31.5); screen.world.entity(3).prev_pos = screen.world.entity(3).pos
 screen.world.buildings.append(State.building(9901,"sandbag",Rect2i(28,29,1,1)))
 screen.world.unit_system.rebuild_navigation(screen.world)
 screen.shot_cache_key=""; await create_timer(.12,true).timeout
 _check(screen.shot_label.text.contains("掩体段1") and screen.shot_label.text.contains("中途人员2") and screen.shot_label.text.contains("友伤风险"),"Alt details explain intervening cover, body interception and friendly-fire risk")
 _check(screen.shot_label.text.contains("0.0%") and screen.shot_label.text.contains("[3]"),"blocked final chance reaches zero while adjacent ally exemption remains listed")
 await _screenshot("-body-risk-1600x900")
 screen.world.buildings.pop_back(); screen.world.unit_system.rebuild_navigation(screen.world)
 blocker.pos=Vector2(27.5,35.5); blocker.prev_pos=blocker.pos
 unit.loaded=0; unit.reload_reserved=30; unit.reload_stage=0
 screen.shot_cache_key=""; await create_timer(.12,true).timeout
 _check(screen.shot_label.text.contains("尚未就绪：装填中") and not screen.shot_label.text.contains("命中率  0.0%"),"reload readiness is reported separately from positive shooting probability")
 unit.loaded=30; unit.reload_reserved=0
 await _key(KEY_ALT,false)
 var mortar: Dictionary = screen.world.stations()[2]
 var crew: Dictionary = screen.world.entity(3)
 crew.station_id = int(mortar.id); crew.job = "operate"; crew.stage = "station"; crew.pos = mortar.crew_points[0]; crew.posture = 1; crew.posture_timer = 0.0; mortar.crew.assign([3]); mortar.loaded = 1
 enemy.pos = Vector2(32.5,14.5); enemy.prev_pos = enemy.pos
 screen.selected.clear(); screen.selected_building = int(mortar.id); screen._refresh_hud()
 screen.camera.position = Vector2(32,23)*64.0; screen.camera.zoom = Vector2.ONE*.5; screen.camera.force_update_scroll()
 await _motion(_point(enemy.pos)); await create_timer(.12,true).timeout
 _check(screen.shot_label.text.contains("目标位于爆炸范围内的概率"),"mortar hover uses explosion coverage probability label")
 await _screenshot("-mortar-1600x900")
 # Use actual window sizes; the same canvas retains readable controls when
 # stretched to the supported 720p and 1080p windows.
 if DisplayServer.get_name() != "headless":
  DisplayServer.window_set_size(Vector2i(1280,720)); await create_timer(.15,true).timeout
  _check(screen.top.get_global_rect().end.x <= screen.get_viewport_rect().size.x and screen.bottom.get_global_rect().end.x <= screen.get_viewport_rect().size.x,"720p HUD stays inside viewport")
  await _screenshot("-720p")
  DisplayServer.window_set_size(Vector2i(1920,1080)); await create_timer(.15,true).timeout
  _check(screen.top.get_global_rect().end.x <= screen.get_viewport_rect().size.x and screen.bottom.get_global_rect().end.x <= screen.get_viewport_rect().size.x,"1080p HUD stays inside viewport")
  await _screenshot("-1080p")
 var cues_before: int = screen.pending_sounds.size()
 screen.world.emit_event("unit_state_changed",{"unit_id":1,"state":"cowering","interrupted":true,"pos":unit.pos})
 screen.world.emit_event("reload_started",{"entity_id":1,"pos":unit.pos,"stage":0})
 screen.world.emit_event("reload_stage",{"entity_id":1,"pos":unit.pos,"stage":1})
 screen.world.emit_event("reload_complete",{"entity_id":1,"pos":unit.pos})
 screen._check_events()
 _check(screen.pending_sounds.size()-cues_before==4,"pressure and each real reload phase event receive distinct queued sound cues")
 var passed := true
 for check in checks: passed = passed and bool(check.passed)
 var output := {"passed":passed,"checks":checks,"method":"Actual Viewport mouse press/release/motion, PopupMenu keyboard selection, keyboard and Alt events against the real battle screen.","fixture":"Enemy, injury, and mortar operator states are inserted solely to expose UI conditions. This is not balance, performance, or victory evidence.","captured": DisplayServer.get_name() != "headless"}
 var executable := OS.get_executable_path()
 var pck := executable.get_basename()+".pck"
 if FileAccess.file_exists(pck):
  output["pck_sha256"] = FileAccess.get_sha256(pck).to_upper()
  output["pck_path"] = pck
 output["executable"] = executable
 var file := FileAccess.open(report,FileAccess.WRITE)
 if file != null: file.store_string(JSON.stringify(output,"\t")); file.close()
 print("UI_V3_RESULT checks=",checks.size()," passed=",passed)
 screen.queue_free(); await process_frame
 quit(0 if passed else 1)
