extends VehicleBody3D

@export_group("Wheels")
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

# active checker
var is_active := false:
	set(value):
		is_active = value
		if is_active:
			_enter_grace = 0.3   # ignore the "interact" press that got us in
		else:
			park_vehicle()

## topple checker
var has_toppled := false
var flip_timer: float = 0.0
var last_stable_transform: Transform3D

## parking brake toggle (player pressed the parking_hand_brake key)
var parking := false

var _enter_grace: float = 0.0


func _ready() -> void:
	# vehicle manager
	VehicleManager.vehicle = self
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# so a reset before the first "stable" frame doesn't send the car to the world origin
	last_stable_transform = global_transform

	_apply_wheel_settings()
	park_vehicle()


func _apply_wheel_settings() -> void:
	for wheel in [front_left, front_right, back_right, back_left]:
		if wheel == null:
			continue
		wheel.wheel_friction_slip = wheel_friction
		if suspension_stiffness_value > 0.0:
			wheel.suspension_stiffness = suspension_stiffness_value


func _physics_process(delta: float) -> void:
	_check_topple(delta)
	_enter_grace = maxf(_enter_grace - delta, 0.0)

	# ---- player actions (only while driving) ----
	if is_active:
		if _enter_grace <= 0.0 and Input.is_action_just_pressed("interact"):
			park_vehicle()
			VehicleManager.exit_vehicle()
			return
		if Input.is_action_just_pressed("parking_hand_brake"):
			parking = not parking

	# ---- inputs (zero when nobody is driving) ----
	var throttle := 0.0
	var steer_input := 0.0
	if is_active:
		throttle = Input.get_axis("forward", "backward")
		steer_input = Input.get_axis("right", "left")

	steering = move_toward(steering, steer_input * max_steer, delta * steer_speed)

	# ---- engine + brakes: decided in ONE place, highest priority first ----
	if not is_active or parking:
		# parked: no engine, brakes held every frame
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
