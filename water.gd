@tool
extends MeshInstance3D
# Optional helper. The shader works without it when SCENE_DEPTH is on.
# It sets cheap render flags, can bake HTerrain depth, and provides get_height() for floating objects.

@export var terrain: Node                  # optional: HTerrain, only used when SCENE_DEPTH is off
@export var max_depth := 20.0
@export var mask_resolution := 512
@export var rebake := false:
	set(v):
		rebake = false
		if v and is_inside_tree():
			_setup()
@export_group("Mesh (optional)")
@export var rebuild_mesh := false
@export var mesh_size := 320.0
@export var mesh_subdivisions := 80
@export var view_distance := 0.0
@export_group("Performance")
@export_range(0.5, 1.0, 0.05) var render_scale := 0.75
var _waves: Array[Vector4] = []
var _speed := 0.22
var _wd: Array[Vector4] = []        # dir.x, dir.y, k, speed
var _wa: PackedFloat32Array = []    # amplitude
func _ready() -> void:
	_setup()
	if not Engine.is_editor_hint() and render_scale < 1.0:
		var vp := get_viewport()
		vp.scaling_3d_scale = render_scale
		if RenderingServer.get_current_rendering_method() == "forward_plus":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
func _param(m: ShaderMaterial, pname: String) -> Variant:
	var v: Variant = m.get_shader_parameter(pname)
	if v == null and m.shader:
		v = RenderingServer.shader_get_parameter_default(m.shader.get_rid(), pname)
	return v

func _setup() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	extra_cull_margin = 16.0
	if view_distance > 0.0:
		visibility_range_end = view_distance
	if rebuild_mesh and not Engine.is_editor_hint():
		var pm := PlaneMesh.new()
		pm.size = Vector2(mesh_size, mesh_size)
		pm.subdivide_width = mesh_subdivisions
		pm.subdivide_depth = mesh_subdivisions
		mesh = pm

	var m := material_override as ShaderMaterial
	if m == null:
		push_error("Water: Material Override must be a ShaderMaterial")
		return

	# Waves are read from the material, so change them in ONE place (the material)
	_waves.clear()
	for n in ["wave_a", "wave_b", "wave_c"]:
		var v: Variant = _param(m, n)
		if v is Vector4:
			_waves.append(v)
	var s: Variant = _param(m, "wave_speed")
	if s != null:
		_speed = float(s)
		_wd.clear()
		_wa.clear()
		for w in _waves:
			var d := Vector2(w.x, w.y).normalized()
			var k := TAU / w.w
			_wd.append(Vector4(d.x, d.y, k, sqrt(9.8 / k) * _speed))
			_wa.append(w.z / k)
	m.set_shader_parameter("max_depth", max_depth)
	if m.get_shader_parameter("normal_map") == null:
		m.set_shader_parameter("normal_map", _make_normal_map())
	if terrain:
		_bake_depth_mask(m)

func _make_normal_map() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 8.0
	tex.noise = noise
	return tex

func _bake_depth_mask(m: ShaderMaterial) -> void:
	var data = terrain.get_data()
	if data == null:
		return
	var img: Image = data.get_image(0).duplicate()   # 0 = height channel
	img.convert(Image.FORMAT_RF)
	var src_res: int = img.get_width()
	var src: PackedFloat32Array = img.get_data().to_float32_array()

	var n := mask_resolution
	var y_scale: float = terrain.map_scale.y
	var y_off: float = terrain.global_position.y
	var water_y: float = global_position.y
	var inv := 1.0 / max_depth
	var ratio := float(src_res - 1) / float(n - 1)

	var bytes := PackedByteArray()
	bytes.resize(n * n)
	for y in n:
		var row := roundi(y * ratio) * src_res
		for x in n:
			var ground: float = src[row + roundi(x * ratio)] * y_scale + y_off
			bytes[y * n + x] = int(255.0 * clampf((water_y - ground) * inv, 0.0, 1.0))

	var mask := Image.create_from_data(n, n, false, Image.FORMAT_L8, bytes)
	var size: float = terrain.map_scale.x * (src_res - 1)
	var origin := Vector2(terrain.global_position.x, terrain.global_position.z)
	if terrain.get("centered") == true:
		origin -= Vector2(size, size) * 0.5
	m.set_shader_parameter("depth_mask", ImageTexture.create_from_image(mask))
	m.set_shader_parameter("mask_origin", origin)
	m.set_shader_parameter("mask_size", size)
	m.set_shader_parameter("mask_res", float(n))

func get_height(p: Vector3) -> float:
	var t := fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	var h := global_position.y
	for i in _wd.size():
		var w := _wd[i]
		h += _wa[i] * sin(w.z * (w.x * p.x + w.y * p.z - w.w * t))
	return h
