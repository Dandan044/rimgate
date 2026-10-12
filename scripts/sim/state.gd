class_name BattleState
extends RefCounted

static func unit(id: int, team: int, position: Vector2, kind: String = "rifleman") -> Dictionary:
	var heavy: bool = kind == "heavy"
	var maximum: float = 150.0 if heavy else 100.0
	return {"id": id, "team": team, "kind": kind, "name": "%02d" % id if team == 0 else ("重装" if heavy else "袭击者"), "pos": position, "prev_pos": position, "velocity": Vector2.ZERO, "hp": maximum, "max_hp": maximum, "armor": 2.0 if heavy else (1.0 if team == 0 else 0.0), "conscious": true, "dead": false, "posture": 0, "posture_mode": -1, "posture_timer": 0.0, "style": 1, "drafted": team == 0, "stability": 0.0, "suppression": 0.0, "last_threat": -999.0, "forced_prone": false, "forced_until": 0.0, "rout_until": 0.0, "bleed_rate": 0.0, "loaded": 30, "reserve": 150, "reload_progress": 0.0, "reload_reserved": 0, "weapon_cooldown": 0.0, "burst_left": 0, "burst_rest": 0.0, "target_id": -1, "job": "idle", "stage": "", "goal": position, "path": PackedVector2Array(), "path_index": 0, "station_id": -1, "crate_id": -1, "rescued_id": -1, "carrier_id": -1, "bandages": 2 if team == 0 else 0, "job_timer": 0.0, "move_speed": 2.0 if heavy else 2.5, "facing": -PI / 2.0, "ai_hold_until": 0.0, "spawn_entry": position, "medical_slot": -1, "status": "待命"}

static func building(id: int, kind: String, rect: Rect2i) -> Dictionary:
	var hp := 200.0
	var height := 0.8
	var screen := 0.5
	var high := false
	match kind:
		"wall": hp = 300.0; height = 2.2; screen = 1.0; high = true
		"crate": hp = 400.0; height = 0.9; screen = 0.55
		"core": hp = 1000.0; height = 2.2; screen = 1.0; high = true
		"mg", "mortar": hp = 300.0; screen = 0.35
		"floor": height = 0.0; screen = 0.0
	var center := Vector2(rect.position) + Vector2(rect.size) * 0.5
	var barrier_type := "wall" if high else ("floor" if height < 0.1 else "cover")
	return {"id": id, "kind": kind, "name": {"sandbag": "沙袋", "wall": "墙体", "crate": "箱体", "core": "远古设施", "mg": "重机枪", "mortar": "迫击炮"}.get(kind, kind), "rect": rect, "pos": center, "hp": hp, "max_hp": hp, "height": height, "screen_volume": screen, "screening_strength": 4.0 * screen, "barrier_type": barrier_type, "high": high, "vaultable": not high, "destroyed": false, "crew": [], "capacity": 2 if kind == "mortar" else (1 if kind == "mg" else 0), "crew_points": [center + Vector2(0, 1), center + Vector2(1, 1)], "ammo": 4 if kind == "mortar" else 0, "loaded": 100 if kind == "mg" else 0, "ammo_capacity": 8 if kind == "mortar" else (400 if kind == "mg" else 0), "supply_reserved": 0, "reload_progress": 0.0, "reload_reserved": 0, "aim_progress": 0.0, "fire_point": Vector2(-1, -1), "fire_requested": false, "target_id": -1, "weapon_cooldown": 0.0, "burst_left": 0, "burst_rest": 0.0, "facing": -PI / 2.0, "arc": deg_to_rad(120.0), "last_crew": [], "status": "无人操作"}
