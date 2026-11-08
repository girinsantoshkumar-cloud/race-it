@tool
class_name ScatterExclusion
extends Node3D
## Drop under your scene at a building / playable zone / clearing. Props won't spawn inside (+ category margin).

enum Shape { CIRCLE, BOX }

@export var shape: Shape = Shape.CIRCLE
@export var radius := 10.0
## Box footprint (X, Z), rotates with node yaw.
@export var box_size := Vector2(20.0, 20.0)
## Category names affected. Empty = all categories.
@export var affects: PackedStringArray = []

func _enter_tree() -> void:
	add_to_group("scatter_exclusion")

func affects_category(n: String) -> bool:
	return affects.is_empty() or affects.has(n)

## Negative = inside.
func signed_distance(p: Vector2) -> float:
	var c := Vector2(global_position.x, global_position.z)
	if shape == Shape.CIRCLE:
		return p.distance_to(c) - radius
	var l := (p - c).rotated(global_rotation.y)
	var q := l.abs() - box_size * 0.5
	return q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0)
	
