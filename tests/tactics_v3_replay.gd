extends SceneTree

const World = preload("res://scripts/sim/world.gd")
const Recording = preload("res://scripts/qa/verified_tactic_v3.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var expected: Dictionary = Recording.expected()
	var commands: Array = Recording.commands()
	var world=World.new()
	var cursor: int = 0
	var violations: int = 0
	var serial: int = 0
	var friendly_hits: int = 0
	var friendly_hp: float = 0.0
	world.start_battle()
	while world.phase=="running" and world.step_index<28801:
		while cursor<commands.size() and int(commands[cursor].step)==world.step_index:
			var order: Dictionary = commands[cursor]
			var result: Dictionary = world.submit(order.ids,order.kind,order.data.duplicate(true))
			if not bool(result.ok): push_error("V3 replay rejected order %d: %s" % [cursor,result.reason]); quit(1); return
			cursor+=1
		world.step()
		var cells: Dictionary = {}
		for unit in world.units:
			if unit.dead or not unit.conscious or int(unit.carrier_id)>=0: continue
			var cell: Vector2i = Vector2i(Vector2(unit.pos).floor())
			if cells.has(cell): violations+=1
			cells[cell]=int(unit.id)
		for event in world.events:
			if int(event.serial)<=serial: continue
			serial=int(event.serial)
			if event.type=="damage" and int(event.get("team",-1))==0 and int(event.get("target_team",-1))==0 and world.entity(int(event.get("entity_id",-1))).has("team"):
				friendly_hits+=1; friendly_hp+=float(event.amount)
		if world.step_index%3600==0: print("V3_REPLAY_PROGRESS seconds=",world.time_s," core=",world.core().hp," commands=",cursor)
	var fingerprint: int = hash(var_to_bytes([world.time_s,world.units,world.buildings,world.supplies,world.projectiles,world.stats,world.rng.state]))
	var alive: int = 0
	var awake: int = 0
	var enemies: int = 0
	for unit in world.units:
		if int(unit.team)==0:
			if not unit.dead: alive+=1
			if not unit.dead and unit.conscious: awake+=1
		elif not unit.dead: enemies+=1
	var passed: bool = world.phase=="won" and world.step_index==28800 and cursor==commands.size() and fingerprint==int(expected.state_hash) and violations==0
	passed=passed and alive==int(expected.alive) and awake==int(expected.awake) and enemies==int(expected.living_enemies) and float(world.core().hp)==float(expected.core_hp)
	passed=passed and friendly_hits==int(expected.ally_friendly_fire_hits) and absf(friendly_hp-float(expected.ally_friendly_fire_hp))<.001
	for key in ["rifle_shots","mg_shots","mortar_shots","enemy_spawned","friendly_fire","ammo_destroyed"]:
		passed=passed and int(world.stats[key])==int(expected[key])
	var report: Dictionary = {"passed":passed,"phase":world.phase,"step":world.step_index,"time":world.time_s,"commands":cursor,"state_hash":fingerprint,"expected_hash":expected.state_hash,"alive":alive,"awake":awake,"living_enemies":enemies,"core_hp":world.core().hp,"occupancy_violations":violations,"ally_friendly_fire_hits":friendly_hits,"ally_friendly_fire_hp":friendly_hp,"stats":world.stats}
	DirAccess.make_dir_recursive_absolute("res://build/reports")
	var file:=FileAccess.open("res://build/reports/tactics_v3_replay.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("V3_REPLAY_RESULT ",JSON.stringify(report))
	if not passed: push_error("Fresh v3 replay differs from its recorded standard-world victory")
	quit(0 if passed else 1)
