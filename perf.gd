extends Node3D

@export var tuft_mesh: Mesh
@export var grass_material: ShaderMaterial
@export var terrain_collision_mask := 1
@export var area := Vector2(100, 100)
@export var chunk_size := 20.0
@export var tufts_per_chunk := 1200
@export var max_slope_deg := 35.0

func _ready():
	await get_tree().physics_frame
	tuft_mesh.surface_set_material(0, grass_material)
	var space := get_world_3d().direct_space_state
	for cx in int(area.x / chunk_size):
		for cz in int(area.y / chunk_size):
			_build_chunk(Vector2(cx, cz) * chunk_size, space)

func _build_chunk(origin: Vector2, space: PhysicsDirectSpaceState3D):
	var xforms: Array[Transform3D] = []
	for i in tufts_per_chunk:
		var x := origin.x + randf() * chunk_size
		var z := origin.y + randf() * chunk_size
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(x, 500, z), Vector3(x, -500, z), terrain_collision_mask)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		if rad_to_deg(acos(hit.normal.dot(Vector3.UP))) > max_slope_deg:
			continue
		var b := Basis(Vector3.UP, randf() * TAU).scaled(
			Vector3.ONE * randf_range(0.8, 1.5))
		xforms.append(Transform3D(b, hit.position))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tuft_mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])

	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.visibility_range_end = 45.0
	inst.visibility_range_end_margin = 10.0
	inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(inst)
