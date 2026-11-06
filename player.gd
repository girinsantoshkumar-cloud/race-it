extends VehicleBody3D

signal health_changed(current: float, maximum: float)
signal broken

@export_group("Vehicle manager (empty = auto-find)")
@export var enter_area: Area3D
@export var exit_point: Node3D
@export var drive_camera: Camera3D
@export var prompt_text := "Drive"
@export var enter_distance := 4.0
@export var auto_camera_offset := Vector3(0.0, 2.5, -6.0)

@export_group("Health")
@export var max_health := 200.0
@export var broken_prompt_text := "Car broken"
## Show "Car broken" while Rob sits inside the dead car.
@export var show_broken_while_inside := true
## Also show it when Rob walks up to the broken car (off = hidden after he gets out).
@export var show_broken_when_near := false

@export_group("Crash damage")
@export var crash_damage_enabled := true
@export var crash_only_when_driven := true
## Speed (m/s) straight into a wall/object below which there is NO damage.
@export var crash_threshold := 6.0
## Damage per m/s above the threshold.
@export var crash_damage_per_speed := 5.0
## Surfaces flatter than this count as ground and never cause damage (0 to 1, higher = only steep walls count).
@export_range(0.3, 0.95) var ground_normal_limit := 0.7
## Seconds of immunity between hits.
@export var crash_cooldown := 0.6
## Seconds of immunity after the level starts (car settling onto the ground).
@export var crash_grace := 1.5
## Maximum damage a single hit can do.
@export var crash_max_damage := 120.0

@export_group("Wheels (empty = auto-find by name)")
@export var front_left: VehicleWheel3D
@export var front_right: VehicleWheel3D
@export var back_right: VehicleWheel3D
@export var back_left: VehicleWheel3D

@export_group("Physics (0 = leave Inspector value)")
@export var set_mass := 0.0
@export var set_gravity_scale := 0.0

@export_group("Suspension")
@export var wheel_friction := 10.5
## 0 = leave the stiffness already set on each wheel node.
@export var suspension_stiffness_value := 0.0

@export_group("Driving")
@export var max_steer := 0.35
@export var steer_speed := 2.5
@export var engine_power := 700.0

@export_group("Brakes")
@export var handbrake_force := 30.0
@export var parking_brake_force := 100.0
@export var idle_brake_force := 1.5

@export_group("Recovery")
@export var flip_threshold := 0.3
@export var flip_time_required := 2.0

var is_active := false:
	set(value):
		is_active = value
		if not is_active:
			park_vehicle()

var health := 0.0
var is_broken := false
var _normal_prompt_text := ""
var _normal_enter_distance := 4.0
var _locked := false
var _broken_label: Label

var has_toppled := false
var flip_timer := 0.0
var last_stable_transform: Transform3D
var parking := false

var _v1 := Vector3.ZERO          # velocity one physics step ago
var _v2 := Vector3.ZERO          # velocity two physics steps ago
var _pending_damage := 0.0
var _crash_cd := 0.0
var _age := 0.0


func _ready() -> void:
	add_to_group("car")
	health = max_health
	_normal_prompt_text = prompt_text
	_normal_enter_distance = enter_distance
	contact_monitor = true
	max_contacts_reported = 8
	if set_mass > 0.0:
		mass = set_mass
	if set_gravity_scale > 0.0:
		gravity_scale = set_gravity_scale
	_auto_setup()
	_bake_wheel_scale()
	VehicleManager.register_vehicle(self)
	_build_broken_label()
	last_stable_transform = global_transform
	_apply_wheel_settings()
	park_vehicle()
	health_changed.emit(health, max_health)


func _exit_tree() -> void:
	VehicleManager.unregister_vehicle(self)


# ----------------------------------------------------------------------
# health
# ----------------------------------------------------------------------

# zombies and crashes call this
func take_damage(amount: float, _hit_pos: Vector3 = Vector3.INF, _hit_normal: Vector3 = Vector3.ZERO) -> void:
	if is_broken or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_break_car()


# Marks the car as broken: engine dead, steering dead, brakes on.
# It does NOT touch is_active or the manager, so you leave with your own exit key.
func _break_car() -> void:
	is_broken = true
	prompt_text = broken_prompt_text
	park_vehicle()
	broken.emit()


# VehicleManager can check this before letting the player in
func can_enter() -> bool:
	return not is_broken


func repair(amount: float = 9999.0) -> void:
	health = minf(health + amount, max_health)
	if health > 0.0 and is_broken:
		is_broken = false
		_locked = false
		prompt_text = _normal_prompt_text
		_set_enterable(true)
	health_changed.emit(health, max_health)


# Switches the enter zone off so a broken car can't be entered.
func _set_enterable(on: bool) -> void:
	enter_distance = _normal_enter_distance if on else 0.0
	if enter_area:
		enter_area.set_deferred("monitoring", on)
		enter_area.set_deferred("monitorable", on)


# our own "Car broken" text
func _build_broken_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	_broken_label = Label.new()
	_broken_label.text = broken_prompt_text
	_broken_label.visible = false
	_broken_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_broken_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_broken_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_broken_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_broken_label.add_theme_font_size_override("font_size", 32)
	_broken_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	_broken_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_broken_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_broken_label)


func _process(_delta: float) -> void:
	# once Rob has left the broken car, lock it so it can't be entered again
	if is_broken and not _locked and not is_active:
		_locked = true
		_set_enterable(false)

	if _broken_label == null:
		return

	var show := false
	if is_broken:
		if is_active:
			show = show_broken_while_inside
		elif show_broken_when_near:
			for p in get_tree().get_nodes_in_group("player"):
				if p is Node3D and (p as Node3D).global_position.distance_to(global_position) <= _normal_enter_distance + 1.0:
					show = true
					break

	# while inside the car, lift the text above the "[E] Exit" prompt
	var lift := -140.0 if is_active else 0.0
	_broken_label.offset_top = lift
	_broken_label.offset_bottom = lift
	_broken_label.text = broken_prompt_text
	_broken_label.visible = show


# ----------------------------------------------------------------------
# crash detection
# ----------------------------------------------------------------------
# A crash only counts when the car's BODY touches something upright (wall, rock,
# tree, another car) and the car was moving INTO it. Driving on the ground,
# hills, bumps, braking and reversing never cause damage.

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if crash_damage_enabled and not is_broken and _crash_cd <= 0.0 and _age > crash_grace \
			and (is_active or not crash_only_when_driven):
		var worst := 0.0
		for i in state.get_contact_count():
			var col := state.get_contact_collider_object(i)
			if col is CharacterBody3D:
				continue                                   # Rob / zombies don't hurt the car this way
			var n := state.get_contact_local_normal(i)
			if absf(n.y) > ground_normal_limit:
				continue                                   # ground / floor-like surface
			# how fast we were moving into the surface just before the hit
			var into := maxf(absf(_v1.dot(n)), absf(_v2.dot(n)))
			worst = maxf(worst, into)
		if worst > crash_threshold:
			_pending_damage = minf((worst - crash_threshold) * crash_damage_per_speed, crash_max_damage)

	_v2 = _v1
	_v1 = state.linear_velocity


# ----------------------------------------------------------------------
# setup
# ----------------------------------------------------------------------

func _auto_setup() -> void:
	if front_left == null:
		front_left = find_child("front_left", true, false) as VehicleWheel3D
	if front_right == null:
		front_right = find_child("front_right", true, false) as VehicleWheel3D
	if back_left == null:
		back_left = find_child("back_left", true, false) as VehicleWheel3D
	if back_right == null:
		back_right = find_child("back_right", true, false) as VehicleWheel3D

	if enter_area == null:
		var areas := find_children("*", "Area3D", true, false)
		if not areas.is_empty():
			enter_area = areas[0] as Area3D

	if exit_point == null:
		for n in find_children("*", "Node3D", true, false):
			if n.name.to_lower().begins_with("exit_point"):
				exit_point = n as Node3D
				break

	if drive_camera == null:
		var cams := find_children("*", "Camera3D", true, false)
		if not cams.is_empty():
			drive_camera = cams[0] as Camera3D
	if drive_camera == null:
		drive_camera = Camera3D.new()
		drive_camera.name = "auto_car_cam"
		add_child(drive_camera)
		drive_camera.position = auto_camera_offset
		drive_camera.look_at(global_position + global_transform.basis.y * 1.2, Vector3.UP)
	drive_camera.current = false


# Moves the wheel node's editor scale (e.g. 3) down to its children,
# because VehicleBody3D resets the scale of the wheel node itself.
func _bake_wheel_scale() -> void:
	for w in [front_left, front_right, back_left, back_right]:
		if w == null:
			continue
		var s: Vector3 = w.scale
		if s.is_equal_approx(Vector3.ONE):
			continue
		w.scale = Vector3.ONE
		for c in w.get_children():
			if c is Node3D:
				c.scale *= s
				c.position *= s


func _apply_wheel_settings() -> void:
	for wheel in [front_left, front_right, back_right, back_left]:
		if wheel == null:
			continue
		wheel.wheel_friction_slip = wheel_friction
		if suspension_stiffness_value > 0.0:
			wheel.suspension_stiffness = suspension_stiffness_value


# ----------------------------------------------------------------------
# input + driving
# ----------------------------------------------------------------------

func _axis(negative: String, positive: String) -> float:
	if InputMap.has_action(negative) and InputMap.has_action(positive):
		return Input.get_axis(negative, positive)
	return 0.0


func _pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func _just_pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _physics_process(delta: float) -> void:
	_age += delta
	_crash_cd = maxf(_crash_cd - delta, 0.0)

	# apply any crash damage found during the physics step
	if _pending_damage > 0.0:
		var dmg := _pending_damage
		_pending_damage = 0.0
		_crash_cd = crash_cooldown
		take_damage(dmg)

	_check_topple(delta)

	# broken car: no engine, no steering, brakes held on
	if is_broken:
		engine_force = 0.0
		steering = move_toward(steering, 0.0, delta * steer_speed)
		brake = parking_brake_force
		return

	if is_active and _just_pressed("parking_hand_brake"):
		parking = not parking

	var throttle := 0.0
	var steer_input := 0.0
	if is_active:
		throttle = _axis("forward", "backward")
		steer_input = _axis("right", "left")

	steering = move_toward(steering, steer_input * max_steer, delta * steer_speed)

	if not is_active or parking:
		engine_force = 0.0
		brake = parking_brake_force
	elif _pressed("hand_brake"):
		engine_force = 0.0
		brake = handbrake_force
	else:
		engine_force = throttle * engine_power
		brake = idle_brake_force if is_zero_approx(throttle) else 0.0


func _check_topple(delta: float) -> void:
	var up_dot := global_transform.basis.y.dot(Vector3.UP)
	if up_dot < flip_threshold:
		has_toppled = true
		flip_timer += delta
		if flip_timer >= flip_time_required:
			_reset_vehicle()
			flip_timer = 0.0
	else:
		has_toppled = false
		flip_timer = 0.0
		if linear_velocity.length() <= 8.0:
			last_stable_transform = global_transform


func _reset_vehicle() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	var t := last_stable_transform
	t.origin += Vector3.UP * 1.0
	t.basis = Basis(Vector3.UP, t.basis.get_euler().y)
	global_transform = t
	has_toppled = false
	_v1 = Vector3.ZERO
	_v2 = Vector3.ZERO
	_crash_cd = crash_cooldown


func park_vehicle() -> void:
	engine_force = 0.0
	steering = 0.0
	brake = parking_brake_force
