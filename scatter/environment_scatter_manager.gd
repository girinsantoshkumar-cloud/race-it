@tool
class_name EnvironmentScatterManager
extends Node3D
## Procedural prop scattering for HTerrain. Generated content lives ONLY under the child "_Generated";
## manually placed nodes are never touched. Same seed => same result.

enum GroundMode { AUTO, HTERRAIN_DATA, RAYCAST, TERRAIN3D }

const CONTAINER := "_Generated"
const HASH_CELL := 8.0
const ROAD_CELL := 16.0

@export var terrain: Node3D ## the HTerrain node
@export var categories: Array[ScatterCategory] = []
@export var seed_value := 12345
@export var generate_on_ready := true
## Saves generated nodes into the .tscn (bloats scene). Leave off; regenerate from seed instead.
@export var bake_into_scene := false

@export_group("Ground")
@export var ground_mode: GroundMode = GroundMode.AUTO
@export_flags_3d_physics var raycast_mask := 1
@export var ray_top := 1000.0
@export var ray_bottom := -500.0
## World-space XZ rect. Empty (zero area) = whole terrain.
@export var region_override := Rect2()

@export_group("Groups")
@export var road_group: StringName = &"scatter_road" ## Path3D nodes; optional meta "road_width"
@export var exclusion_group: StringName = &"scatter_exclusion"
## Manually placed large props (trees, rocks...) that procedural props should avoid. Optional meta "scatter_radius".
@export var blocker_group: StringName = &"scatter_blocker"

@export_group("Roads")
@export var default_road_width := 6.0
## Also treat road-generator RoadSegment nodes as roads (auto-detected).
@export var include_road_generator := false
@export var road_influence := 80.0

@export_group("Optional")
@export var grass_manager: Node
## Method on grass_manager to call after generation (leave empty to skip).
@export var grass_refresh_method: StringName = &""

@export_group("Actions")
@export_tool_button("Generate / Regenerate", "Reload") var _btn_gen = generate
@export_tool_button("Clear generated", "Remove") var _btn_clear = clear
@export_tool_button("Diagnostics", "Search") var _btn_diag = diagnostics

# ---- runtime state ----
var _data: Object
var _data_ok := false
var _use_data := false
var _t3d_data: Object
var _use_t3d := false
var _centered := false
var _res := 0
var _map_scale := Vector3.ONE
var _region := Rect2()
var _region_in := Rect2()
var _hash: Dictionary = {}
var _max_r := 2.0
var _road_grid: Dictionary = {}
var _seg_a := PackedVector2Array()
var _seg_b := PackedVector2Array()
var _seg_w := PackedFloat32Array()
var _roads: Array = []
var _exclusions: Array[ScatterExclusion] = []
var _placed_by_cat: Dictionary = {}
var _part_cache: Dictionary = {}
var _container: Node3D
var _gy := 0.0
var _gn := Vector3.UP
# per-category
var _cur_excl: Array = []
var _cur_noise: FastNoiseLite
var _cur_xfs: Array[Transform3D] = []
var _cur_vars := PackedInt32Array()
var _cur_pos := PackedVector3Array()


func _ready() -> void:
	if not Engine.is_editor_hint() and generate_on_ready:
		generate()


# ======================= public API =======================

func clear() -> void:
	var old := get_node_or_null(CONTAINER)
	if old:
		remove_child(old)
		old.free()
	_container = null


func generate() -> void:
	var t0 := Time.get_ticks_msec()
	clear()
	if terrain == null:
		push_error("EnvironmentScatterManager: assign `terrain` (HTerrain node).")
		return
	if not _setup_ground():
		return
	_validate_ground()
	_region = _compute_region()
	_region_in = _region.grow(-1.0)
	_collect_exclusions()
	_collect_roads()
	_hash.clear()
	_placed_by_cat.clear()
	_part_cache.clear()
	_max_r = 2.0
	for c in categories:
		if c:
			_max_r = maxf(_max_r, c.footprint_radius * c.scale_max + c.spacing_gap)
	_register_blockers()

	_container = Node3D.new()
	_container.name = CONTAINER
	_container.top_level = true
	add_child(_container)
	_container.global_transform = Transform3D.IDENTITY

	for c in categories:
		if c == null or not c.enabled or c.scenes.is_empty():
			continue
		_run_category(c)

	if bake_into_scene and Engine.is_editor_hint() and get_tree().edited_scene_root:
		_set_owner_recursive(_container, get_tree().edited_scene_root)
	if grass_manager and grass_refresh_method != &"" and grass_manager.has_method(grass_refresh_method):
		grass_manager.call(grass_refresh_method)
	print("[Scatter] done in %d ms" % (Time.get_ticks_msec() - t0))


func diagnostics() -> void:
	if terrain == null:
		print("[Scatter] terrain not assigned")
		return
	_setup_ground()
	print("[Scatter] terrain class=%s  get_data=%s  data_ok=%s  world_to_map=%s  map_to_world=%s  map_scale=%s"
		% [terrain.get_class(), terrain.has_method("get_data"), _data_ok,
		terrain.has_method("world_to_map"), terrain.has_method("map_to_world"), _map_scale])
	_region = _compute_region()
	print("[Scatter] mode: terrain3d=%s hterrain_data=%s centered=%s res=%d map_scale=%s" % [_use_t3d, _use_data, _centered, _res, _map_scale])
	print("[Scatter] region=", _region)
	_collect_exclusions()
	_collect_roads()
	print("[Scatter] roads found=%d (segments of %d m grid cells=%d), exclusions=%d" % [_roads.size(), 4, _road_grid.size(), _exclusions.size()])
	for r in _roads:
		print("[Scatter]   road %s width=%.1f length=%.1f" % [r.path.name, r.width, r.curve.get_baked_length()])
	var c := _region.get_center()
	if _use_t3d and _sample(c.x, c.y):
		print("[Scatter] terrain3d height at centre = ", _gy, "  normal = ", _gn)
	if _data_ok:
		var hd := _h_data(c.x, c.y)
		print("[Scatter] data height at centre = ", hd)
		var hit := _ray(c.x, c.y)
		if hit.is_empty():
			print("[Scatter] raycast: no hit (terrain collider off / not built in editor?)")
		else:
			print("[Scatter] raycast height = %s  diff = %s" % [hit.position.y, hit.position.y - hd])
			if absf(hit.position.y - hd) > 0.5:
				print("[Scatter] WARNING mismatch: set ground_mode = RAYCAST or check map_scale/centered.")


# ======================= ground =======================

func _setup_ground() -> bool:
	_data = null
	_t3d_data = null
	var t3d_ok := false
	if terrain.is_class("Terrain3D"):
		_t3d_data = terrain.get("data")
		t3d_ok = _t3d_data != null and _t3d_data.has_method("get_height") and _t3d_data.has_method("get_normal")
	_use_t3d = t3d_ok and (ground_mode == GroundMode.AUTO or ground_mode == GroundMode.TERRAIN3D)
	if ground_mode == GroundMode.TERRAIN3D and not t3d_ok:
		push_error("Scatter: terrain is not a Terrain3D node with data.get_height/get_normal.")
		return false
	if terrain.has_method("get_data"):
		_data = terrain.call("get_data")
	_data_ok = _data != null and _data.has_method("get_interpolated_height_at")
	_use_data = not _use_t3d and (ground_mode == GroundMode.HTERRAIN_DATA or (ground_mode == GroundMode.AUTO and _data_ok))
	if _use_data and not _data_ok:
		push_error("Scatter: HTerrain data API not found (get_data / get_interpolated_height_at). Use ground_mode = RAYCAST.")
		return false
	_map_scale = Vector3.ONE
	if "map_scale" in terrain:
		_map_scale = terrain.get("map_scale")
	_centered = "centered" in terrain and bool(terrain.get("centered"))
	_res = 0
	if _data != null and _data.has_method("get_resolution"):
		_res = int(_data.call("get_resolution"))
	return true


func _h_data(x: float, z: float) -> float:
	var m: Vector3
	if terrain.has_method("world_to_map"):
		m = terrain.call("world_to_map", Vector3(x, 0.0, z))
	else:
		var l := terrain.to_local(Vector3(x, 0.0, z))
		if _centered:
			l.x += (_res - 1) * _map_scale.x * 0.5
			l.z += (_res - 1) * _map_scale.z * 0.5
		m = Vector3(l.x / _map_scale.x, 0.0, l.z / _map_scale.z)
	var h: float = _data.call("get_interpolated_height_at", m)
	return terrain.global_position.y + h * _map_scale.y


func _ray(x: float, z: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, ray_top, z), Vector3(x, ray_bottom, z), raycast_mask)
	return get_world_3d().direct_space_state.intersect_ray(q)


## Sets _gy / _gn. Returns false if no ground.
func _sample(x: float, z: float) -> bool:
	if _use_t3d:
		var p := Vector3(x, 0.0, z)
		var h: float = _t3d_data.call("get_height", p)
		if is_nan(h):
			return false
		var n: Vector3 = _t3d_data.call("get_normal", p)
		if is_nan(n.x) or n == Vector3.ZERO:
			n = Vector3.UP
		_gy = h
		_gn = n
		return true
	if _use_data:
		_gy = _h_data(x, z)
		var e := 1.5
		_gn = Vector3(_h_data(x - e, z) - _h_data(x + e, z), 2.0 * e,
			_h_data(x, z - e) - _h_data(x, z + e)).normalized()
		return true
	var hit := _ray(x, z)
	if hit.is_empty():
		return false
	_gy = hit.position.y
	_gn = hit.normal
	return true


## Compares HTerrain data heights with physics raycasts at 5 points. Falls back to raycast on mismatch (AUTO mode).
func _validate_ground() -> void:
	if not _use_data:
		return
	var r := _compute_region()
	var total := 0.0
	var n := 0
	for f: Vector2 in [Vector2(0.5, 0.5), Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]:
		var p := r.position + r.size * f
		var hit := _ray(p.x, p.y)
		if hit.is_empty():
			continue
		total += absf(hit.position.y - _h_data(p.x, p.y))
		n += 1
	if n == 0:
		push_warning("[Scatter] Cannot validate heights: no terrain collider hit. Enable HTerrain collision / check raycast_mask.")
		return
	var avg := total / n
	if avg > 0.75:
		push_warning("[Scatter] Height mismatch (avg %.2f m, centered=%s, map_scale=%s)." % [avg, _centered, _map_scale])
		if ground_mode == GroundMode.AUTO:
			push_warning("[Scatter] Falling back to RAYCAST ground sampling.")
			_use_data = false
	else:
		print("[Scatter] Height check OK (avg diff %.2f m, centered=%s)" % [avg, _centered])


func _compute_region() -> Rect2:
	if region_override.has_area():
		return region_override
	if _use_t3d and _t3d_data.has_method("get_region_locations"):
		var rs := float(terrain.get("region_size"))
		var sp := 1.0
		if "vertex_spacing" in terrain:
			sp = float(terrain.get("vertex_spacing"))
		var locs: Array = _t3d_data.call("get_region_locations")
		if not locs.is_empty():
			var mn := Vector2(INF, INF)
			var mx := Vector2(-INF, -INF)
			for l in locs:
				var lv := Vector2(l)
				mn = mn.min(lv * rs * sp)
				mx = mx.max((lv + Vector2.ONE) * rs * sp)
			return Rect2(mn, mx - mn)
	if _data != null and _data.has_method("get_resolution"):
		var res: int = _data.call("get_resolution")
		var a: Vector3
		var b: Vector3
		if terrain.has_method("map_to_world"):
			a = terrain.call("map_to_world", Vector3(0, 0, 0))
			b = terrain.call("map_to_world", Vector3(res - 1, 0, res - 1))
		else:
			var off := Vector3.ZERO
			if _centered:
				off = Vector3(-(res - 1) * _map_scale.x * 0.5, 0.0, -(res - 1) * _map_scale.z * 0.5)
			a = terrain.to_global(off)
			b = terrain.to_global(off + Vector3((res - 1) * _map_scale.x, 0, (res - 1) * _map_scale.z))
		var mn := Vector2(minf(a.x, b.x), minf(a.z, b.z))
		var mx := Vector2(maxf(a.x, b.x), maxf(a.z, b.z))
		return Rect2(mn, mx - mn)
	push_warning("Scatter: cannot derive terrain size; set region_override.")
	return Rect2(-250, -250, 500, 500)


# ======================= exclusions / roads / blockers =======================

func _collect_exclusions() -> void:
	_exclusions.clear()
	for n in get_tree().get_nodes_in_group(exclusion_group):
		if n is ScatterExclusion:
			_exclusions.append(n)


func _collect_roads() -> void:
	_roads.clear()
	_road_grid.clear()
	_seg_a.clear()
	_seg_b.clear()
	_seg_w.clear()
	for n in _road_nodes():
		var path := n as Node3D
		if path == null:
			continue
		var curve: Curve3D = path.get("curve")
		if curve == null or curve.point_count < 2:
			continue
		var w := _road_width(path)
		var L := curve.get_baked_length()
		var pts := PackedVector3Array()
		var s := 0.0
		while s < L:
			pts.append(path.to_global(curve.sample_baked(s)))
			s += 4.0
		pts.append(path.to_global(curve.sample_baked(L)))
		_roads.append({"path": path, "curve": curve, "width": w})
		for i in range(pts.size() - 1):
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			var idx := _seg_a.size()
			_seg_a.append(a)
			_seg_b.append(b)
			_seg_w.append(w)
			var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * road_influence
			var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * road_influence
			for cx in range(floori(mn.x / ROAD_CELL), floori(mx.x / ROAD_CELL) + 1):
				for cz in range(floori(mn.y / ROAD_CELL), floori(mx.y / ROAD_CELL) + 1):
					var key := Vector2i(cx, cz)
					var arr: PackedInt32Array = _road_grid.get(key, PackedInt32Array())
					arr.append(idx)
					_road_grid[key] = arr


func _road_nodes() -> Array:
	var out: Array = get_tree().get_nodes_in_group(road_group).duplicate()
	var root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if include_road_generator and root:
		_find_road_segments(root, out)
	return out


func _find_road_segments(n: Node, out: Array) -> void:
	if n is Node3D and "curve" in n and "start_point" in n and "end_point" in n:
		if not out.has(n):
			out.append(n)
		return
	for ch in n.get_children():
		_find_road_segments(ch, out)


func _road_width(n: Node) -> float:
	if n.has_meta("road_width"):
		return float(n.get_meta("road_width"))
	var sp = n.get("start_point")
	if sp != null and "lanes" in sp and "lane_width" in sp:
		var w := float(sp.lane_width) * float(sp.lanes.size())
		for k in ["shoulder_width_l", "shoulder_width_r"]:
			if k in sp:
				w += float(sp.get(k))
		return maxf(w, 2.0)
	return default_road_width


## Distance to nearest road EDGE (INF if beyond road_influence).
func _road_dist(x: float, z: float) -> float:
	if _road_grid.is_empty():
		return INF
	var arr: PackedInt32Array = _road_grid.get(Vector2i(floori(x / ROAD_CELL), floori(z / ROAD_CELL)), PackedInt32Array())
	var p := Vector2(x, z)
	var best := INF
	for i in arr:
		var a := _seg_a[i]
		var ab := _seg_b[i] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t) - _seg_w[i] * 0.5)
	return best


func _register_blockers() -> void:
	for n in get_tree().get_nodes_in_group(blocker_group):
		var n3 := n as Node3D
		if n3 == null or n3 == self:
			continue
		var r := float(n3.get_meta("scatter_radius", 3.0))
		_max_r = maxf(_max_r, r)
		_register(n3.global_position.x, n3.global_position.z, r)


# ======================= spatial hash (large props) =======================

func _register(x: float, z: float, r: float) -> void:
	var key := Vector2i(floori(x / HASH_CELL), floori(z / HASH_CELL))
	var arr: PackedVector3Array = _hash.get(key, PackedVector3Array())
	arr.append(Vector3(x, z, r))
	_hash[key] = arr
	_max_r = maxf(_max_r, r)


func _blocked(x: float, z: float, r: float) -> bool:
	var span := int(ceil((r + _max_r) / HASH_CELL))
	var cx := floori(x / HASH_CELL)
	var cz := floori(z / HASH_CELL)
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var arr: PackedVector3Array = _hash.get(Vector2i(cx + dx, cz + dz), PackedVector3Array())
			for e in arr:
				var rr := e.z + r
				var ddx := e.x - x
				var ddz := e.y - z
				if ddx * ddx + ddz * ddz < rr * rr:
					return true
	return false


# ======================= category run =======================

func _run_category(c: ScatterCategory) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, c.category_name])
	_cur_xfs.clear()
	_cur_vars.clear()
	_cur_pos.clear()
	_cur_excl = _exclusions.filter(func(e: ScatterExclusion): return e.affects_category(c.category_name))
	_cur_noise = null
	if c.use_noise:
		_cur_noise = FastNoiseLite.new()
		_cur_noise.seed = rng.seed & 0x7fffffff
		_cur_noise.frequency = c.noise_frequency
		_cur_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	if c.mode == ScatterCategory.Mode.ALONG_ROADS:
		_scatter_along_roads(c, rng)
	else:
		_scatter_area(c, rng)

	_placed_by_cat[c.category_name] = _cur_pos.duplicate()
	print("[Scatter] %s: %d placed (target %d)" % [c.category_name, _cur_xfs.size(), c.count])
	_build_category(c)


func _scatter_area(c: ScatterCategory, rng: RandomNumberGenerator) -> void:
	# anchors for "near" placement
	var anchors := PackedVector3Array()
	if c.near_category != "" and _placed_by_cat.has(c.near_category):
		anchors.append_array(_placed_by_cat[c.near_category])
	if c.near_group != &"":
		for n in get_tree().get_nodes_in_group(c.near_group):
			if n is Node3D:
				anchors.append(n.global_position)
	# cluster centres
	var centers := PackedVector2Array()
	if c.cluster_fraction > 0.0 and c.cluster_count > 0:
		var tries := c.cluster_count * 20
		while centers.size() < c.cluster_count and tries > 0:
			tries -= 1
			var p := _rand_in_region(rng)
			if _filters_ok(c, rng, p.x, p.y, true):
				centers.append(p)

	var target := c.count
	var attempts := int(target * c.attempts_multiplier)
	var placed := 0
	for i in attempts:
		if placed >= target:
			break
		var x: float
		var z: float
		var roll := rng.randf()
		if not anchors.is_empty() and roll < c.near_fraction:
			var a := anchors[rng.randi() % anchors.size()]
			var ang := rng.randf() * TAU
			var d := rng.randf_range(c.near_min_distance, c.near_max_distance)
			x = a.x + cos(ang) * d
			z = a.z + sin(ang) * d
		elif not centers.is_empty() and rng.randf() < c.cluster_fraction:
			var ctr := centers[rng.randi() % centers.size()]
			var ang2 := rng.randf() * TAU
			var d2 := absf(rng.randfn(0.0, 0.5)) * c.cluster_radius
			x = ctr.x + cos(ang2) * d2
			z = ctr.y + sin(ang2) * d2
		else:
			var p2 := _rand_in_region(rng)
			x = p2.x
			z = p2.y
		if _try_place(c, rng, x, z, NAN, true):
			placed += 1


func _scatter_along_roads(c: ScatterCategory, rng: RandomNumberGenerator) -> void:
	for r in _roads:
		var path: Node3D = r.path
		var curve: Curve3D = r.curve
		var w: float = r.width
		var L := curve.get_baked_length()
		var s := rng.randf() * c.road_spacing
		while s < L:
			var p0 := path.to_global(curve.sample_baked(s))
			var p1 := path.to_global(curve.sample_baked(minf(s + 1.0, L)))
			if s + 1.0 > L:
				p1 = p0
				p0 = path.to_global(curve.sample_baked(maxf(s - 1.0, 0.0)))
			var t := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
			if t.length_squared() > 0.0001:
				t = t.normalized()
				var nrm := Vector3(-t.z, 0.0, t.x)
				for side in [-1.0, 1.0]:
					if not c.road_both_sides and side < 0.0:
						continue
					if rng.randf() > c.road_side_chance:
						continue
					var off := w * 0.5 + c.road_side_offset + rng.randf() * 0.5
					var base: Vector3 = p0 + nrm * off * side
					var n := rng.randi_range(c.group_min, maxi(c.group_min, c.group_max))
					for k in n:
						var jx := 0.0
						var jz := 0.0
						if n > 1:
							var a := rng.randf() * TAU
							var d := sqrt(rng.randf()) * c.group_radius
							jx = cos(a) * d
							jz = sin(a) * d
						var yaw := NAN
						if c.face_road:
							var dir: Vector3 = -nrm * side
							yaw = atan2(dir.x, dir.z) + deg_to_rad(c.yaw_offset_deg)
						_try_place(c, rng, base.x + jx, base.z + jz, yaw, false)
			s += c.road_spacing * (1.0 + rng.randf_range(-c.road_spacing_jitter, c.road_spacing_jitter))


func _rand_in_region(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(
		rng.randf_range(_region_in.position.x, _region_in.end.x),
		rng.randf_range(_region_in.position.y, _region_in.end.y))


func _filters_ok(c: ScatterCategory, rng: RandomNumberGenerator, x: float, z: float, use_road: bool) -> bool:
	var p := Vector2(x, z)
	for e in _cur_excl:
		if e.signed_distance(p) < c.exclusion_margin:
			return false
	if use_road and not _road_grid.is_empty():
		var d := _road_dist(x, z)
		if d < c.road_clear_distance:
			return false
		if c.road_fade_distance > 0.0 and d < INF:
			var f := smoothstep(c.road_clear_distance, c.road_clear_distance + c.road_fade_distance, d)
			if rng.randf() > lerpf(c.min_density_near_road, 1.0, f):
				return false
	if _cur_noise:
		var n01 := _cur_noise.get_noise_2d(x, z) * 0.5 + 0.5
		var th := c.noise_threshold
		if rng.randf() > smoothstep(th - c.noise_softness, th + c.noise_softness, n01):
			return false
	return true


func _try_place(c: ScatterCategory, rng: RandomNumberGenerator, x: float, z: float, forced_yaw: float, use_road: bool) -> bool:
	if not _region_in.has_point(Vector2(x, z)):
		return false
	if not _filters_ok(c, rng, x, z, use_road):
		return false
	if not _sample(x, z):
		return false
	if rad_to_deg(acos(clampf(_gn.y, -1.0, 1.0))) > c.max_slope_deg:
		return false
	if _gy < c.min_height or _gy > c.max_height:
		return false
	var xf := _make_xform(c, rng, Vector3(x, _gy, z), _gn, forced_yaw)
	var r := c.footprint_radius * xf.basis.get_scale().y
	if c.avoid_large and _blocked(x, z, r + c.spacing_gap):
		return false
	if c.register_as_large:
		_register(x, z, r)
	_cur_xfs.append(xf)
	_cur_vars.append(_pick_variant(c, rng))
	_cur_pos.append(xf.origin)
	return true


func _pick_variant(c: ScatterCategory, rng: RandomNumberGenerator) -> int:
	var n := c.scenes.size()
	if c.weights.size() != n:
		return rng.randi() % n
	var total := 0.0
	for w in c.weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return rng.randi() % n
	var r := rng.randf() * total
	for i in n:
		r -= maxf(c.weights[i], 0.0)
		if r <= 0.0:
			return i
	return n - 1


func _make_xform(c: ScatterCategory, rng: RandomNumberGenerator, pos: Vector3, nrm: Vector3, forced_yaw: float) -> Transform3D:
	var s := rng.randf_range(c.scale_min, c.scale_max)
	var j := c.scale_xz_jitter
	var sx := s * (1.0 + rng.randf_range(-j, j))
	var sz := s * (1.0 + rng.randf_range(-j, j))
	var up := Vector3.UP.lerp(nrm, c.align_to_normal).normalized()
	var yaw := forced_yaw
	if is_nan(yaw):
		yaw = rng.randf() * TAU if c.random_yaw else 0.0
	var b := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw)
	if c.tilt_max_deg > 0.0:
		b = b * Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(-c.tilt_max_deg, c.tilt_max_deg))) \
			* Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(-c.tilt_max_deg, c.tilt_max_deg)))
	b = b.scaled_local(Vector3(sx, s, sz))
	pos.y -= c.sink * s
	return Transform3D(b, pos)


# ======================= building nodes =======================

func _build_category(c: ScatterCategory) -> void:
	if _cur_xfs.is_empty():
		return
	var root := Node3D.new()
	root.name = c.category_name
	_container.add_child(root)

	if c.render == ScatterCategory.Render.NODES:
		for i in _cur_xfs.size():
			var inst := c.scenes[_cur_vars[i]].instantiate() as Node3D
			if inst:
				root.add_child(inst)
				inst.transform = _cur_xfs[i]
		return

	# group by (variant, chunk)
	var groups: Dictionary = {}
	var chunks: Dictionary = {}
	for i in _cur_xfs.size():
		var p := _cur_xfs[i].origin
		var cx := floori(p.x / c.chunk_size)
		var cz := floori(p.z / c.chunk_size)
		var key := Vector3i(_cur_vars[i], cx, cz)
		var arr: Array = groups.get(key, [])
		arr.append(_cur_xfs[i])
		groups[key] = arr
		if c.collision_radius > 0.0:
			var ck := Vector2i(cx, cz)
			var carr: Array = chunks.get(ck, [])
			carr.append(_cur_xfs[i])
			chunks[ck] = carr

	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if c.cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for key in groups:
		var xs: Array = groups[key]
		var parts := _get_parts(c.scenes[key.x])
		for part in parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part.mesh
			mm.instance_count = xs.size()
			for i in xs.size():
				mm.set_instance_transform(i, xs[i] * part.xf)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = shadow
			if part.mat:
				mmi.material_override = part.mat
			if c.draw_distance > 0.0:
				mmi.visibility_range_end = c.draw_distance
			root.add_child(mmi)

	if c.collision_radius > 0.0:
		var shape := CylinderShape3D.new()
		shape.radius = c.collision_radius
		shape.height = c.collision_height
		for ck in chunks:
			var body := StaticBody3D.new()
			body.collision_layer = c.collision_layer
			body.collision_mask = 0
			root.add_child(body)
			for xf: Transform3D in chunks[ck]:
				var cs := CollisionShape3D.new()
				cs.shape = shape
				var sc := xf.basis.get_scale().y
				cs.transform = Transform3D(Basis.from_scale(Vector3(sc, sc, sc)),
					xf.origin + Vector3.UP * c.collision_height * 0.5 * sc)
				body.add_child(cs)


## Mesh parts of a scene: [{mesh, xf (relative to scene root), mat}]
func _get_parts(scene: PackedScene) -> Array:
	if _part_cache.has(scene):
		return _part_cache[scene]
	var out: Array = []
	var inst := scene.instantiate()
	_collect_parts(inst, Transform3D.IDENTITY, out, true)
	inst.free()
	_part_cache[scene] = out
	return out


func _collect_parts(n: Node, parent_xf: Transform3D, out: Array, is_root: bool) -> void:
	var xf := parent_xf
	if n is Node3D and not is_root:
		xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		out.append({"mesh": mi.mesh, "xf": xf, "mat": mi.material_override})
	for ch in n.get_children():
		_collect_parts(ch, xf, out, false)


func _set_owner_recursive(n: Node, o: Node) -> void:
	n.owner = o
	for ch in n.get_children():
		_set_owner_recursive(ch, o)
