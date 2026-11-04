extends CharacterBody3D

enum State { IDLE, WANDER, CHASE, SEARCH, ATTACK, DOWNED, STANDING, DEAD }

@export_group("Targets (leave empty to auto-find)")
@export var person_node: Node3D                    # Rob. Auto: group "player", else node named "Rob"
@export var car_node: Node3D                       # Auto: group "car", else node named "Car"
@export var nav_agent: NavigationAgent3D
@export var animation_tree: AnimationTree

@export_group("In-car detection")
@export var in_car_node: Node                      # node holding the bool (Rob or the car). Empty = auto-check both
@export var in_car_property := "in_car"
@export var hide_means_in_car := false             # only tick if Rob's node is hidden ONLY when driving
@export var debug_target := false                  # prints target changes to Output

@export_group("Senses")
@export var sprint_key: Key = KEY_SHIFT
@export var hear_sprint_range := 28.0
@export var hear_car_range := 40.0
@export var sight_range := 18.0
@export var sight_angle := 70.0
@export var flip_facing := false                   # tick if he only sees things BEHIND him
@export var notice_radius := 4.0
@export var need_line_of_sight := true
@export var eye_height := 1.5
@export var lose_range := 60.0

@export_group("Behaviour")
@export var wander_enabled := true
@export var wander_radius := 8.0
@export var idle_time := 3.0
@export var chase_memory := 3.0
@export var search_look_time := 4.0

@export_group("Movement")
@export var wander_speed := 1.2
@export var chase_speed := 2.8
@export var crawl_speed := 1.2
@export var turn_speed := 8.0
@export var repath_interval := 0.25
@export var use_avoidance := true
@export var walk_anim_min_speed := 0.3             # below this real speed he plays idle

@export_group("Obstacle steering")
@export var whisker_length := 2.0
@export var whisker_angle := 40.0
@export var whisker_height := 0.8
@export var steer_strength := 1.0
@export var stuck_check_time := 1.0

@export_group("Combat")
@export var max_health := 100
@export var attack_range := 1.7
@export var car_reach := 3.5
@export var attack_damage := 10
@export var attack_cooldown := 1.2
@export var attack_hit_delay := 0.4
@export var crawl_damage := 5

@export_group("Downed / Revive")
@export var can_revive := true
@export var downed_health := 40
@export var stand_up_delay := 8.0
@export var stand_up_duration := 3.0
@export var revive_health := 60
@export var despawn_time := 6.0

# Blend2 chain order in the AnimationTree
const BLEND_NODES := ["Blend2", "Blend2 2", "Blend2 3", "Blend2 4", "Blend2 5"]
enum Anim { IDLE = -1, WALK, CRAWL, ATTACK, DIE, STAND }

var state := State.IDLE
var health := 0
var has_been_downed := false
var downed_timer := 0.0
var attack_ready := true
var ready_to_think := false
var target: Node3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _home := Vector3.ZERO
var _last_known := Vector3.ZERO
var _lost_timer := 0.0
var _state_timer := 0.0
var _wander_point := Vector3.ZERO
var _has_wander_point := false
var _search_arrived := false

var _last_person_pos := Vector3.ZERO
var _last_car_pos := Vector3.ZERO
var _person_speed := 0.0
var _car_speed := 0.0

var _repath_timer := 0.0
var _safe_velocity := Vector3.ZERO
var _stuck_timer := 0.0
var _stuck_check_pos := Vector3.ZERO
var _sidestep_timer := 0.0
var _sidestep_dir := 1.0
var _prev_target: Node3D

func _ready() -> void:
	health = max_health
	_home = global_position

	if nav_agent == null:
		nav_agent = find_child("NavigationAgent3D", true, false) as NavigationAgent3D
	if nav_agent == null:
		nav_agent = NavigationAgent3D.new()
		add_child(nav_agent)
	nav_agent.path_desired_distance = 0.6
	nav_agent.target_desired_distance = 0.8
	nav_agent.path_max_distance = 3.0
	nav_agent.avoidance_enabled = use_avoidance
	nav_agent.radius = 0.5
	nav_agent.height = 1.8
	nav_agent.neighbor_distance = 6.0
	nav_agent.max_neighbors = 8
	nav_agent.time_horizon_agents = 1.5
	nav_agent.time_horizon_obstacles = 1.0
	nav_agent.max_speed = chase_speed
	nav_agent.velocity_computed.connect(_on_velocity_computed)

	if animation_tree == null:
		animation_tree = find_child("AnimationTree", true, false) as AnimationTree
	if animation_tree:
		animation_tree.active = true

	_auto_find_targets()

	if person_node:
		_last_person_pos = person_node.global_position
	if car_node:
		_last_car_pos = car_node.global_position

	_stuck_check_pos = global_position
	_play(Anim.IDLE)

	await get_tree().physics_frame   # let the navigation map sync
	ready_to_think = true

func _auto_find_targets() -> void:
	var root := get_tree().current_scene
	if person_node == null:
		person_node = get_tree().get_first_node_in_group("player") as Node3D
		if person_node == null and root:
			person_node = root.find_child("Rob", true, false) as Node3D
	if car_node == null:
		car_node = get_tree().get_first_node_in_group("car") as Node3D
		if car_node == null and root:
			car_node = root.find_child("Car", true, false) as Node3D
	if person_node == null:
		push_warning("Zombie: no Rob found. Assign person_node or add Rob to group 'player'.")
	if car_node == null:
		push_warning("Zombie: no car found. Assign car_node or add the car to group 'car'.")

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = safe_velocity

func _physics_process(delta: float) -> void:
	if not ready_to_think:
		return

	_update_speeds(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta

	_pick_target()

	match state:
		State.IDLE:
			_stop()
			_state_timer += delta
			if _perceive(false):
				_alert()
			elif wander_enabled and _state_timer >= idle_time:
				_start_wander()

		State.WANDER:
			if _perceive(false):
				_alert()
			else:
				var flat := Vector2(_wander_point.x - global_position.x, _wander_point.z - global_position.z)
				if not _has_wander_point or flat.length() < 1.0:
					_set_state(State.IDLE)
				else:
					_move_to_point(_wander_point, wander_speed, delta)

		State.CHASE:
			if target == null:
				_set_state(State.IDLE)
			else:
				var perceived := _perceive(true)
				if perceived:
					_lost_timer = 0.0
					_last_known = target.global_position
				else:
					_lost_timer += delta

				var dist := _distance_to_target()
				if dist > lose_range:
					_set_state(State.IDLE)
				elif dist <= _reach() and (perceived or _lost_timer < 0.5):
					_set_state(State.ATTACK)
				elif _lost_timer > chase_memory:
					_set_state(State.SEARCH)
				else:
					_move_to_point(_last_known, chase_speed, delta)

		State.SEARCH:
			if _perceive(false):
				_alert()
			else:
				_state_timer += delta
				var flat := Vector2(_last_known.x - global_position.x, _last_known.z - global_position.z)
				if not _search_arrived and flat.length() > 1.2 and _state_timer < 12.0:
					_move_to_point(_last_known, wander_speed * 1.6, delta)
				else:
					if not _search_arrived:
						_search_arrived = true
						_state_timer = 0.0
					_stop()
					rotation.y += deg_to_rad(60.0) * delta        # look around
					if _state_timer >= search_look_time:
						_set_state(State.IDLE)

		State.ATTACK:
			_stop()
			if target == null:
				_set_state(State.IDLE)
			else:
				_face(target.global_position, delta)
				_play(Anim.ATTACK)
				_try_attack(attack_damage)
				if _distance_to_target() > _reach() * 1.3:
					_set_state(State.CHASE)

		State.DOWNED:
			downed_timer += delta
			_play(Anim.CRAWL)
			if target:
				if _distance_to_target() > _reach():
					_move_to_point(target.global_position, crawl_speed, delta)
				else:
					_stop()
					_face(target.global_position, delta)
					_try_attack(crawl_damage)
			else:
				_stop()
			if downed_timer >= stand_up_delay:
				_stand_up()

		State.STANDING, State.DEAD:
			_stop()

	move_and_slide()

	# Walk/idle comes from how fast he REALLY moves, not from the state
	if state in [State.IDLE, State.WANDER, State.CHASE, State.SEARCH]:
		var real := get_real_velocity()
		var spd := Vector2(real.x, real.z).length()
		_play(Anim.WALK if spd > walk_anim_min_speed else Anim.IDLE)

# ---------------- state helpers ----------------

func _set_state(s: State) -> void:
	state = s
	_state_timer = 0.0
	_search_arrived = false
	if s == State.CHASE:
		_lost_timer = 0.0
	if s == State.IDLE:
		_has_wander_point = false

func _alert() -> void:
	if target:
		_last_known = target.global_position
	_set_state(State.CHASE)

func _start_wander() -> void:
	var offset := Vector3(randf_range(-wander_radius, wander_radius), 0.0, randf_range(-wander_radius, wander_radius))
	var map := nav_agent.get_navigation_map()
	_wander_point = NavigationServer3D.map_get_closest_point(map, _home + offset)
	_set_state(State.WANDER)
	_has_wander_point = true     # after _set_state, which clears it only for IDLE

# Other scripts can call this: zombie.hear_noise(global_position, 30.0)
func hear_noise(pos: Vector3, loudness: float) -> void:
	if state == State.DEAD or state == State.STANDING or state == State.DOWNED:
		return
	if global_position.distance_to(pos) > loudness:
		return
	_last_known = pos
	if state == State.IDLE or state == State.WANDER or state == State.SEARCH:
		_set_state(State.SEARCH)

# ---------------- speed tracking ----------------

func _update_speeds(delta: float) -> void:
	if delta <= 0.0:
		return
	if person_node and is_instance_valid(person_node):
		var p := person_node.global_position
		_person_speed = Vector2(p.x - _last_person_pos.x, p.z - _last_person_pos.z).length() / delta
		_last_person_pos = p
	if car_node and is_instance_valid(car_node):
		var c := car_node.global_position
		_car_speed = Vector2(c.x - _last_car_pos.x, c.z - _last_car_pos.z).length() / delta
		_last_car_pos = c

# ---------------- target selection ----------------

func _pick_target() -> void:
	var has_person := person_node != null and is_instance_valid(person_node)
	var has_car := car_node != null and is_instance_valid(car_node)
	if has_car and has_person and _person_in_car():
		target = car_node
	elif has_person:
		target = person_node
	else:
		target = null

	if debug_target and target != _prev_target:
		_prev_target = target
		print("Zombie target -> ", target.name if target else "none", " | in_car=", _person_in_car())

func _person_in_car() -> bool:
	# 1) explicit node
	if in_car_node != null and in_car_property != "" and in_car_property in in_car_node:
		return bool(in_car_node.get(in_car_property))
	# 2) auto: look on Rob, then on the car
	if person_node != null and in_car_property != "" and in_car_property in person_node:
		return bool(person_node.get(in_car_property))
	if car_node != null and in_car_property != "" and in_car_property in car_node:
		return bool(car_node.get(in_car_property))
	# 3) optional fallback: hidden Rob = driving
	if hide_means_in_car and person_node != null and not person_node.visible:
		return true
	return false

func _distance_to_target() -> float:
	return global_position.distance_to(target.global_position)

func _reach() -> float:
	return car_reach if target == car_node else attack_range

# ---------------- senses ----------------

# alerted = already hunting: full 360 vision instead of the cone
func _perceive(alerted: bool) -> bool:
	if target == null:
		return false
	var to_target := target.global_position - global_position
	var dist := to_target.length()

	if dist <= notice_radius:
		return true

	if target == car_node:
		if dist <= hear_car_range and _car_speed > 1.0:
			return true
	else:
		if dist <= hear_sprint_range and Input.is_key_pressed(sprint_key) and _person_speed > 0.5:
			return true

	if dist <= sight_range:
		var in_cone := alerted
		if not in_cone:
			var flat := Vector3(to_target.x, 0, to_target.z).normalized()
			var forward := global_transform.basis.z
			if flip_facing:
				forward = -forward
			forward.y = 0
			forward = forward.normalized()
			in_cone = rad_to_deg(forward.angle_to(flat)) <= sight_angle
		if in_cone and (not need_line_of_sight or _has_line_of_sight()):
			return true
	return false

func _has_line_of_sight() -> bool:
	var from := global_position + Vector3.UP * eye_height
	var to := target.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var c = hit.collider
	return c == target or target.is_ancestor_of(c)

# ---------------- smart movement ----------------

func _move_to_point(point: Vector3, speed: float, delta: float) -> void:
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = repath_interval
		nav_agent.target_position = point

	nav_agent.max_speed = speed

	var next_pos := nav_agent.get_next_path_position()
	var dir := next_pos - global_position
	dir.y = 0.0

	if nav_agent.is_navigation_finished() or dir.length() < 0.05:
		next_pos = point
		dir = next_pos - global_position
		dir.y = 0.0

	dir = dir.normalized()
	dir = _steer_around(dir)

	_check_stuck(delta, point)
	if _sidestep_timer > 0.0:
		_sidestep_timer -= delta
		dir = dir.rotated(Vector3.UP, deg_to_rad(70.0) * _sidestep_dir).normalized()

	var desired := dir * speed
	if use_avoidance and nav_agent.avoidance_enabled:
		nav_agent.velocity = desired
		velocity.x = _safe_velocity.x
		velocity.z = _safe_velocity.z
		if _safe_velocity.length_squared() < 0.0001:
			velocity.x = desired.x
			velocity.z = desired.z
	else:
		velocity.x = desired.x
		velocity.z = desired.z

	var move_dir := Vector3(velocity.x, 0.0, velocity.z)
	if move_dir.length() > 0.1:
		_face(global_position + move_dir, delta)
	else:
		_face(next_pos, delta)

func _steer_around(dir: Vector3) -> Vector3:
	if dir == Vector3.ZERO:
		return dir
	var forward_hit := _whisker(dir)
	var left_hit := _whisker(dir.rotated(Vector3.UP, deg_to_rad(whisker_angle)))
	var right_hit := _whisker(dir.rotated(Vector3.UP, deg_to_rad(-whisker_angle)))

	if forward_hit < 0.0 and left_hit < 0.0 and right_hit < 0.0:
		return dir

	var result := dir
	if forward_hit >= 0.0:
		var turn := 1.0 if left_hit < 0.0 or left_hit > right_hit else -1.0
		result = dir.rotated(Vector3.UP, deg_to_rad(65.0) * turn * steer_strength)
	else:
		if left_hit >= 0.0:
			result = dir.rotated(Vector3.UP, deg_to_rad(-25.0) * steer_strength)
		elif right_hit >= 0.0:
			result = dir.rotated(Vector3.UP, deg_to_rad(25.0) * steer_strength)
	return result.normalized()

# Hit distance, or -1.0 if clear.
func _whisker(dir: Vector3) -> float:
	var from := global_position + Vector3.UP * whisker_height
	var to := from + dir * whisker_length
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1.0
	var c = hit.collider
	if target != null and (c == target or target.is_ancestor_of(c)):
		return -1.0
	if c is CharacterBody3D:
		return -1.0        # other enemies: avoidance handles them
	return from.distance_to(hit.position)

func _check_stuck(delta: float, goal: Vector3) -> void:
	_stuck_timer += delta
	if _stuck_timer < stuck_check_time:
		return
	_stuck_timer = 0.0
	var moved := Vector2(global_position.x - _stuck_check_pos.x, global_position.z - _stuck_check_pos.z).length()
	_stuck_check_pos = global_position
	var remaining := Vector2(goal.x - global_position.x, goal.z - global_position.z).length()
	if moved < 0.3 and remaining > 1.5:
		_repath_timer = 0.0
		_sidestep_timer = 0.6
		_sidestep_dir = 1.0 if randf() > 0.5 else -1.0

func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_safe_velocity = Vector3.ZERO
	_stuck_timer = 0.0

func _face(point: Vector3, delta: float) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), turn_speed * delta)

# ---------------- combat ----------------

func _try_attack(damage: int) -> void:
	if not attack_ready:
		return
	attack_ready = false
	await get_tree().create_timer(attack_hit_delay).timeout
	if (state == State.ATTACK or state == State.DOWNED) and target != null \
			and is_instance_valid(target) and _distance_to_target() <= _reach() * 1.3:
		if target.has_method("take_damage"):
			target.take_damage(damage)
		elif person_node != null and person_node.has_method("take_damage"):
			person_node.take_damage(damage)    # car has no health, Rob takes the hit
	await get_tree().create_timer(max(attack_cooldown - attack_hit_delay, 0.0)).timeout
	attack_ready = true

func take_damage(amount: int) -> void:
	if state == State.DEAD or state == State.STANDING:
		return

	health -= amount
	downed_timer = 0.0

	if state == State.IDLE or state == State.WANDER or state == State.SEARCH:
		if person_node and is_instance_valid(person_node):
			_last_known = person_node.global_position
		_set_state(State.CHASE)

	if health <= 0:
		if can_revive and not has_been_downed:
			_go_downed()
		else:
			_die()

func _go_downed() -> void:
	has_been_downed = true
	state = State.DOWNED
	health = downed_health
	downed_timer = 0.0
	attack_ready = true

func _stand_up() -> void:
	state = State.STANDING
	_play(Anim.STAND)
	await get_tree().create_timer(stand_up_duration).timeout
	if state != State.STANDING:
		return
	health = revive_health
	if person_node and is_instance_valid(person_node):
		_last_known = person_node.global_position
	_set_state(State.CHASE)   # next kill is permanent

func _die() -> void:
	state = State.DEAD
	_play(Anim.DIE)
	for c in find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", true)
	nav_agent.avoidance_enabled = false
	await get_tree().create_timer(despawn_time).timeout
	queue_free()

# ---------------- animation ----------------

func _play(anim: int) -> void:
	if animation_tree == null:
		return
	for i in BLEND_NODES.size():
		animation_tree.set("parameters/%s/blend_amount" % BLEND_NODES[i], 1.0 if i == anim else 0.0)
