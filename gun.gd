extends Node3D

@export var damage := 25
@export var start_ready := true
@export var fire_rate := 0.35
@export var max_range := 200.0
@export var hit_mask := 0xFFFFFFFF
@export var crosshair_offset := Vector2.ZERO
@export var debug_shots := false

@export_group("Muzzle flash")
@export var muzzle_node: Node3D                      # Marker3D at the barrel tip (recommended)
@export var flash_scale := 1.0                       # overall flash size
@export var flash_light_energy := 6.0
@export var smoke_enabled := true
@export var sparks_enabled := true

@export_group("Tracer / recoil")
@export var flash_color := Color(1.0, 0.75, 0.3)
@export var tracer_enabled := true
@export var tracer_width := 0.015
@export var tracer_time := 0.07
@export var recoil_enabled := true
@export var recoil_kick := 0.06
@export var recoil_pitch := 3.0
@export var shot_sound: AudioStream

@onready var anim: AnimationPlayer = $gun_anim_player

var can_shoot := false
var _cooldown := 0.0
var _base_pos := Vector3.ZERO
var _base_rot := Vector3.ZERO
var _recoil_tween: Tween
var _flash_light: OmniLight3D
var _audio: AudioStreamPlayer3D
var _exclude: Array[RID] = []

func _ready() -> void:
	can_shoot = start_ready
	_base_pos = position
	_base_rot = rotation_degrees

	var n: Node = self
	while n:
		if n is CollisionObject3D:
			_exclude.append((n as CollisionObject3D).get_rid())
		n = n.get_parent()

	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.6, 0.2)
	_flash_light.light_energy = flash_light_energy
	_flash_light.omni_range = 7.0
	_flash_light.shadow_enabled = false
	_flash_light.visible = false
	add_child(_flash_light)

	if shot_sound:
		_audio = AudioStreamPlayer3D.new()
		_audio.stream = shot_sound
		add_child(_audio)

func _process(delta: float) -> void:
	_cooldown = max(_cooldown - delta, 0.0)
	if not is_visible_in_tree():
		return
	if Input.is_action_pressed("shoot_out") and can_shoot and _cooldown <= 0.0:
		_shoot()

func _shoot() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	can_shoot = false
	_cooldown = fire_rate
	if anim and anim.has_animation("shoot"):
		anim.play("shoot")
	else:
		can_shoot = true

	# Ray from the camera through the crosshair
	var screen_pos := get_viewport().get_visible_rect().size * 0.5 + crosshair_offset
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var end := origin + dir * max_range

	var query := PhysicsRayQueryParameters3D.create(origin, end, hit_mask)
	query.exclude = _exclude
	var result := get_world_3d().direct_space_state.intersect_ray(query)

	var aim_point := end
	if not result.is_empty():
		aim_point = result.position
		var hit = result.collider
		var normal: Vector3 = result.normal
		if debug_shots:
			print("Shot hit: ", hit.name)
		if hit and hit.has_method("take_damage"):
			hit.take_damage(damage)
			_impact(aim_point, normal, Color(0.7, 0.02, 0.02), 14, 4.0, 0.5, 0.03)   # blood
		else:
			_impact(aim_point, normal, Color(1.0, 0.8, 0.4), 10, 5.0, 0.35, 0.02)    # sparks
	elif debug_shots:
		print("Shot hit nothing")

	var muzzle := muzzle_node.global_position if muzzle_node else global_position
	var flash_dir := (aim_point - muzzle).normalized()
	_muzzle_flash(muzzle, flash_dir)
	if tracer_enabled:
		_tracer(muzzle, aim_point)
	if recoil_enabled:
		_recoil()
	if _audio:
		_audio.play()

# ---------------- muzzle flash ----------------

func _muzzle_flash(pos: Vector3, dir: Vector3) -> void:
	var s := flash_scale

	# light flash
	_flash_light.global_position = pos
	_flash_light.visible = true
	get_tree().create_timer(0.06).timeout.connect(func(): _flash_light.visible = false)

	# hot white-yellow core, stretched forward like the flame in a barrel shot
	_flame_core(pos, dir, Color(1.0, 0.95, 0.7), 0.07 * s, Vector3(1.0, 1.0, 3.2), 0.07)
	# wider orange fireball wrapped around it
	_flame_core(pos, dir, Color(1.0, 0.45, 0.08), 0.11 * s, Vector3(1.0, 1.0, 2.0), 0.10)

	# billowing fire cone
	_particles(pos, dir, 16, 0.14, 2.0 * s, 6.0 * s, 20.0, 0.07 * s, Vector3.ZERO,
		[Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.5, 0.1, 0.9), Color(0.5, 0.1, 0.0, 0.0)],
		[0.0, 0.35, 1.0], true, 1.0, 0.2)

	# flying sparks
	if sparks_enabled:
		_particles(pos, dir, 12, 0.3, 8.0 * s, 16.0 * s, 28.0, 0.012 * s, Vector3(0, -9.8, 0),
			[Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.5, 0.1, 1.0), Color(1.0, 0.3, 0.0, 0.0)],
			[0.0, 0.5, 1.0], true, 1.0, 0.4)

	# smoke puff
	if smoke_enabled:
		_particles(pos, dir, 6, 0.7, 0.4, 1.4, 35.0, 0.06 * s, Vector3(0, 0.6, 0),
			[Color(0.55, 0.55, 0.55, 0.0), Color(0.5, 0.5, 0.5, 0.35), Color(0.35, 0.35, 0.35, 0.0)],
			[0.0, 0.2, 1.0], false, 0.6, 2.6)

# stretched glowing blob that pops and fades, aimed along the barrel
func _flame_core(pos: Vector3, dir: Vector3, color: Color, radius: float, stretch: Vector3, life: float) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color

	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	sph.radial_segments = 10
	sph.rings = 5
	sph.material = m

	var mi := MeshInstance3D.new()
	mi.mesh = sph
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos + dir * radius * stretch.z * 0.6
	var up := Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT
	mi.look_at(mi.global_position + dir, up)
	mi.scale = stretch * 0.4

	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", stretch * 1.3, life)
	tw.tween_property(m, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(mi.queue_free)

# generic one-shot particle burst with a colour ramp and shrink/grow curve
func _particles(pos: Vector3, dir: Vector3, amount: int, life: float, v_min: float, v_max: float,
		spread: float, size: float, gravity: Vector3, colors: Array, offsets: Array,
		additive: bool, scale_start: float, scale_end: float) -> void:
	var p := GPUParticles3D.new()

	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var gt := GradientTexture1D.new()
	gt.gradient = g

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, scale_start))
	curve.add_point(Vector2(1.0, scale_end))
	var ct := CurveTexture.new()
	ct.curve = curve

	var mat := ParticleProcessMaterial.new()
	mat.direction = dir
	mat.spread = spread
	mat.initial_velocity_min = v_min
	mat.initial_velocity_max = v_max
	mat.gravity = gravity
	mat.color_ramp = gt
	mat.scale_curve = ct
	mat.scale_min = 0.7
	mat.scale_max = 1.3
	p.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.material = m
	p.draw_pass_1 = mesh

	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)

# ---------------- impact / tracer / recoil ----------------

func _impact(pos: Vector3, normal: Vector3, color: Color, amount: int, speed: float, life: float, size: float) -> void:
	_particles(pos, normal, amount, life, speed * 0.5, speed, 40.0, size, Vector3(0, -9.8, 0),
		[color, color, Color(color.r, color.g, color.b, 0.0)], [0.0, 0.6, 1.0], false, 1.0, 0.5)

func _tracer(from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	if dist < 0.2:
		return

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = flash_color

	var box := BoxMesh.new()
	box.size = Vector3(tracer_width, tracer_width, dist)
	box.material = m

	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	get_tree().current_scene.add_child(mi)
	mi.global_position = (from + to) * 0.5
	var d := (to - from).normalized()
	var up := Vector3.UP if abs(d.y) < 0.99 else Vector3.RIGHT
	mi.look_at(to, up)

	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, tracer_time)
	tw.tween_callback(mi.queue_free)

func _recoil() -> void:
	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()
	position = _base_pos + Vector3(0.0, 0.0, recoil_kick)
	rotation_degrees.x = _base_rot.x + recoil_pitch
	_recoil_tween = create_tween().set_parallel(true)
	_recoil_tween.tween_property(self, "position", _base_pos, 0.12)
	_recoil_tween.tween_property(self, "rotation_degrees:x", _base_rot.x, 0.12)

# ---------------- animation signal ----------------

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "shoot" or anim_name == "equip":
		can_shoot = true
	elif anim_name == "unequip":
		can_shoot = false
