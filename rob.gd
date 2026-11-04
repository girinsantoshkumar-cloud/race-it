extends CharacterBody3D

signal damaged(amount: float, health: float)
signal died

@export var max_health := 100.0
@export var regen_delay := 0.0
@export var regen_per_sec := 5.0
@export var show_hud := true
@export var restart_on_death := true
@export var restart_delay := 3.0
@export var hit_sound: AudioStream
@export var debug := false

@export_group("Heart")
@export var heart_texture: Texture2D           # drag hg.png here
@export var heart_height := 170.0              # width follows the image proportions
@export var heart_margin := Vector2(30, 30)
@export_range(0.05, 1.0) var green_below := 0.45
@export var sick_color := Color(0.35, 0.95, 0.2)
@export_range(0.0, 1.0) var sick_strength := 0.75
@export var show_number := true
@export var heartbeat := true

@export_group("Bar")
@export var bar_height := 16.0
@export var bar_gap := 8.0
@export var bar_min_width := 150.0
@export var bar_color := Color(0.85, 0.05, 0.08)

@export_group("Animation")
@export var intro_fill := true
@export var fill_speed := 0.7
@export var trail_delay := 0.35
@export var trail_speed := 0.35

@export_group("Blood")
@export var blood_color := Color(0.6, 0.02, 0.03)
@export var blood_burst_amount := 30
@export var drip_below := 0.5

@export_group("State")
@export var is_active := true
@export var is_sprinting := false
@export var walk_speed := 5.0
@export var sprint_speed := 8.0

var health := 0.0
var is_dead := false

var _since_hit := 0.0
var _shown := 0.0
var _trail := 1.0
var _trail_wait := 0.0

var _heart: HeartDisplay
var _bar: BarDisplay
var _flash: ColorRect
var _label: Label
var _death_label: Label
var _audio: AudioStreamPlayer
var _burst: CPUParticles2D
var _drip: CPUParticles2D
var _drip_top: CPUParticles2D
var _burst_top: CPUParticles2D
var _heart_mat: ShaderMaterial
var _bar_mat: ShaderMaterial


class HeartDisplay extends Control:
	var shown := 1.0
	var trail := 1.0
	var tex: Texture2D
	var beat_speed := 1.5
	var beat_enabled := true
	var punch := 0.0
	var _t := 0.0

	func _process(delta: float) -> void:
		pivot_offset = size * 0.5
		punch = move_toward(punch, 0.0, delta * 1.8)
		var s := 1.0 + punch * 0.15
		if beat_enabled:
			_t += delta * beat_speed * TAU
			var a := maxf(sin(_t), 0.0)
			var b := maxf(sin(_t * 2.0 + 1.2), 0.0) * 0.5
			s += 0.04 * a * a + 0.02 * b * b
		scale = Vector2(s, s)

	func _fill(r: float, col: Color) -> void:
		if r <= 0.0 or tex == null:
			return
		var ts := tex.get_size()
		var h := size.y * r
		draw_texture_rect_region(tex,
			Rect2(0.0, size.y - h, size.x, h),
			Rect2(0.0, ts.y * (1.0 - r), ts.x, ts.y * r), col)

	func _draw() -> void:
		if tex == null:
			return
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false, Color(0.12, 0.1, 0.1, 0.7))
		if trail > shown:
			_fill(trail, Color(1.0, 0.85, 0.85, 0.55))
		_fill(shown, Color.WHITE)


class BarDisplay extends Control:
	var shown := 1.0
	var trail := 1.0
	var fill_color := Color(0.85, 0.05, 0.08)

	func _draw() -> void:
		var full := Rect2(Vector2.ZERO, size)
		draw_rect(full, Color(0, 0, 0, 0.7))
		var inner := full.grow(-3.0)
		if trail > shown:
			draw_rect(Rect2(inner.position, Vector2(inner.size.x * trail, inner.size.y)), Color(1, 1, 1, 0.5))
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * shown, inner.size.y)), fill_color)
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * shown, inner.size.y * 0.4)), Color(1, 1, 1, 0.15))
		draw_rect(full, Color(1, 1, 1, 0.85), false, 2.0)


func _ready() -> void:
	add_to_group("player_health")
	add_to_group("player")
	health = max_health
	_shown = 0.0 if intro_fill else 1.0
	_trail = _shown
	if hit_sound:
		_audio = AudioStreamPlayer.new()
		_audio.stream = hit_sound
		add_child(_audio)
	if show_hud:
		_build_hud()
	_update_hud()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if is_dead or not is_active:
		velocity.x = move_toward(velocity.x, 0.0, 5.0)
		velocity.z = move_toward(velocity.z, 0.0, 5.0)
		move_and_slide()
		return

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = 4.5

	# axis order matches your scene (Rob faces +Z)
	var input_dir := Input.get_vector("right", "left", "backward", "forward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	is_sprinting = Input.is_key_pressed(KEY_SHIFT) and direction != Vector3.ZERO
	var speed := sprint_speed if is_sprinting else walk_speed

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if is_dead or not is_active:
		return
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.002)
		var camera_pivot := get_node_or_null("CameraPivot") as Node3D
		if camera_pivot:
			camera_pivot.rotate_x(event.relative.y * 0.002)
			camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.5, 1.5)

func _process(delta: float) -> void:
	if not is_dead and regen_delay > 0.0:
		_since_hit += delta
		if _since_hit >= regen_delay and health < max_health:
			health = minf(health + regen_per_sec * delta, max_health)
			_update_hud()

	if _heart == null:
		return

	var ratio := clampf(health / max_health, 0.0, 1.0)
	_shown = move_toward(_shown, ratio, fill_speed * delta)

	if _trail < _shown:
		_trail = _shown
	elif _trail > _shown:
		if _trail_wait > 0.0:
			_trail_wait -= delta
		else:
			_trail = move_toward(_trail, _shown, trail_speed * delta)

	_heart.shown = _shown
	_heart.trail = _trail
	_bar.shown = _shown
	_bar.trail = _trail
	_heart.queue_redraw()
	_bar.queue_redraw()

	if show_number:
		_label.text = "%d" % int(ceil(_shown * max_health))

	var bleeding := (not is_dead) and ratio <= drip_below and ratio > 0.0
	_drip.emitting = bleeding
	_drip_top.emitting = bleeding

func take_damage(amount: float = 10.0) -> void:
	if is_dead:
		return
	health = maxf(health - amount, 0.0)
	_since_hit = 0.0
	_trail_wait = trail_delay
	damaged.emit(amount, health)
	if debug:
		print("Rob took ", amount, " -> health ", health)
	if _audio:
		_audio.play()
	if _flash:
		_flash.color.a = 0.45
		create_tween().tween_property(_flash, "color:a", 0.0, 0.45)
	if _heart:
		_heart.punch = 1.0
		_spawn_blood(amount)
	_update_hud()
	if health <= 0.0:
		_die()

func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(health + amount, max_health)
	_update_hud()

func _die() -> void:
	is_dead = true
	is_active = false
	died.emit()
	if _death_label:
		_death_label.visible = true
	if _heart:
		_heart.beat_enabled = false
		_burst.amount = blood_burst_amount * 2
		_burst.restart()
		_burst_top.amount = blood_burst_amount
		_burst_top.restart()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if restart_on_death:
		await get_tree().create_timer(restart_delay).timeout
		get_tree().reload_current_scene()


func _make_drop_texture() -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.55, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	return gt

func _make_particles(drop_tex: Texture2D, pos: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = drop_tex
	p.color = blood_color
	p.direction = Vector2(0, 1)
	p.gravity = Vector2(0, 900)
	p.position = pos
	p.local_coords = false
	p.z_index = 5
	return p

func _spawn_blood(amount: float) -> void:
	var n := clampi(int(blood_burst_amount * clampf(amount / 10.0, 0.6, 2.5)), 8, 90)
	_burst.amount = n
	_burst.restart()
	_burst_top.amount = int(n * 0.5)
	_burst_top.restart()

func _build_blood(parent: Control, w: float, h: float) -> void:
	var drop_tex := _make_drop_texture()
	var tip := Vector2(w * 0.5, h * 0.92)
	var top := Vector2(w * 0.38, h * 0.08)

	_burst = _make_particles(drop_tex, tip)
	_burst.one_shot = true
	_burst.emitting = false
	_burst.explosiveness = 0.9
	_burst.lifetime = 0.9
	_burst.spread = 70.0
	_burst.initial_velocity_min = 60.0
	_burst.initial_velocity_max = 240.0
	_burst.scale_amount_min = 0.25
	_burst.scale_amount_max = 0.7
	parent.add_child(_burst)

	_burst_top = _make_particles(drop_tex, top)
	_burst_top.direction = Vector2(0, -1)
	_burst_top.one_shot = true
	_burst_top.emitting = false
	_burst_top.explosiveness = 0.9
	_burst_top.lifetime = 1.0
	_burst_top.spread = 45.0
	_burst_top.initial_velocity_min = 80.0
	_burst_top.initial_velocity_max = 220.0
	_burst_top.scale_amount_min = 0.2
	_burst_top.scale_amount_max = 0.55
	parent.add_child(_burst_top)

	_drip = _make_particles(drop_tex, tip)
	_drip.one_shot = false
	_drip.emitting = false
	_drip.amount = 6
	_drip.lifetime = 1.3
	_drip.spread = 10.0
	_drip.initial_velocity_min = 0.0
	_drip.initial_velocity_max = 25.0
	_drip.scale_amount_min = 0.3
	_drip.scale_amount_max = 0.55
	parent.add_child(_drip)

	_drip_top = _make_particles(drop_tex, top)
	_drip_top.one_shot = false
	_drip_top.emitting = false
	_drip_top.amount = 4
	_drip_top.lifetime = 1.4
	_drip_top.spread = 10.0
	_drip_top.initial_velocity_min = 0.0
	_drip_top.initial_velocity_max = 20.0
	_drip_top.scale_amount_min = 0.25
	_drip_top.scale_amount_max = 0.45
	parent.add_child(_drip_top)


func _make_tint_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 sick_color : source_color = vec4(0.35, 0.95, 0.2, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 c = COLOR;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 green = sick_color.rgb * (lum * 1.6 + 0.12);
	c.rgb = mix(c.rgb, green, amount);
	COLOR = c;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("sick_color", sick_color)
	return m

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	_flash = ColorRect.new()
	_flash.color = Color(0.7, 0.0, 0.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_flash)

	var aspect := 0.71
	if heart_texture:
		var ts := heart_texture.get_size()
		aspect = ts.x / maxf(ts.y, 1.0)
	var h := heart_height
	var w := h * aspect
	var bar_w := maxf(bar_min_width, w)

	var bar_bottom := -heart_margin.y
	var bar_top := bar_bottom - bar_height
	var heart_bottom := bar_top - bar_gap
	var heart_top := heart_bottom - h

	_heart_mat = _make_tint_material()
	_bar_mat = _make_tint_material()

	_heart = HeartDisplay.new()
	_heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heart.tex = heart_texture
	_heart.beat_enabled = heartbeat
	_heart.material = _heart_mat
	_heart.anchor_top = 1.0
	_heart.anchor_bottom = 1.0
	_heart.offset_left = heart_margin.x + (bar_w - w) * 0.5
	_heart.offset_right = _heart.offset_left + w
	_heart.offset_top = heart_top
	_heart.offset_bottom = heart_bottom
	_heart.shown = _shown
	_heart.trail = _trail
	layer.add_child(_heart)

	_bar = BarDisplay.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.material = _bar_mat
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_left = heart_margin.x
	_bar.offset_right = heart_margin.x + bar_w
	_bar.offset_top = bar_top
	_bar.offset_bottom = bar_bottom
	_bar.fill_color = bar_color
	_bar.shown = _shown
	_bar.trail = _trail
	layer.add_child(_bar)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", int(w * 0.24))
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	_label.visible = show_number
	_heart.add_child(_label)

	_build_blood(_heart, w, h)

	_death_label = Label.new()
	_death_label.text = "YOU DIED"
	_death_label.visible = false
	_death_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.add_theme_font_size_override("font_size", 72)
	_death_label.add_theme_color_override("font_color", Color(0.75, 0.05, 0.05))
	layer.add_child(_death_label)

func _update_hud() -> void:
	if _heart == null:
		return
	var ratio := clampf(health / max_health, 0.0, 1.0)

	var sick := 0.0
	if ratio < green_below:
		sick = 1.0 - ratio / green_below
	var amt := sick * sick_strength
	_heart_mat.set_shader_parameter("amount", amt)
	_bar_mat.set_shader_parameter("amount", amt)

	_heart.beat_speed = lerpf(1.2, 3.2, 1.0 - ratio)
