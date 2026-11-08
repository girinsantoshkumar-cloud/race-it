extends Node3D

@export var terrain: Node
@export var grass_meshes: Array[Mesh]
@export var type_weights: Array[float] = []
@export var type_size: Array[float] = []

@export_group("Last of Us Overgrown Density")
@export var chunk_size := 28.0                  # Slightly tighter chunk for higher density near camera
@export var radius := 1                         # Keep at 1 for 8GB RAM
@export var spacing := 0.52                     # Much tighter spacing (spawns 2.5x more tufts per meter!)
@export var min_normal_y := 0.75                # Allows grass to grow on steeper slopes too
@export var water_level := -1000.0
@export var height_offset := -0.05

@export_group("Clump Size & Overgrown Height")
@export var width_scale_range := Vector2(0.55, 1.15)  # Wide, overlapping clumps so you don't see bare dirt
@export var height_scale_range := Vector2(0.28, 0.65) # Knee-to-waist high overgrown Last of Us look
@export var max_tilt := 0.35                          # Tangled, wild tilt

@export_group("Natural Overgrowth Mask")
@export_range(0.0, 1.0) var coverage := 0.88          # 88% of the ground is covered in thick grass!
@export var meadow_size := 40.0
@export_range(0.01, 0.5) var edge_softness := 0.15
@export var clump_size := 4.5
@export_range(0.0, 1.0) var clump_strength := 0.45    # Lowered so it stays thick instead of leaving empty holes
@export_range(0.0, 1.0) var max_density := 0.92       # Almost every spot inside the meadow gets grass
@export var patch_size := 12.0
@export_range(0.0, 1.0) var patch_strength := 0.55

var _data = null
var _weights: Array[float] = []
var _sizes: Array[float] = []
var _meadow := FastNoiseLite.new()
var _clump := FastNoiseLite.new()
var _patch := FastNoiseLite.new()

var _chunks := {}
var _ticket := {}
var _pool: Array = []
var _last := Vector2i(1 << 30, 1 << 30)
var _next_ticket := 0
var _printed := false

func _ready() -> void:
	if grass_meshes.is_empty():
		push_error("GRASS: add at least one mesh to Grass Meshes")
		return
	for i in grass_meshes.size():
		_weights.append(type_weights[i] if i < type_weights.size() else 1.0)
		_sizes.append(type_size[i] if i < type_size.size() else 1.0)
	_setup_noise(_meadow, 101, meadow_size)
	_setup_noise(_clump, 202, clump_size)
	_setup_noise(_patch, 303, patch_size)

func _setup_noise(n: FastNoiseLite, s: int, size: float) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.0 / maxf(size, 0.5)

func _process(_delta: float) -> void:
	if grass_meshes.is_empty() or terrain == null:
		return
	if _data == null:
		_data = terrain.get_data()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	var c := Vector2i(floori(p.x / chunk_size), floori(p.z / chunk_size))
	if c == _last:
		return
	_last = c
	_refresh(c)

func _refresh(c: Vector2i) -> void:
	for k in _chunks.keys():
		if absi(k.x - c.x) > radius or absi(k.y - c.y) > radius:
			var old: Array = _chunks[k]
			_chunks.erase(k)
			_ticket.erase(k)
			for nd in old:
				nd.visible = false
			_pool.append(old)
	for x in range(c.x - radius, c.x + radius + 1):
		for z in range(c.y - radius, c.y + radius + 1):
			var k := Vector2i(x, z)
			if _chunks.has(k):
				continue
			var group := _take_group()
			var pos := Vector3((x + 0.5) * chunk_size, 0.0, (z + 0.5) * chunk_size)
			for nd in group:
				nd.global_position = pos
			_chunks[k] = group
			_next_ticket += 1
			_ticket[k] = _next_ticket
			WorkerThreadPool.add_task(_build.bind(k, _next_ticket))

func _take_group() -> Array:
	if not _pool.is_empty():
		return _pool.pop_back()
	var group: Array = []
	for m in grass_meshes:
		var nd := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		nd.multimesh = mm
		nd.top_level = true
		nd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nd.visibility_range_end = (radius + 0.5) * chunk_size
		nd.visibility_range_end_margin = 5.0
		nd.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(nd)
		group.append(nd)
	return group

func _pick_type(r01: float) -> int:
	var total := 0.0
	for w in _weights:
		total += w
	var r := r01 * total
	for i in _weights.size():
		r -= _weights[i]
		if r <= 0.0:
			return i
	return _weights.size() - 1

func _density(wx: float, wz: float, normal_y: float) -> float:
	var m := _meadow.get_noise_2d(wx, wz) * 0.5 + 0.5
	var threshold := 1.0 - coverage
	var d := smoothstep(threshold - edge_softness, threshold + edge_softness, m)
	var c := _clump.get_noise_2d(wx, wz) * 0.5 + 0.5
	d *= lerpf(1.0, c * 1.3, clump_strength)
	var slope := clampf((normal_y - min_normal_y) / maxf(1.0 - min_normal_y, 0.01) * 2.0, 0.0, 1.0)
	return clampf(d * max_density * slope, 0.0, 1.0)

func _build(k: Vector2i, ticket: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k)
	var origin := Vector3((k.x + 0.5) * chunk_size, 0.0, (k.y + 0.5) * chunk_size)
	var lists: Array = []
	for t in grass_meshes.size():
		lists.append([])
	var steps := int(chunk_size / spacing)
	for i in steps:
		for j in steps:
			var jx := rng.randf()
			var jz := rng.randf()
			var yaw := rng.randf() * TAU
			var w_scale := rng.randf_range(width_scale_range.x, width_scale_range.y)
			var h_scale := rng.randf_range(height_scale_range.x, height_scale_range.y)
			var tr := rng.randf()
			var keep := rng.randf()
			var tilt_x := rng.randf_range(-max_tilt, max_tilt)
			var tilt_z := rng.randf_range(-max_tilt, max_tilt)

			var wx := k.x * chunk_size + (i + jx) * spacing
			var wz := k.y * chunk_size + (j + jz) * spacing
			var h = _height(wx, wz)
			if h == null or h < water_level:
				continue
			var n := _normal(wx, wz)
			if n.y < min_normal_y:
				continue
			var dens := _density(wx, wz, n.y)
			if keep > dens:
				continue

			var t := _pick_type(tr)
			var patch := 1.0 + _patch.get_noise_2d(wx, wz) * patch_strength
			var sxz := w_scale * _sizes[t]
			var sy := h_scale * patch * _sizes[t]

			var up := Vector3.UP.lerp(n, 0.65).normalized()
			var b := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw)
			b = b * Basis(Vector3.RIGHT, tilt_x) * Basis(Vector3.FORWARD, tilt_z)
			b = b.scaled(Vector3(sxz, sy, sxz))
			lists[t].append(Transform3D(b, Vector3(wx, h, wz) - origin))
	_apply.bind(k, ticket, lists).call_deferred()

func _apply(k: Vector2i, ticket: int, lists: Array) -> void:
	if _ticket.get(k, -1) != ticket or not _chunks.has(k):
		return
	var group: Array = _chunks[k]
	var total := 0
	for t in group.size():
		var nd: MultiMeshInstance3D = group[t]
		var list: Array = lists[t]
		var mm := nd.multimesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		nd.visible = true
		total += list.size()
	if not _printed:
		_printed = true
		print("GRASS chunk ", k, " placed ", total, " tufts")

func _height(wx: float, wz: float):
	var m: Vector3 = terrain.world_to_map(Vector3(wx, 0.0, wz))
	var r: int = _data.get_resolution()
	if m.x < 0.0 or m.z < 0.0 or m.x >= r - 1 or m.z >= r - 1:
		return null
	var h: float = _data.get_interpolated_height_at(m)
	return terrain.global_position.y + h * terrain.map_scale.y + height_offset

func _normal(wx: float, wz: float) -> Vector3:
	var d := 0.6
	var hl = _height(wx - d, wz)
	var hr = _height(wx + d, wz)
	var hd = _height(wx, wz - d)
	var hu = _height(wx, wz + d)
	if hl == null or hr == null or hd == null or hu == null:
		return Vector3.UP
	return Vector3(hl - hr, 2.0 * d, hd - hu).normalized()
