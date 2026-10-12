class_name WeaponPose
extends RefCounted

# World coordinates are measured in grid cells. Sprite rectangles are pixels,
# matching the original 64-pixel atlas cells. Animation offsets stay visual.
const GRID := 64.0

static func rifle(position: Vector2, facing: float, posture: int = 0) -> Dictionary:
	var hand := Vector2(-sin(facing) * 18.0, -17.0 + cos(facing) * 7.0)
	if posture == 2:
		hand = Vector2.from_angle(facing) * 12.0 + Vector2(-sin(facing), cos(facing)) * 9.0
	var anchor: Vector2 = position + hand / GRID
	return {"anchor": anchor, "muzzle": anchor + Vector2.from_angle(facing) * (21.25 / GRID), "angle": facing, "sprite_rect": Rect2(-15.625, -20.0, 40.0, 40.0)}

static func station(position: Vector2, facing: float, kind: String = "mg") -> Dictionary:
	var pivot_x: float = 16.0 if kind == "mortar" else 22.0
	var tip_x: float = 58.0 if kind == "mortar" else 61.0
	var sprite: Rect2 = Rect2(-pivot_x * 76.0 / 64.0, -17.0, 76.0, 34.0)
	return {"anchor": position, "muzzle": position + Vector2.from_angle(facing) * ((tip_x - pivot_x) * 76.0 / 64.0 / GRID), "angle": facing, "sprite_rect": sprite}

static func aimed_rifle(position: Vector2, target: Vector2, posture: int = 0) -> Dictionary:
	var angle: float = (target - position).angle()
	var pose: Dictionary = rifle(position, angle, posture)
	for _iteration in range(4):
		angle = (target - Vector2(pose.anchor)).angle()
		pose = rifle(position, angle, posture)
	return pose
