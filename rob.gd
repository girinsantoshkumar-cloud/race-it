extends CharacterBody3D

@export var head: Node3D
@export var camera: Camera3D

@onready var animation_tree: AnimationTree = get_node("cute_rob_Walking /AnimationTree")


@export_group("Animation")
@export var blend_speed := 15.0
## How strongly mouse turning drives the turn_left / turn_right blends.
@export var turn_anim_sensitivity := 0.02

var walk_val := 0.0
var jump := 0.0
var turn_left := 0.0
var turn_right := 0.0

### character is_active (VehicleManager flips this when you enter a vehicle)
var is_active := true

@export_group("Movement")
@export var walk_speed := 7.0
@export var sprint_speed := 11.0
@export var reverse_speed := 4.5
@export var ground_accel := 14.0
@export var air_accel := 3.0
@export var jump_velocity := 4.5
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12

@export_group("Camera")
@export var mouse_sensitivity := 0.0022
@export var max_pitch_deg := 89.0
@export var base_fov := 75.0
@export var sprint_fov := 82.0
@export var fov_lerp_speed := 8.0
@export var bob_enabled := true
@export var bob_frequency := 2.0
@export var bob_amplitude := 0.04

var is_sprinting := false

var _mouse_turn := 0.0        # accumulated mouse X, used to drive turn animations
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _bob_time := 0.0


func _ready() -> void:
	## manage vehicles
	VehicleManager.character = self
	animation_tree.active = true

	if head == null or camera == null:
		push_warning("Player: assign 'head' and 'camera' exports in the Inspector.")
		set_process_unhandled_input(false)
		return

	camera.fov = base_fov
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-max_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)
		_mouse_turn += event.relative.x

	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func handle_animations(delta: float, move_amount: float, turn_amount: float, is_jumping: bool) -> void:
	var w := 1.0 - exp(-blend_speed * delta)

	walk_val = lerpf(walk_val, move_amount, w)
	jump = lerpf(jump, 1.0 if is_jumping else 0.0, w)

	# turn_amount is signed: negative = turning left, positive = turning right
	turn_left = lerpf(turn_left, clampf(-turn_amount, 0.0, 1.0), w)
	turn_right = lerpf(turn_right, clampf(turn_amount, 0.0, 1.0), w)


func update_tree() -> void:
	animation_tree["parameters/walk_blend/blend_amount"] = walk_val
	animation_tree["parameters/jump_blend/blend_amount"] = jump
	animation_tree["parameters/turn_left_blend/blend_amount"] = turn_left
	animation_tree["parameters/turn_right_blend/blend_amount"] = turn_right



func _physics_process(delta: float) -> void:

	## Check whether the character is active or not, if not return
	if not is_active:
		return


	if not is_on_floor():
		velocity += get_gravity() * delta
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	else:
		_coyote_timer = coyote_time

	if Input.is_action_just_pressed("ui_accept"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	# With this action order, input_dir.y > 0 means FORWARD, < 0 means BACKWARD
	var input_dir := Input.get_vector("right", "left", "backward", "forward")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var moving_forward := input_dir.y > 0.0
	var moving_backward := input_dir.y < 0.0

	is_sprinting = InputMap.has_action("sprint") \
			and Input.is_action_pressed("sprint") \
			and moving_forward

	var speed := walk_speed
	if moving_backward:
		speed = reverse_speed
	elif is_sprinting:
		speed = sprint_speed

	var accel := ground_accel if is_on_floor() else air_accel
	var weight := 1.0 - exp(-accel * delta)   # frame-rate independent smoothing

	var horizontal := Vector2(velocity.x, velocity.z)
	horizontal = horizontal.lerp(Vector2(direction.x, direction.z) * speed, weight)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	if Input.is_action_just_released("ui_accept") and velocity.y > 0.0:
		velocity.y *= 0.5

	var is_jumping := not is_on_floor()

	move_and_slide()

	var turn_amount := clampf(_mouse_turn * turn_anim_sensitivity, -1.0, 1.0)
	_mouse_turn = 0.0

	handle_animations(delta, input_dir.length(), turn_amount, is_jumping)
	update_tree()
	_update_camera(delta)

func _update_camera(delta: float) -> void:
	var h_speed := Vector2(velocity.x, velocity.z).length()

	# FOV kick while sprinting
	var target_fov := sprint_fov if is_sprinting and h_speed > 0.5 else base_fov
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-fov_lerp_speed * delta))

	# Head bob, only while walking on the ground
	if bob_enabled and is_on_floor() and h_speed > 0.5:
		_bob_time += delta * h_speed * bob_frequency * 0.4
		camera.position.y = sin(_bob_time) * bob_amplitude
		camera.position.x = cos(_bob_time * 0.5) * bob_amplitude * 0.5
	else:
		camera.position = camera.position.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))
