extends CharacterBody3D

enum State { IDLE, CHASE, ATTACK, DEAD }

@export var speed := 2.5
@export var detect_range := 25.0
@export var lose_range := 45.0
@export var attack_range := 1.8
@export var attack_damage := 10.0
@export var attack_cooldown := 1.4
@export var hit_delay := 0.5
@export var health := 50.0
@export var turn_speed := 8.0
@export var model_yaw_offset := 0.0
@export var slope_tilt := true          # tilt model to ground normal
@export var tilt_speed := 6.0
@export var debug := false

@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var model: Node3D = $bot_dough
@onready var anim: AnimationPlayer = $bot_dough/AnimationPlayer

var state := State.IDLE
var target: Node3D = null
var attack_timer := 0.0
var repath_timer := 0.0
var debug_timer := 0.0
var stuck_timer := 0.0
var last_pos := Vector3.ZERO
var stuck_nudge := Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("enemies")
	# Bumpy terrain settings
	floor_snap_length = 0.8
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	floor_constant_speed = true          # same speed uphill/downhill
	motion_mode = MOTION_MODE_GROUNDED

	nav.path_desired_distance = 0.8
	nav.target_desired_distance = 1.2
	nav.path_max_distance = 3.0
	nav.path_height_offset = 0.0
	nav.velocity_computed.connect(_on_velocity_computed)

	speed *= randf_range(0.8, 1.3)
	last_pos = global_position
	anim.play("enemy_animations/walking")
	anim.pause()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	attack_timer = max(attack_timer - delta, 0.0)
	_update_target()

	match state:
		State.IDLE:
			_move(Vector3.ZERO)
			if target:
				state = State.CHASE
		State.CHASE:
			_chase(delta)
		State.ATTACK:
			_attack_state(delta)

	move_and_slide()
	_tilt_to_ground(delta)

	if debug:
		debug_timer -= delta
		if debug_timer <= 0.0:
			debug_timer = 1.0
			print("[", name, "] ", State.keys()[state],
				" target=", target.name if target else "none",
				" floor=", is_on_floor(),
				" vel=", velocity.snapped(Vector3(0.01, 0.01, 0.01)))


func _update_target() -> void:
	var best: Node3D = null
	var best_d := INF
	for t in get_tree().get_nodes_in_group("player"):
		if not (t is Node3D):
			continue
		if not t.visible:
			continue
		# Only chase the entity the player is currently controlling.
		if "is_active" in t and not bool(t.get("is_active")):
			continue
		var d := global_position.distance_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	var limit := lose_range if state != State.IDLE else detect_range
	target = best if best and best_d <= limit else null
	if target == null and state in [State.CHASE, State.ATTACK]:
		state = State.IDLE
		anim.pause()


func _chase(delta: float) -> void:
	if target == null:
		return
	var flat := target.global_position - global_position
	flat.y = 0.0
	if flat.length() <= attack_range:
		state = State.ATTACK
		_move(Vector3.ZERO)
		return

	repath_timer -= delta
	if repath_timer <= 0.0:
		nav.target_position = target.global_position
		repath_timer = 0.2

	if anim.current_animation != "enemy_animations/walking" or not anim.is_playing():
		anim.play("enemy_animations/walking")

	var dir := nav.get_next_path_position() - global_position
	dir.y = 0.0
	if dir.length() < 0.1:               # no navmesh / no path: go straight
		dir = flat
	dir = dir.normalized()

	# Follow the slope: project move direction onto the ground plane
	if is_on_floor():
		dir = (dir - get_floor_normal() * dir.dot(get_floor_normal())).normalized()

	stuck_nudge = Vector3.ZERO
	_check_stuck(delta)
	_face(dir, delta)
	_move(dir * speed + stuck_nudge)


func _check_stuck(delta: float) -> void:
	# If blocked by a bump/rock for 1s, nudge sideways and repath
	stuck_timer += delta
	if stuck_timer >= 1.0:
		if global_position.distance_to(last_pos) < 0.3:
			stuck_nudge = global_transform.basis.x * randf_range(-3.0, 3.0)
			repath_timer = 0.0
		last_pos = global_position
		stuck_timer = 0.0


func _attack_state(delta: float) -> void:
	_move(Vector3.ZERO)
	if target == null:
		return
	var to_t := target.global_position - global_position
	to_t.y = 0.0
	_face(to_t.normalized(), delta)

	if anim.current_animation == "enemy_animations/attacking" and anim.is_playing():
		return

	if to_t.length() > attack_range * 1.3:
		state = State.CHASE
		return

	if attack_timer <= 0.0:
		attack_timer = attack_cooldown
		anim.play("enemy_animations/attacking")
		_deal_damage()


func _deal_damage() -> void:
	await get_tree().create_timer(hit_delay).timeout
	if state == State.DEAD or target == null:
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		if target.has_method("take_damage"):
			target.take_damage(attack_damage)


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var want := atan2(dir.x, dir.z) + model_yaw_offset
	model.rotation.y = lerp_angle(model.rotation.y, want, turn_speed * delta)


func _tilt_to_ground(delta: float) -> void:
	if not slope_tilt:
		return
	var n := get_floor_normal() if is_on_floor() else Vector3.UP
	# Local-space tilt so it doesn't fight the yaw rotation
	var local_n := global_transform.basis.inverse() * n
	var tx := atan2(local_n.z, local_n.y)
	var tz := -atan2(local_n.x, local_n.y)
	model.rotation.x = lerp_angle(model.rotation.x, tx, tilt_speed * delta)
	model.rotation.z = lerp_angle(model.rotation.z, tz, tilt_speed * delta)


func _move(desired: Vector3) -> void:
	if nav.avoidance_enabled:
		nav.velocity = desired
	else:
		velocity.x = desired.x
		velocity.z = desired.z


func _on_velocity_computed(safe: Vector3) -> void:
	velocity.x = safe.x
	velocity.z = safe.z


func take_damage(amount: float) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if health <= 0.0:
		_die()


func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	$CollisionShape3D.set_deferred("disabled", true)
	remove_from_group("enemies")
	model.rotation.x = 0.0
	model.rotation.z = 0.0
	anim.play("enemy_animations/dying")
	await anim.animation_finished
	await get_tree().create_timer(5.0).timeout
	queue_free()
