extends Node3D

signal state_changed(new_state: int)

enum State { UNARMED, GUN, MELEE }

@export var player: CharacterBody3D
@export var head: Node3D
@export var left_arm: Node3D
@export var right_arm: Node3D
@export var gun: Node3D
@export var bat: Node3D

@export_group("Master")
@export var motion_scale := 1.0
@export var polish := 1.0

@export_group("Weapon Switch")
@export var switch_time := 0.18
@export var switch_drop := 0.35
@export var switch_tilt_deg := 25.0
@export var wheel_switch := true

@export_group("Swing")
@export var walk_freq := 5.0
@export var run_freq := 7.0
@export var stride := 0.35
@export var lift := 0.14
@export var side := 0.04
@export var pitch_deg := 18.0
@export var run_scale := 1.2
@export var move_threshold := 1.5
@export var blend_speed := 6.0

@export_group("Twist")
@export var roll_axis := Vector3(0, 0, 1)
@export var roll_deg := 40.0
@export var roll_sign := 1.0

@export_group("Idle")
@export var idle_freq := 1.0
@export var idle_amp := 0.005
@export var breath_deg := 0.4

@export_group("Sprint Pose")
@export var sprint_drop := 0.05
@export var sprint_tilt_deg := 8.0
@export var sprint_yaw_deg := 4.0

@export_group("Step Dip")
@export var step_dip := 0.012
@export var step_sway := 0.01

@export_group("Look Sway")
@export var look_gain := 0.0035
@export var max_look_deg := 3.0
@export var look_spring := 35.0
@export var look_damp := 9.0

@export_group("Strafe Lean")
@export var strafe_roll_deg := 3.0
@export var strafe_shift := 0.02
@export var strafe_sign := 1.0

@export_group("Jump and Land")
@export var air_lift := 0.003
@export var air_max := 0.03
@export var land_kick := 0.04
@export var land_recover := 8.0

var state: State = State.UNARMED
var _pending := -1
var _lower := 0.0
var _phase := 0.0
var _idle_t := 0.0
var _amount := 0.0
var _sprint := 0.0
var _strafe := 0.0
var _air := 0.0
var _kick := 0.0
var _was_on_floor := true
var _prev_vy := 0.0
var _prev_yaw := 0.0
var _prev_pitch := 0.0
var _look := Vector2.ZERO
var _look_vel := Vector2.ZERO
var _left_base := Transform3D.IDENTITY
var _right_base := Transform3D.IDENTITY


func _ready() -> void:
	# Auto-find anything left empty in the Inspector
	if player == null:
		var n := get_parent()
		while n and not (n is CharacterBody3D):
			n = n.get_parent()
		player = n as CharacterBody3D
	if gun == null:
		gun = find_child("gun*", true, false) as Node3D
	if bat == null:
		bat = find_child("Bat*", true, false) as Node3D
	if left_arm == null:
		left_arm = find_child("Left*", true, false) as Node3D
	if right_arm == null:
		right_arm = find_child("Right*", true, false) as Node3D

	if player == null: push_warning("Viewmodel: PLAYER not found. Assign Rob.")
	if gun == null: push_warning("Viewmodel: GUN not found. Add gun.tscn under ViewmodelPivot.")
	if bat == null: push_warning("Viewmodel: BAT not found. Add Bat under the right arm.")
	if left_arm == null: push_warning("Viewmodel: LEFT ARM not found.")
	if right_arm == null: push_warning("Viewmodel: RIGHT ARM not found.")

	if left_arm:
		_left_base = left_arm.transform
	if right_arm:
		_right_base = right_arm.transform
	if player:
		_prev_yaw = player.rotation.y
	if head:
		_prev_pitch = head.rotation.x
	_apply_state(State.UNARMED)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.is_active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: equip(State.UNARMED)
			KEY_2: equip(State.GUN)
			KEY_3: equip(State.MELEE)

	elif wheel_switch and event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle(1)


func equip(s: int) -> void:
	var current := _pending if _pending != -1 else int(state)
	if s == current:
		return
	_pending = s


func cycle(dir: int) -> void:
	var current := _pending if _pending != -1 else int(state)
	equip(posmod(current + dir, 3))


func _apply_state(s: int) -> void:
	state = s as State
	if left_arm:
		left_arm.visible = (s == State.UNARMED)
	if right_arm:
		right_arm.visible = (s == State.UNARMED)
	if gun:
		gun.visible = (s == State.GUN)
	if bat:
		bat.visible = (s == State.MELEE)
	state_changed.emit(s)


func _to_parent(arm: Node3D, v: Vector3) -> Vector3:
	var par := arm.get_parent() as Node3D
	if par == null:
		return v
	return par.global_transform.basis.inverse() * (global_transform.basis * v)


func _apply(arm: Node3D, base: Transform3D, s: float, sd: float, amp: float, idle: float) -> void:
	var k := motion_scale * amp
	var up := 0.5 + 0.5 * s
	var off := Vector3(
		-sd * side * up * k,
		up * lift * k + sin(_idle_t) * idle_amp * idle,
		-s * stride * k
	)
	var axis := _to_parent(arm, Vector3.RIGHT).normalized()
	var b := Basis(axis, s * deg_to_rad(pitch_deg) * k) * base.basis
	b = b * Basis(roll_axis.normalized(), -s * deg_to_rad(roll_deg) * k * sd * roll_sign)
	arm.transform = Transform3D(b, base.origin + _to_parent(arm, off))


func _process(delta: float) -> void:
	if player == null or delta <= 0.0:
		return

	if not player.is_active:
		visible = false
		return
	visible = true

	# Weapon switch: lower, swap while hidden, raise
	var lower_goal := 1.0 if _pending != -1 else 0.0
	_lower = move_toward(_lower, lower_goal, delta / maxf(switch_time, 0.01))
	if _pending != -1 and _lower >= 1.0:
		_apply_state(_pending)
		_pending = -1
	var ease_lower := smoothstep(0.0, 1.0, _lower)

	var on_floor := player.is_on_floor()
	var raw := Vector2(player.velocity.x, player.velocity.z).length() if on_floor else 0.0
	var w := 1.0 - exp(-blend_speed * delta)

	_amount = lerpf(_amount, clampf(raw / move_threshold, 0.0, 1.0), w)
	var sprint_target := 1.0 if (player.is_sprinting and raw > 0.5) else 0.0
	_sprint = lerpf(_sprint, sprint_target, w)

	var freq := lerpf(walk_freq, run_freq, _sprint)
	_phase += delta * freq * _amount
	_idle_t += delta * idle_freq * TAU

	var amp := _amount * lerpf(1.0, run_scale, _sprint)
	var idle := 1.0 - _amount
	var s := sin(_phase)

	if right_arm:
		_apply(right_arm, _right_base, s, 1.0, amp, idle)
	if left_arm:
		_apply(left_arm, _left_base, -s, -1.0, amp, idle)

	var p := polish
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO

	pos.y -= switch_drop * ease_lower
	rot.x -= deg_to_rad(switch_tilt_deg) * ease_lower

	pos.y -= sprint_drop * _sprint * p
	rot.x -= deg_to_rad(sprint_tilt_deg) * _sprint * p
	rot.y += deg_to_rad(sprint_yaw_deg) * _sprint * p

	pos.y -= absf(s) * step_dip * amp * p
	pos.x += s * step_sway * amp * p

	rot.x += sin(_idle_t) * deg_to_rad(breath_deg) * idle * p

	var local_vel := player.global_transform.basis.inverse() * player.velocity
	var strafe_target := clampf(local_vel.x / maxf(player.sprint_speed, 0.01), -1.0, 1.0) * strafe_sign
	_strafe = lerpf(_strafe, strafe_target if on_floor else 0.0, w)
	rot.z -= deg_to_rad(strafe_roll_deg) * _strafe * p
	pos.x -= strafe_shift * _strafe * p

	var air_target := clampf(player.velocity.y * air_lift, -air_max, air_max) if not on_floor else 0.0
	_air = lerpf(_air, air_target, 1.0 - exp(-12.0 * delta))
	if on_floor and not _was_on_floor:
		_kick = clampf(-_prev_vy * land_kick * 0.15, 0.0, land_kick * 2.0)
	_was_on_floor = on_floor
	_prev_vy = player.velocity.y
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-land_recover * delta))
	pos.y += (_air - _kick) * p

	var yaw := player.rotation.y
	var yaw_vel := angle_difference(_prev_yaw, yaw) / delta
	_prev_yaw = yaw
	var pitch_vel := 0.0
	if head:
		var pitch := head.rotation.x
		pitch_vel = (pitch - _prev_pitch) / delta
		_prev_pitch = pitch

	var lim := deg_to_rad(max_look_deg)
	var look_target := Vector2(
		clampf(-pitch_vel * look_gain, -lim, lim),
		clampf(-yaw_vel * look_gain, -lim, lim)
	)
	var accel := (look_target - _look) * look_spring - _look_vel * look_damp
	_look_vel += accel * delta
	_look += _look_vel * delta
	rot.x += _look.x * p
	rot.y += _look.y * p
	rot.z -= _look.y * 0.5 * p

	position = pos
	rotation = rot
