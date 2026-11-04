extends VehicleBody3D

@export_group("Vehicle manager (empty = auto-find)")
@export var enter_area: Area3D                     # first Area3D child
@export var exit_point: Node3D                     # any child named exit_point*
@export var drive_camera: Camera3D                 # first Camera3D child; built if missing
@export var prompt_text := "Drive"                 # e.g. "Drive Porsche"
## Used only when the car has no camera. Flip the Z sign if it ends up in front of the car.
@export var auto_camera_offset := Vector3(0.0, 2.5, -6.0)

@export_group("Wheels (empty = auto-find by name)")
@export var front_left: VehicleWheel3D
@export var front_right: VehicleWheel3D
@export var back_right: VehicleWheel3D
@export var back_left: VehicleWheel3D

@export_group("Suspension")
@export var wheel_friction: float = 10.5
## 0 = leave the stiffness already set on each wheel node.
@export var suspension_stiffness_value: float = 0.0

@export_group("Driving")
@export var max_steer: float = 0.35
@export var steer_speed: float = 2.5
@export var engine_power: float = 700.0

@export_group("Brakes")
## Hand brake while driving. Godot's docs suggest roughly 25-30 per 1000 kg for hard braking.
@export var handbrake_force: float = 30.0
## Held while parked (toggle key) and whenever nobody is driving.
@export var parking_brake_force: float = 100.0
## Light drag when you let go of the throttle, so the car doesn't coast forever.
@export var idle_brake_force: float = 1.5

@export_group("Recovery")
@export var flip_threshold: float = 0.3
@export var flip_time_required: float = 2.0

# the manager flips this when Rob gets in / out
var is_active := false:
	set(value):
		is_active = value
		if not is_active:
			park_vehicle()

## topple checker
var has_toppled := false
var flip_timer: float = 0.0
var last_stable_transform: Transform3D

## parking brake toggle (player pressed the parking_hand_brake key)
var parking := false


func _ready() -> void:
	add_to_group("car")
	_auto_setup()
	VehicleManager.register_vehicle(self)

	# so a reset before the first "stable" frame doesn't send the car to the world origin
	last_stable_transform = global_transform

	_apply_wheel_settings()
	park_vehicle()


func _exit_tree() -> void:
	VehicleManager.unregister_vehicle(self)


func _auto_setup() -> void:
	# wheels by name
	if front_left == null:
		front_left = find_child("front_left", true, false) as VehicleWheel3D
	if front_right == null:
		front_right = find_child("front_right", true, false) as VehicleWheel3D
	if back_left == null:
		back_left = find_child("back_left", true, false) as VehicleWheel3D
	if back_right == null:
		back_right = find_child("back_right", true, false) as VehicleWheel3D

	# enter zone: first Area3D, must have a real shape
	if enter_area == null:
		var areas := find_children("*", "Area3D", true, false)
		if not areas.is_empty():
			enter_area = areas[0] as Area3D
	if enter_area == null:
		push_warning("%s: no Area3D found, so there will be no enter prompt." % name)
	else:
		var has_shape := false
		for s in enter_area.find_children("*", "CollisionShape3D", true, false):
			if (s as CollisionShape3D).shape != null:
				has_shape = true
		if not has_shape:
			push_warning("%s: enter area has no collision shape assigned (the yellow warning)." % name)

	# exit point: any Node3D named exit_point*
	if exit_point == null:
		for n in find_children("*", "Node3D", true, false):
			if n.name.to_lower().begins_with("exit_point"):
				exit_point = n as Node3D
				break

	# camera: existing one, else build a simple follow camera
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
	drive_camera.current = false                   # only the driven car's camera is current


func _apply_wheel_settings() -> void:
	for wheel in [front_left, front_right, back_right, back_left]:
		if wheel == null:
			continue
		wheel.wheel_friction_slip = wheel_friction
		if suspension_stiffness_value > 0.0:
			wheel.suspension_stiffness = suspension_stiffness_value


func _physics_process(delta: float) -> void:
	_check_topple(delta)

	if is_active and Input.is_action_just_pressed("parking_hand_brake"):
		parking = not parking

	# inputs (zero when nobody is driving)
	var throttle := 0.0
	var steer_input := 0.0
	if is_active:
		throttle = Input.get_axis("forward", "backward")
		steer_input = Input.get_axis("right", "left")

	steering = move_toward(steering, steer_input * max_steer, delta * steer_speed)

	# engine + brakes: decided in ONE place, highest priority first
	if not is_active or parking:
		engine_force = 0.0
		brake = parking_brake_force
	elif Input.is_action_pressed("hand_brake"):
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
	var reset_transform := last_stable_transform
	reset_transform.origin += Vector3.UP * 1.0
	var yaw := reset_transform.basis.get_euler().y
	reset_transform.basis = Basis(Vector3.UP, yaw)

	global_transform = reset_transform
	has_toppled = false


## Called on exit; the per-frame logic above keeps the brakes on afterwards.
func park_vehicle() -> void:
	engine_force = 0.0
	steering = 0.0
	brake = parking_brake_force
