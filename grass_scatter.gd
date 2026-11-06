
extends MultiMeshInstance3D

@export var grass_scene: PackedScene
@export var grass_count := 1000
@export var area_size := Vector2(40, 40)
@export var ray_height := 100.0
@export var ray_depth := 200.0
@export_flags_3d_physics var collision_mask := 1

var rng := RandomNumberGenerator.new()

func _ready():
	rng.randomize()
	call_deferred("scatter_grass")

func get_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and node.mesh:
		return node.mesh

	for child in node.get_children():
		var result = get_mesh(child)
		if result:
			return result

	return null

func scatter_grass():
	if grass_scene == null:
		push_error("Assign your grass GLB!")
		return

	var grass = grass_scene.instantiate()
	var mesh = get_mesh(grass)
	grass.free()

	if mesh == null:
		push_error("No mesh found in grass GLB!")
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = grass_count
	multimesh = mm

	var space = get_world_3d().direct_space_state
	var placed := 0

	for i in range(grass_count):
		var x = rng.randf_range(-area_size.x / 2, area_size.x / 2)
		var z = rng.randf_range(-area_size.y / 2, area_size.y / 2)

		var origin = global_position + Vector3(x, ray_height, z)
		var target = origin - Vector3(0, ray_height + ray_depth, 0)

		var query = PhysicsRayQueryParameters3D.create(origin, target)
		query.collision_mask = collision_mask

		var hit = space.intersect_ray(query)

		if hit.is_empty():
			continue

		var yaw = rng.randf_range(0.0, TAU)
		var basis = Basis(Quaternion(Vector3.UP, hit.normal))
		basis = basis * Basis(Vector3.UP, yaw)

		var pos = to_local(hit.position)

		mm.set_instance_transform(
			placed,
			Transform3D(basis, pos)
		)

		placed += 1

		if i % 200 == 0:
			await get_tree().process_frame

	mm.visible_instance_count = placed
	print("Grass placed: ", placed)
