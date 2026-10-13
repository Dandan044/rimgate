class_name WeaponPose
extends RefCounted

# World coordinates are measured in grid cells. Sprite rectangles are pixels,
# matching the original 64-pixel atlas cells. Animation offsets stay visual.
const GRID := 64.0

static func rifle(position: Vector2, facing: float, posture: int = 0) -> Dictionary:
	# Shoulder mount belongs to the shared pose: the visible barrel and actual
	# projectile origin must move together when stance/art proportions change.
	var hand := Vector2(-sin(facing) * 12.0, -25.0 + cos(facing) * 3.0)
	if posture == 1:
		hand = Vector2(-sin(facing) * 11.0, -20.0 + cos(facing) * 2.0)
	if posture == 2:
		# Alongside the lowered head/shoulder; the barrel must stay readable
		# beyond the head's silhouette, rather than disappearing underneath it.
		hand = Vector2.from_angle(facing) * 14.0 + Vector2(-sin(facing), cos(facing)) * 15.0
	var anchor: Vector2 = position + hand / GRID
	return {"anchor": anchor, "pivot": position, "muzzle": anchor + Vector2.from_angle(facing) * (21.25 / GRID), "muzzle_height": [1.44, 0.96, 0.36][clampi(posture, 0, 2)], "angle": facing, "sprite_rect": Rect2(-15.625, -20.0, 40.0, 40.0)}

static func station(position: Vector2, facing: float, kind: String = "mg") -> Dictionary:
	var pivot_x: float = 16.0 if kind == "mortar" else 22.0
	var tip_x: float = 58.0 if kind == "mortar" else 61.0
	var sprite: Rect2 = Rect2(-pivot_x * 76.0 / 64.0, -17.0, 76.0, 34.0)
	return {"anchor": position, "pivot": position, "muzzle": position + Vector2.from_angle(facing) * ((tip_x - pivot_x) * 76.0 / 64.0 / GRID), "muzzle_height": 1.1 if kind == "mortar" else 1.25, "angle": facing, "sprite_rect": sprite}

static func aimed_rifle(position: Vector2, target: Vector2, posture: int = 0) -> Dictionary:
	var angle: float = (target - position).angle()
	var pose: Dictionary = rifle(position, angle, posture)
	for _iteration in range(4):
		angle = (target - Vector2(pose.anchor)).angle()
		pose = rifle(position, angle, posture)
	return pose
