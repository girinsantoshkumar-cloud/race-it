extends CharacterBody3D

enum {
	IDLE,
	WALK,
	JUMP,
	TURN_LEFT,
	TURN_RIGHT
}

var curAnim = IDLE

# --------------------------------------------------
# ANIMATION
# --------------------------------------------------

@export var blend_speed := 15.0

@onready var animation_tree: AnimationTree = get_node("cute_rob_Walking /AnimationTree")

var walk_val := 0.0
var jump := 0.0
var turn_left := 0.0
var turn_right := 0.0
###character is_active
var is_active:=true

# --------------------------------------------------
# MOVEMENT
# --------------------------------------------------

const SPEED := 7.0
const REVERSE_SPEED := 4.5
const JUMP_VELOCITY := 4.5

# How fast the character rotates when steering (radians/sec).
@export var rotation_speed := 3.0


# --------------------------------------------------
# READY
# --------------------------------------------------

func _ready() -> void:
	#print("Rob: ", self)
	#print("AnimationTree: ", animation_tree)
	##manage vehicles
	VehicleManager.character =self
	animation_tree.active = true


# ==================================================
# ANIMATION HANDLER
# ==================================================
# Instead of a hard state machine, every value eases toward
# its target every frame based on what's actually happening,
# so walking + turning can blend together at the same time.

func handle_animations(delta: float, move_amount: float, turn_amount: float, is_jumping: bool) -> void:

	walk_val = lerpf(walk_val, move_amount, blend_speed * delta)
	jump = lerpf(jump, 1.0 if is_jumping else 0.0, blend_speed * delta)

	# turn_amount is signed: negative = turning left, positive = turning right
	turn_left = lerpf(turn_left, clampf(-turn_amount, 0.0, 1.0), blend_speed * delta)
	turn_right = lerpf(turn_right, clampf(turn_amount, 0.0, 1.0), blend_speed * delta)


# ==================================================
# UPDATE ANIMATION TREE
# ==================================================

func update_tree() -> void:
	animation_tree["parameters/walk_blend/blend_amount"] = walk_val
	animation_tree["parameters/jump_blend/blend_amount"] = jump
	animation_tree["parameters/turn_left_blend/blend_amount"] = turn_left
	animation_tree["parameters/turn_right_blend/blend_amount"] = turn_right


# ==================================================
# PHYSICS
# ==================================================

func _physics_process(delta: float) -> void:

	##Check whether the character is active or not if not return
	if not is_active:
		return
	# ------------------------------------------------
	# GRAVITY
	# ------------------------------------------------

	if not is_on_floor():
		velocity += get_gravity() * delta

	# ------------------------------------------------
	# STEERING (continuous rotation, GTA-style)
	# Hold left/right to turn at any time, moving or not.
	# ------------------------------------------------

	var steer_input := Input.get_axis("left", "right")

	if steer_input != 0.0:
		rotation.y -= steer_input * rotation_speed * delta

	# ------------------------------------------------
	# THROTTLE (forward/backward along facing direction)
	# ------------------------------------------------

	var throttle_input := Input.get_axis("forward", "backward")

	var forward_direction := -transform.basis.z
	var move_speed := SPEED if throttle_input >= 0.0 else REVERSE_SPEED

	if throttle_input != 0.0:
		velocity.x = forward_direction.x * throttle_input * move_speed
		velocity.z = forward_direction.z * throttle_input * move_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	# ------------------------------------------------
	# JUMP
	# ------------------------------------------------

	var is_jumping := not is_on_floor()

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		is_jumping = true

	# ------------------------------------------------
	# MOVE
	# ------------------------------------------------

	move_and_slide()

	# ------------------------------------------------
	# ANIMATION
	# ------------------------------------------------

	handle_animations(delta, absf(throttle_input), steer_input, is_jumping)
	update_tree()
