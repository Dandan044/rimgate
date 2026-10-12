extends RefCounted

var failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _snapshot(w) -> String:
	return var_to_str([w.units, w.buildings, w.supplies, w.projectiles, w.pending_orders, w.medical_reservations, w.medical_stock, w.time_s, w.step_index, w.next_wave, w.stats, w.rng.state])

func run(factory: Callable) -> Array[String]:
	failures.clear()
	var w = factory.call()
	_check(w.units.size() == 6 and w.phase == "preparing", "Initial state must contain six friendlies in preparation")
	_check(w.stations().size() == 3 and w.supplies.size() == 14, "Initial stations and supply boxes")
	var initial := _snapshot(w)
	for i in range(600): w.step()
	_check(initial == _snapshot(w), "Preparation must freeze all simulation state")
	w.start_battle()
	w.units[0].bleed_rate = 0.2
	w.units[0].hp = 70.0
	w.units[0].suppression = 40.0
	w.units[0].reload_progress = 1.0
	w.set_paused(true)
	var accepted: Dictionary = w.submit([1], "move", {"position": Vector2(20.5, 30.5)})
	_check(accepted.get("ok", false), "Paused movement command accepted")
	var frozen := _snapshot(w)
	for i in range(600): w.step()
	_check(frozen == _snapshot(w), "Ten seconds of paused ticks must freeze HP, bullets, jobs and timers")
	w.set_paused(false); w.step()
	_check(w.time_s > 0.0 and w.pending_orders.is_empty(), "Resume consumes paused intentions")
	_check(w.units[0].hp < 70.0, "Resume advances bleeding")
	w.reset()
	_check(initial == _snapshot(w), "Reset restores deterministic full initial state")
	w.start_battle(); w.time_s = 30.0 - 1.0 / 60.0
	w.step()
	_check(w.next_wave == 1 and w.stats.enemy_spawned == 4, "First wave occurs exactly at 30 s")
	w.time_s = 150.0 - 1.0 / 60.0; w.step()
	_check(w.next_wave == 2 and w.stats.enemy_spawned == 12, "Second wave occurs exactly at 150 s")
	w.time_s = 300.0 - 1.0 / 60.0; w.step()
	_check(w.next_wave == 3 and w.stats.enemy_spawned == 24, "Third wave occurs exactly at 300 s")
	w = factory.call(); w.next_wave = 3; w.start_battle()
	for u in w.units: u.hp = 20.0; u.conscious = false
	w.step()
	_check(w.phase == "running", "All unconscious but alive must not trigger defeat")
	w.time_s = 480.0 - 1.0 / 60.0; w.step()
	_check(w.phase == "won", "Surviving to 480 s wins even with unconscious defenders")
	var ended := _snapshot(w)
	for i in range(60): w.step()
	_check(ended == _snapshot(w), "Results freeze simulation")
	w = factory.call(); w.start_battle(); w.next_wave = 3
	w.time_s = 480.0 - 1.0 / 60.0; w.core().hp = 0.0; w.step()
	_check(w.phase == "lost", "Core loss takes priority over victory on same step")
	w = factory.call(); w.start_battle(); w.next_wave = 3
	for u in w.units: u.hp = 0.0
	w.step()
	_check(w.phase == "lost", "All dead triggers defeat")
	w.reset()
	_check(initial == _snapshot(w), "Reset after loss clears old state, timers and reservations")
	w = factory.call()
	w.spawn_wave(0); w.spawn_wave(1); w.spawn_wave(2)
	var occupied: Dictionary = {}
	for u in w.units:
		var cell := Vector2i(Vector2(u.pos).floor())
		_check(not occupied.has(cell), "Back-to-back waves spawn into distinct cells")
		_check(Vector2(u.pos).is_equal_approx(Vector2(cell) + Vector2(0.5, 0.5)), "Every spawned unit begins at a grid centre")
		occupied[cell] = u.id
	_check(w.units.size() == 30, "Safe spawn preserves all six defenders and twenty-four attackers")
	w = factory.call()
	_check(w.submit([1], "operate", {"target_id": 1022}).ok, "Station operator can be reserved in preparation")
	var target = preload("res://scripts/sim/state.gd").unit(900, 1, Vector2(20.5, 10.5))
	w.units.append(target)
	var locked: Dictionary = w.submit_station_attack(1022, 900)
	_check(locked.ok and w.entity(1022).target_id == -1, "Preparing station target queues without advancing simulation")
	w.start_battle(); w.step()
	_check(w.entity(1022).target_id == 900 and w.entity(1).station_id == 1022, "Station attack applies without releasing the operator")
	return failures
