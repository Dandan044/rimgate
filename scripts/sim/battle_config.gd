class_name BattleConfig
extends Resource

const GRID := 64.0
const MAP_SIZE := Vector2i(64, 48)
const FIXED_DT := 1.0 / 60.0
const SEED := 104729
const DURATION := 480.0
const HEIGHTS := [1.8, 1.2, 0.45]
const VOLUMES := [1.0, 0.65, 0.35]
const RADII := [0.22, 0.18, 0.13]
const POSTURE_SPEED := [1.0, 0.75, 0.35]
const STYLE_AIM := [0.25, 0.55, 0.85]
const STYLE_ACCURACY := [0.65, 1.0, 1.25]
const STYLE_RECOVERY := [1.4, 1.0, 0.7]
# v0.2 tuning defaults: one full normal rifle cycle is 2.25 aim + .25 burst + .5 recovery.
const RIFLE_AIM_SECONDS := [0.65, 2.25, 3.8]
const RIFLE_RECOVER_SECONDS := [0.0, 0.5, 0.7]
const MG_AIM_SECONDS := [0.45, 1.5, 2.8]
const MG_RECOVER_SECONDS := [0.0, 0.7, 0.8]
const COVER_CAP := 0.9
const COVER_VOLUME_SCALE := 4.0
const COVER_NEAR_DISTANCE := 0.5
const COVER_FULL_DISTANCE := 2.5
const MEDICAL_RECT := Rect2(38, 39, 6, 4)
const SUPPLY_POINT := Vector2(27.5, 29.5)
const WAVE_TIMES := [30.0, 150.0, 300.0]

static func rifle() -> Dictionary:
	return {"kind": "rifle", "damage": 18.0, "penetration": 1.0, "range": 24.0, "rate": 8.0, "magazine": 30, "reload": 3.0, "speed": 80.0, "accuracy_near": 0.6, "accuracy_far": 0.2, "recoil": 0.12}

static func machine_gun() -> Dictionary:
	return {"kind": "mg", "damage": 24.0, "penetration": 2.0, "range": 32.0, "rate": 10.0, "magazine": 100, "reload": 5.0, "speed": 90.0, "accuracy_near": 0.55, "accuracy_far": 0.16, "recoil": 0.045}

static func fragment() -> Dictionary:
	return {"kind": "fragment", "damage": 24.0, "penetration": 1.0, "range": 10.0, "speed": 60.0}
