extends CharacterBody3D

enum State { IDLE, WANDER, ALERT, CHASE, SEARCH, ATTACK, DOWNED, STANDING, DEAD }

@export_group("Targets (leave empty to auto-find)")
@export var person_node: Node3D
@export var car_node: Node3D
@export var nav_agent: NavigationAgent3D
@export var animation_tree: AnimationTree          # turned off; the AnimationPlayer is driven directly
@export var model_node: Node3D                     # auto: child that contains the Skeleton3ss  D
@export var player_name := "Rob"
@export var car_name := "Car"
@export var require_visible := false

@export_group("Sound slots (drag your mp3s here)")
@export var sfx_sniff: AudioStream
@export var sfx_growl: AudioStream
@export var sfx_hurt_half: AudioStream
@export var sfx_hurt_crawl: AudioStream
@export var sfx_idle: AudioStream
@export var sfx_bite: AudioStream
@export var voice_volume_db := 0.0
@export var idle_sound_min := 4.0
@export var idle_sound_max := 9.0
@export var sniff_range := 12.0
@export var sniff_interval := 3.5
@export var hurt_sound_cooldown := 0.4
@export var half_health_fraction := 0.5

@export_group("Senses")
@export var sprint_key: Key = KEY_SHIFT
@export var sight_range := 20.0
@export var sight_angle := 75.0
@export var notice_radius := 4.0
@export var hear_sprint_range := 28.0
@export var hear_vehicle_range := 45.0
@export var vehicle_speed := 5.0
@export var gunshot_action := "shoot_out"
@export var gunshot_range := 50.0
@export var need_line_of_sight := true
@export var eye_height := 1.6
@export var lose_range := 55.0
@export var chase_memory := 4.0

@export_group("Behaviour")
@export var wander_enabled := true
@export var wander_radius := 8.0
@export var idle_time_min := 2.0
@export var idle_time_max := 6.0
@export var search_look_time := 4.0
@export var alert_radius := 25.0
@export var runner_chance := 0.15
@export var runner_mult := 1.9

@export_group("Movement")
@export var speed := 2.5
@export var wander_speed_mult := 0.45
@export var crawl_speed := 1.0
@export var turn_speed := 8.0
@export var use_avoidance := true
@export var stagger_time := 0.35
@export var stagger_speed_mult := 0.25
@export var model_yaw_offset := 0.0                # radians
@export var flip_facing := false                   # tick if he walks/faces backwards
@export var slope_tilt := true
@export var tilt_speed := 6.0
@export var whisker_length := 2.0
@export var whisker_angle := 40.0
@export var whisker_height := 0.8
@export var steer_strength := 1.0

@export_group("Combat")
@export var max_health := 50.0
@export var attack_range := 1.8
@export var car_reach := 3.5
@export var attack_damage := 10.0
@export var attack_cooldown := 1.4
@export var hit_delay := 0.5
@export var crawl_damage := 5.0

@export_group("Downed / Revive")
@export var can_revive := true                     # untick for the robot
@export var downed_health := 30.0
@export var stand_up_delay := 8.0
@export var stand_up_duration := 2.5
@export var revive_health := 40.0
@export var despawn_time := 8.0

@export_group("Animation names (empty = auto-detect by keyword)")
@export var anim_idle := ""
@export var anim_walk := ""
@export var anim_attack := ""
@export var anim_die := ""
@export var anim_crawl := ""
@export var anim_stand := ""
@export var anim_hit := ""
@export var anim_blend := 0.25

@export_group("Crawl / ground fix")
@export var auto_ground_fix := true
@export var ground_margin := 0.12
@export var crawl_y_offset := 0.0
@export var crawl_collider_height := 0.6
@export var crawl_yaw_offset := 0.0                # degrees: 180 if he crawls backwards
@export var lock_root_motion := true
@export var root_bone_names: Array[String] = ["hips", "pelvis", "root"]

@export_group("Blood")
@export var blood_enabled := true
@export var blood_color := Color(0.55, 0.02, 0.02)
@export var blood_height := 1.1
@export var blood_amount := 60
@export var blood_spread := 55.0
@export var blood_speed := 7.0
@export var mist_enabled := true
@export var bleed_duration := 5.0
@export var splats_enabled := true
@export var splats_per_hit := 10
@export var splat_radius := 4.0
@export var splat_size_min := 0.3
@export var splat_size_max := 1.0
@export var drip_trail := true
@export var death_pool := true
@export var pool_size := 2.2
@export var splat_lifetime := 60.0
@export var max_splats := 300

@export var debug := false

var nav: NavigationAgent3D
var model: Node3D
var coll: CollisionShape3D
var anim: AnimationPlayer
var skeleton: Skeleton3D

var state := State.IDLE
var health := 0.0
var has_been_downed := false
var target: Node3D = null
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _clip := {}
var _named: Array = []
var _home := Vector3.ZERO
var _last_known := Vector3.ZERO
var _wander_point := Vector3.ZERO
var _state_timer := 0.0
var _idle_wait := 3.0
var _alert_wait := 0.6
var _lost_timer := 0.0
var _search_arrived := false
var _attack_timer := 0.0
var _downed_timer := 0.0
var _stagger_timer := 0.0
var _is_runner := false

var _prev_target: Node3D = null
var _tgt_prev := Vector3.ZERO
var _tgt_speed := 0.0
var _no_target_time := 0.0
var _warned_no_target := false
var _warned_receiver := false

var _repath_timer := 0.0
var _safe := Vector3.ZERO
var _stuck_timer := 0.0
var _stuck_pos := Vector3.ZERO
var _sidestep_timer := 0.0
var _sidestep_dir := 1.0
var _debug_timer := 0.0

var _model_base_y := 0.0
var _capsule: CapsuleShape3D
var _capsule_h := 0.0
var _coll_base_y := 0.0
var _fix_timer := 0.0
var _fix_target := 0.0
var _proc_fall := false

var _voice: AudioStreamPlayer3D
var _sfx: AudioStreamPlayer3D
var _idle_timer := 3.0
var _sniff_timer := 2.0
var _hurt_cd := 0.0
var _bleed: GPUParticles3D
var _bleed_time := 0.0
var _drip_timer := 0.0

static var _splat_mats: Array = []
static var _splats: Array = []

# ======================================================================
# setup
# ======================================================================

func _ready() -> void:
	add_to_group("enemies")
	floor_snap_length = 0.8
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	motion_mode = MOTION_MODE_GROUNDED

	health = max_health
	_home = global_position
	_stuck_pos = global_position

	coll = find_child("CollisionShape3D", true, false) as CollisionShape3D
	nav = nav_agent
	if nav == null:
		nav = find_child("NavigationAgent3D", true, false) as NavigationAgent3D
	if nav == null:
		nav = NavigationAgent3D.new()
		add_child(nav)
	model = model_node if model_node else _detect_model()
	if model == null:
		push_warning("Zombie: no model found. Assign model_node.")
		model = Node3D.new()
		add_child(model)
	_model_base_y = model.position.y
	_fix_target = _model_base_y

	nav.path_desired_distance = 0.8
	nav.target_desired_distance = 1.2
	nav.path_max_distance = 3.0
	nav.avoidance_enabled = use_avoidance
	nav.radius = 0.5
	nav.neighbor_distance = 6.0
	nav.max_neighbors = 8
	nav.time_horizon_agents = 1.5
	nav.velocity_computed.connect(_on_velocity_computed)

	speed *= randf_range(0.85, 1.25)
	_is_runner = randf() < runner_chance

	anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	var tree := animation_tree if animation_tree else find_child("AnimationTree", true, false) as AnimationTree
	if tree and anim:
		tree.active = false                          # tree runs clips freely; drive the player directly
	if anim == null:
		push_warning("Zombie: no AnimationPlayer found.")
	else:
		_resolve_clips()
		for role in ["idle", "walk", "crawl"]:
			if _has(role):
				anim.get_animation(_c(role)).loop_mode = Animation.LOOP_LINEAR
		for role in ["attack", "stand", "hit", "die"]:
			if _has(role):
				anim.get_animation(_c(role)).loop_mode = Animation.LOOP_NONE
		_lock_root_motion()
		if _has("idle"):
			_play("idle")
		elif _has("walk"):
			_play("walk")
			anim.speed_scale = 0.0

	if coll and coll.shape is CapsuleShape3D:
		_capsule = (coll.shape as CapsuleShape3D).duplicate()
		coll.shape = _capsule
		_capsule_h = _capsule.height
		_coll_base_y = coll.position.y

	_voice = AudioStreamPlayer3D.new()
	_voice.unit_size = 8.0
	_voice.max_distance = 60.0
	_voice.volume_db = voice_volume_db
	add_child(_voice)
	_sfx = AudioStreamPlayer3D.new()
	_sfx.unit_size = 8.0
	_sfx.max_distance = 40.0
	_sfx.volume_db = voice_volume_db
	add_child(_sfx)

	_make_bleed()
	_ensure_splat_assets()
	_idle_timer = randf_range(idle_sound_min, idle_sound_max)
	_sniff_timer = randf_range(1.0, sniff_interval)
	_set_state(State.IDLE)

func _detect_model() -> Node3D:
	var sk := find_child("Skeleton3D", true, false)
	if sk:
		var n: Node = sk
		while n.get_parent() != null and n.get_parent() != self:
			n = n.get_parent()
		if n is Node3D and n != self:
			return n as Node3D
	for c in get_children():
		if c is Node3D and not (c is CollisionShape3D) and not (c is CollisionPolygon3D):
			return c as Node3D
	return null

# finds clips by keyword so wrong names can't leave him stuck on walk/idle
func _resolve_clips() -> void:
	var all: Array = []
	for n in anim.get_animation_list():
		all.append(String(n))
	var taken: Array = []
	var roles := [
		["die", anim_die, ["death", "die", "dying", "dead"]],
		["crawl", anim_crawl, ["crawl"]],
		["attack", anim_attack, ["attack", "bite", "punch", "claw", "swipe"]],
		["hit", anim_hit, ["hit", "hurt", "damage", "flinch"]],
		["stand", anim_stand, ["stand_up", "standing_up", "stand up", "get_up", "getup", "rise", "revive", "stand"]],
		["walk", anim_walk, ["walk", "run", "shamble", "move"]],
		["idle", anim_idle, ["idle", "breath", "wait"]],
	]
	for r in roles:
		var role: String = r[0]
		var forced: String = r[1]
		if forced != "" and anim.has_animation(forced):
			_clip[role] = forced
			taken.append(forced)
			continue
		var found := ""
		for kw in r[2]:
			for n in all:
				var low: String = n.to_lower()
				if n in taken or low.contains("reset"):
					continue
				if low.contains(kw):
					found = n
					break
			if found != "":
				break
		if found != "":
			_clip[role] = found
			taken.append(found)
	for role in ["die", "attack", "walk"]:
		if not _has(role):
			push_warning("Zombie %s: no '%s' clip found. Available: %s" % [name, role, all])
	if debug:
		print("[", name, "] clips: ", _clip)

func _c(role: String) -> String:
	return _clip.get(role, "")

func _has(role: String) -> bool:
	return anim != null and _c(role) != "" and anim.has_animation(_c(role))

func _play(role: String, blend: float = -1.0, restart: bool = false) -> void:
	if not _has(role):
		return
	var clip := _c(role)
	if not restart and anim.is_playing() and anim.current_animation == clip:
		return
	if role != "walk" and role != "crawl":
		anim.speed_scale = 1.0
	anim.play(clip, anim_blend if blend < 0.0 else blend)

# removes net hip drift so crawl / walk clips don't slide the model
func _lock_root_motion() -> void:
	if not lock_root_motion or anim == null:
		return
	for role in ["idle", "walk", "attack", "crawl", "stand", "hit"]:
		if not _has(role):
			continue
		var a := anim.get_animation(_c(role))
		var length := maxf(a.length, 0.001)
		for ti in a.get_track_count():
			if a.track_get_type(ti) != Animation.TYPE_POSITION_3D:
				continue
			var path := String(a.track_get_path(ti)).to_lower()
			var bone := path.get_slice(":", path.get_slice_count(":") - 1)
			var is_root := false
			for rn in root_bone_names:
				if bone.contains(rn.to_lower()):
					is_root = true
					break
			if not is_root:
				continue
			var n := a.track_get_key_count(ti)
			if n < 2:
				continue
			var first: Vector3 = a.track_get_key_value(ti, 0)
			var last: Vector3 = a.track_get_key_value(ti, n - 1)
			var drift := Vector3(last.x - first.x, 0.0, last.z - first.z)
			for k in n:
				var v: Vector3 = a.track_get_key_value(ti, k)
				var frac := a.track_get_key_time(ti, k) / length
				a.track_set_key_value(ti, k, v - drift * frac)

func _make_bleed() -> void:
	_bleed = GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 1.1
	mat.gravity = Vector3(0, -9.8, 0)
	_bleed.process_material = mat
	_bleed.draw_pass_1 = _blood_mesh(0.022)
	_bleed.amount = 18
	_bleed.lifetime = 0.9
	_bleed.one_shot = false
	_bleed.emitting = false
	_bleed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bleed.position = Vector3(0, blood_height * 0.7, 0)
	add_child(_bleed)

func _blood_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = blood_color
	mesh.material = m
	return mesh

# ======================================================================
# main loop
# ======================================================================

func _physics_process(delta: float) -> void:
	_tick_timers(delta)

	if state == State.DEAD:
		_tilt_to_ground(delta)
		_ground_fix(delta)
		return

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	_update_target(delta)
	_listen_for_gunshot()

	match state:
		State.IDLE:
			_move(Vector3.ZERO)
			_state_timer += delta
			if _perceive(false):
				_become_alert(true)
			else:
				_suspicion(delta)
				if wander_enabled and _state_timer >= _idle_wait:
					_start_wander()

		State.WANDER:
			if _perceive(false):
				_become_alert(true)
			else:
				_suspicion(delta)
				var flat := Vector2(_wander_point.x - global_position.x, _wander_point.z - global_position.z)
				_state_timer += delta
				if flat.length() < 1.2 or _state_timer > 15.0:
					_set_state(State.IDLE)
				else:
					_move_to(_wander_point, speed * wander_speed_mult, delta)

		State.ALERT:
			_move(Vector3.ZERO)
			var look := _last_known - global_position
			look.y = 0.0
			_face(look.normalized(), delta)
			_state_timer += delta
			if _state_timer >= _alert_wait:
				_set_state(State.CHASE)

		State.CHASE:
			if target == null:
				_set_state(State.IDLE)
			else:
				var seen := _perceive(true)
				if seen:
					_lost_timer = 0.0
					_last_known = target.global_position
				else:
					_lost_timer += delta
				var flat_d := _flat_dist(target.global_position)
				if flat_d <= _reach() and (seen or _lost_timer < 0.5):
					_set_state(State.ATTACK)
					_move(Vector3.ZERO)
				elif _lost_timer > chase_memory:
					_set_state(State.SEARCH)
				else:
					_move_to(_last_known, _chase_speed() * _stagger_mult(), delta)

		State.SEARCH:
			if _perceive(false):
				_become_alert(false)
			else:
				_state_timer += delta
				var flat := Vector2(_last_known.x - global_position.x, _last_known.z - global_position.z)
				if not _search_arrived and flat.length() > 1.5 and _state_timer < 14.0:
					_move_to(_last_known, speed * 0.8 * _stagger_mult(), delta)
				else:
					if not _search_arrived:
						_search_arrived = true
						_state_timer = 0.0
						_say("sniff")
					_move(Vector3.ZERO)
					model.rotation.y += deg_to_rad(50.0) * delta
					if _state_timer >= search_look_time:
						_set_state(State.IDLE)

		State.ATTACK:
			_move(Vector3.ZERO)
			if target == null:
				_set_state(State.IDLE)
			else:
				var to_t := target.global_position - global_position
				to_t.y = 0.0
				_face(to_t.normalized(), delta)
				if to_t.length() > _reach() * 1.3:
					_set_state(State.CHASE)
				elif _attack_timer <= 0.0:
					_attack_timer = attack_cooldown
					_play("attack", 0.1, true)
					_deal_damage(attack_damage)

		State.DOWNED:
			_downed_timer += delta
			if target:
				if _flat_dist(target.global_position) > _reach():
					_move_to(target.global_position, crawl_speed, delta, true)
				else:
					_move(Vector3.ZERO)
					var to_t := target.global_position - global_position
					to_t.y = 0.0
					_face(to_t.normalized(), delta, deg_to_rad(crawl_yaw_offset))
					if _attack_timer <= 0.0:
						_attack_timer = attack_cooldown
						_deal_damage(crawl_damage)
			else:
				_move(Vector3.ZERO)
			if _downed_timer >= stand_up_delay:
				_stand_up()

		State.STANDING:
			_move(Vector3.ZERO)

	move_and_slide()
	_tilt_to_ground(delta)
	_ground_fix(delta)
	_update_animation(delta)

	if debug:
		_debug_timer -= delta
		if _debug_timer <= 0.0:
			_debug_timer = 1.0
			print("[", name, "] ", State.keys()[state], " target=", target.name if target else "none",
				" hp=", health, " tgt_speed=", snappedf(_tgt_speed, 0.1))

func _tick_timers(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_stagger_timer = maxf(_stagger_timer - delta, 0.0)
	_hurt_cd = maxf(_hurt_cd - delta, 0.0)
	if _bleed_time > 0.0:
		_bleed_time -= delta
	if _bleed:
		_bleed.emitting = _bleed_time > 0.0 and blood_enabled

	if drip_trail and splats_enabled and blood_enabled and _bleed_time > 0.0:
		_drip_timer -= delta
		if _drip_timer <= 0.0:
			_drip_timer = randf_range(0.25, 0.5)
			_floor_splat(global_position + Vector3(randf_range(-0.3, 0.3), 0.5, randf_range(-0.3, 0.3)),
				randf_range(0.15, 0.35))

	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = randf_range(idle_sound_min, idle_sound_max)
		if state == State.IDLE or state == State.WANDER:
			_say("idle")

func _set_state(s: State) -> void:
	var prev := state
	state = s
	_state_timer = 0.0
	_search_arrived = false
	if s == State.CHASE:
		_lost_timer = 0.0
	if s == State.IDLE:
		_idle_wait = randf_range(idle_time_min, idle_time_max)
	if s == State.SEARCH and prev != State.SEARCH:
		_say("sniff")

# ======================================================================
# target + senses
# ======================================================================

func _player_dead() -> bool:
	for n in get_tree().get_nodes_in_group("player_health"):
		if bool(n.get("is_dead")):
			return true
	return false

# chases whatever the player is controlling right now (Rob on foot, or the car):
# any node in group "player" / "car" whose is_active is true
func _find_target(max_dist: float = INF) -> Node3D:
	if _player_dead():
		return null
	var cands: Array = []
	cands.append_array(get_tree().get_nodes_in_group("player"))
	cands.append_array(get_tree().get_nodes_in_group("car"))
	if person_node:
		cands.append(person_node)
	if car_node:
		cands.append(car_node)
	if cands.is_empty():
		_named = _named.filter(func(x): return is_instance_valid(x))
		if _named.is_empty():
			var root := get_tree().current_scene
			if root:
				for nm in [player_name, car_name]:
					var f := root.find_child(nm, true, false)
					if f:
						_named.append(f)
		cands = _named

	var best: Node3D = null
	var best_d: float = max_dist
	for t in cands:
		if not (t is Node3D) or not is_instance_valid(t):
			continue
		if require_visible and not t.visible:
			continue
		if "is_active" in t and not bool(t.get("is_active")):
			continue
		var d := global_position.distance_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best

func _update_target(delta: float) -> void:
	target = _find_target(lose_range)
	if target != _prev_target:
		_prev_target = target
		_tgt_speed = 0.0
		_tgt_prev = target.global_position if target else Vector3.ZERO
	elif target:
		var raw := Vector2(target.global_position.x - _tgt_prev.x, target.global_position.z - _tgt_prev.z).length() / maxf(delta, 0.0001)
		_tgt_speed = lerpf(_tgt_speed, raw, 0.3)
		_tgt_prev = target.global_position
	if target == null and state in [State.CHASE, State.ATTACK, State.ALERT]:
		_set_state(State.IDLE)

	if target == null and not _warned_no_target and not _player_dead():
		_no_target_time += delta
		if _no_target_time > 3.0 and _find_target() == null:
			_warned_no_target = true
			push_warning("Zombie: no valid target. Rob must be in group 'player' with is_active true (car in group 'car').")
	else:
		_no_target_time = 0.0

func _target_sprinting() -> bool:
	if target and "is_sprinting" in target:
		return bool(target.get("is_sprinting"))
	return Input.is_key_pressed(sprint_key)

func _perceive(alerted: bool) -> bool:
	if target == null:
		return false
	var to_t := target.global_position - global_position
	var dist := to_t.length()

	if dist <= notice_radius:
		return true
	if _tgt_speed > vehicle_speed and dist <= hear_vehicle_range:
		return true
	if dist <= hear_sprint_range and _target_sprinting() and _tgt_speed > 0.5:
		return true

	if dist <= sight_range:
		var in_cone := alerted
		if not in_cone:
			var yaw := rotation.y + model.rotation.y - model_yaw_offset - (PI if flip_facing else 0.0)
			var forward := Vector3(sin(yaw), 0.0, cos(yaw))
			var flat := Vector3(to_t.x, 0.0, to_t.z).normalized()
			in_cone = rad_to_deg(forward.angle_to(flat)) <= sight_angle
		if in_cone and (not need_line_of_sight or _has_line_of_sight()):
			return true
	return false

func _has_line_of_sight() -> bool:
	var from := global_position + Vector3.UP * eye_height
	var to := target.global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var c = hit.collider
	return c == target or target.is_ancestor_of(c)

func _suspicion(delta: float) -> void:
	if target == null:
		return
	_sniff_timer -= delta
	if _sniff_timer > 0.0:
		return
	if _flat_dist(target.global_position) <= sniff_range:
		_sniff_timer = sniff_interval * randf_range(0.8, 1.3)
		_say("sniff")

func _listen_for_gunshot() -> void:
	if gunshot_action == "" or not InputMap.has_action(gunshot_action):
		return
	if not Input.is_action_just_pressed(gunshot_action):
		return
	if not (state in [State.IDLE, State.WANDER, State.SEARCH]):
		return
	var p := _find_target()
	if p and global_position.distance_to(p.global_position) <= gunshot_range:
		_last_known = p.global_position
		_set_state(State.SEARCH)

func _become_alert(broadcast: bool = true) -> void:
	if target:
		_last_known = target.global_position
	_alert_wait = randf_range(0.5, 0.9)
	_set_state(State.ALERT)
	_say("growl")
	if broadcast:
		get_tree().call_group("enemies", "hear_shout", global_position, _last_known, alert_radius)

func hear_shout(src: Vector3, where: Vector3, radius: float) -> void:
	if not (state in [State.IDLE, State.WANDER]):
		return
	if global_position.distance_to(src) > radius:
		return
	_last_known = where
	_set_state(State.SEARCH)

func hear_noise(pos: Vector3, loudness: float) -> void:
	if not (state in [State.IDLE, State.WANDER, State.SEARCH]):
		return
	if global_position.distance_to(pos) > loudness:
		return
	_last_known = pos
	_set_state(State.SEARCH)

# ======================================================================
# movement
# ======================================================================

func _start_wander() -> void:
	var offset := Vector3(randf_range(-wander_radius, wander_radius), 0.0, randf_range(-wander_radius, wander_radius))
	_wander_point = NavigationServer3D.map_get_closest_point(nav.get_navigation_map(), _home + offset)
	_set_state(State.WANDER)

func _chase_speed() -> float:
	return speed * (runner_mult if _is_runner else 1.0)

func _stagger_mult() -> float:
	return stagger_speed_mult if _stagger_timer > 0.0 else 1.0

func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

func _reach() -> float:
	if target and (target == car_node or target.is_in_group("car")):
		return car_reach
	return attack_range

func _move_to(point: Vector3, spd: float, delta: float, crawling: bool = false) -> void:
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = 0.2
		nav.target_position = point
	nav.max_speed = spd

	var dir := nav.get_next_path_position() - global_position
	dir.y = 0.0
	if nav.is_navigation_finished() or dir.length() < 0.1:
		dir = point - global_position
		dir.y = 0.0
	dir = dir.normalized()

	# crawling = steady straight movement, no steering or avoidance
	if crawling:
		_face(dir, delta, deg_to_rad(crawl_yaw_offset))
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		return

	dir = _steer_around(dir)
	_check_stuck(delta, point)
	if _sidestep_timer > 0.0:
		_sidestep_timer -= delta
		dir = dir.rotated(Vector3.UP, deg_to_rad(70.0) * _sidestep_dir).normalized()
	_face(dir, delta)
	_move(dir * spd)

func _steer_around(dir: Vector3) -> Vector3:
	if dir == Vector3.ZERO:
		return dir
	var f := _whisker(dir)
	var l := _whisker(dir.rotated(Vector3.UP, deg_to_rad(whisker_angle)))
	var r := _whisker(dir.rotated(Vector3.UP, deg_to_rad(-whisker_angle)))
	if f < 0.0 and l < 0.0 and r < 0.0:
		return dir
	var result := dir
	if f >= 0.0:
		var turn := 1.0 if l < 0.0 or l > r else -1.0
		result = dir.rotated(Vector3.UP, deg_to_rad(65.0) * turn * steer_strength)
	elif l >= 0.0:
		result = dir.rotated(Vector3.UP, deg_to_rad(-25.0) * steer_strength)
	elif r >= 0.0:
		result = dir.rotated(Vector3.UP, deg_to_rad(25.0) * steer_strength)
	return result.normalized()

# hit distance, or -1.0 if clear. Walkable slopes don't count as obstacles.
func _whisker(dir: Vector3) -> float:
	var from := global_position + Vector3.UP * whisker_height
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * whisker_length)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return -1.0
	if hit.normal.y > 0.5:
		return -1.0
	var c = hit.collider
	if target != null and (c == target or target.is_ancestor_of(c)):
		return -1.0
	if c is CharacterBody3D:
		return -1.0
	return from.distance_to(hit.position)

func _check_stuck(delta: float, goal: Vector3) -> void:
	_stuck_timer += delta
	if _stuck_timer < 1.0:
		return
	_stuck_timer = 0.0
	var moved := global_position.distance_to(_stuck_pos)
	_stuck_pos = global_position
	if moved < 0.3 and _flat_dist(goal) > 1.5:
		_repath_timer = 0.0
		_sidestep_timer = 0.6
		_sidestep_dir = 1.0 if randf() > 0.5 else -1.0

func _move(desired: Vector3) -> void:
	if desired.length_squared() < 0.0001:
		velocity.x = 0.0
		velocity.z = 0.0
		_safe = Vector3.ZERO
		if nav.avoidance_enabled:
			nav.velocity = Vector3.ZERO
		return
	if use_avoidance and nav.avoidance_enabled:
		nav.velocity = desired
		velocity.x = _safe.x
		velocity.z = _safe.z
		if _safe.length_squared() < 0.0001:
			velocity.x = desired.x
			velocity.z = desired.z
	else:
		velocity.x = desired.x
		velocity.z = desired.z

func _on_velocity_computed(safe: Vector3) -> void:
	_safe = safe

func _face(dir: Vector3, delta: float, extra: float = 0.0) -> void:
	if dir.length() < 0.01:
		return
	var want := atan2(dir.x, dir.z) - rotation.y + model_yaw_offset + (PI if flip_facing else 0.0) + extra
	model.rotation.y = lerp_angle(model.rotation.y, want, turn_speed * delta)

# tilts the model to the slope. The floor normal is rotated into the model's
# pre-yaw frame first; skipping that was why he sank into hills.
func _tilt_to_ground(delta: float) -> void:
	if not slope_tilt or _proc_fall:
		return
	var n := get_floor_normal() if is_on_floor() else Vector3.UP
	var ln := Basis(Vector3.UP, model.rotation.y).inverse() * (global_transform.basis.inverse() * n)
	var tx := atan2(ln.z, ln.y)
	var tz := -asin(clampf(ln.x, -1.0, 1.0))
	model.rotation.x = lerp_angle(model.rotation.x, tx, tilt_speed * delta)
	model.rotation.z = lerp_angle(model.rotation.z, tz, tilt_speed * delta)

# ======================================================================
# animation
# ======================================================================

func _update_animation(delta: float) -> void:
	if anim == null:
		return
	var real := get_real_velocity()
	var spd := Vector2(real.x, real.z).length()
	var moving := spd > 0.25

	if state == State.DOWNED:
		_play("crawl")
		var wc := clampf(spd / maxf(crawl_speed, 0.1), 0.0, 2.0) if moving else 0.0
		anim.speed_scale = lerpf(anim.speed_scale, wc, clampf(8.0 * delta, 0.0, 1.0))
		return
	if state == State.STANDING:
		return
	# let one-shot swings / hit reactions finish
	if anim.is_playing() and (anim.current_animation == _c("attack") or anim.current_animation == _c("hit")):
		return

	if _has("idle"):
		if moving:
			_play("walk")
			anim.speed_scale = clampf(spd / maxf(speed, 0.1), 0.5, 2.5)
		else:
			_play("idle")
	else:
		_play("walk")
		var want := clampf(spd / maxf(speed, 0.1), 0.0, 2.5) if moving else 0.0
		anim.speed_scale = lerpf(anim.speed_scale, want, clampf(8.0 * delta, 0.0, 1.0))

# ======================================================================
# crawl / hill ground fix
# ======================================================================

func _set_crawl_collider(on: bool) -> void:
	if _capsule == null:
		return
	if on:
		var h := maxf(crawl_collider_height, _capsule.radius * 2.0 + 0.01)
		_capsule.height = h
		coll.position.y = _coll_base_y - (_capsule_h - h) * 0.5
	else:
		_capsule.height = _capsule_h
		coll.position.y = _coll_base_y

# lying down: samples ~14 bones against the ground below each, lifts the model by
# the deepest penetration. Rises fast (no clipping), settles slowly.
func _ground_fix(delta: float) -> void:
	if skeleton == null or not auto_ground_fix:
		return
	var lying := state == State.DOWNED or state == State.STANDING or state == State.DEAD
	if not lying:
		model.position.y = lerpf(model.position.y, _model_base_y, clampf(12.0 * delta, 0.0, 1.0))
		_fix_target = _model_base_y
		return

	_fix_timer -= delta
	if _fix_timer <= 0.0:
		_fix_timer = 0.05
		var space := get_world_3d().direct_space_state
		var count := skeleton.get_bone_count()
		var stride := maxi(count / 14, 1)
		var worst := -INF
		for i in range(0, count, stride):
			var p := skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 2.0)
			q.exclude = [get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty() or hit.collider is CharacterBody3D:
				continue
			worst = maxf(worst, hit.position.y + ground_margin - p.y)
		if worst > -INF:
			_fix_target = maxf(model.position.y + worst + crawl_y_offset, _model_base_y)

	var cur := model.position.y
	var rate := 30.0 if _fix_target > cur else 8.0
	model.position.y = lerpf(cur, _fix_target, clampf(rate * delta, 0.0, 1.0))

# ======================================================================
# combat
# ======================================================================

func _damage_receiver() -> Node:
	if target and target.has_method("take_damage"):
		return target
	for n in get_tree().get_nodes_in_group("player_health"):
		if n.has_method("take_damage"):
			return n
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_method("take_damage"):
			return p
	if person_node and person_node.has_method("take_damage"):
		return person_node
	return null

func _deal_damage(amount: float) -> void:
	await get_tree().create_timer(hit_delay).timeout
	if not (state == State.ATTACK or state == State.DOWNED):
		return
	if target == null or not is_instance_valid(target):
		return
	if _flat_dist(target.global_position) > _reach() * 1.4:
		return
	var rx := _damage_receiver()
	if rx == null:
		if not _warned_receiver:
			_warned_receiver = true
			push_warning("Zombie: nothing to damage. Rob needs take_damage() (and a PlayerHealth child, or a node in group 'player_health').")
		return
	rx.take_damage(amount)
	_say("bite")
	if debug:
		print("[", name, "] bite landed on ", rx.name)

func take_damage(amount: float, hit_pos: Vector3 = Vector3.INF, hit_normal: Vector3 = Vector3.ZERO) -> void:
	if state == State.DEAD or state == State.STANDING:
		return

	health -= amount
	_downed_timer = 0.0
	_stagger_timer = stagger_time
	_blood_hit(hit_pos, hit_normal, health <= 0.0)

	if state in [State.IDLE, State.WANDER, State.SEARCH]:
		var p := _find_target()
		if p:
			_last_known = p.global_position
		_alert_wait = 0.1
		_set_state(State.ALERT)
		get_tree().call_group("enemies", "hear_shout", global_position, _last_known, alert_radius)

	if health <= 0.0:
		if can_revive and not has_been_downed and _has("crawl"):
			_go_downed()
		else:
			_die()
	else:
		_hurt_sound()
		if state != State.DOWNED and _has("hit"):
			_play("hit", 0.05, true)

func _hurt_sound() -> void:
	if _hurt_cd > 0.0:
		return
	if state == State.DOWNED:
		_hurt_cd = hurt_sound_cooldown
		_say("hurt_crawl")
	elif health <= max_health * half_health_fraction:
		_hurt_cd = hurt_sound_cooldown
		_say("hurt_half")

func _go_downed() -> void:
	has_been_downed = true
	_set_state(State.DOWNED)
	health = downed_health
	_downed_timer = 0.0
	_attack_timer = 0.0
	_set_crawl_collider(true)
	_bleed.position.y = 0.3
	_bleed_time = bleed_duration
	_play("crawl", 0.2, true)
	_say("hurt_crawl")

func _stand_up() -> void:
	_set_state(State.STANDING)
	_set_crawl_collider(false)
	_bleed.position.y = blood_height * 0.7
	_play("stand", 0.2, true)
	await get_tree().create_timer(stand_up_duration).timeout
	if state != State.STANDING:
		return
	health = revive_health
	var p := _find_target()
	if p:
		_last_known = p.global_position
	_set_state(State.CHASE)
	_say("growl")

func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	_move(Vector3.ZERO)
	nav.avoidance_enabled = false
	if coll:
		coll.set_deferred("disabled", true)
	remove_from_group("enemies")
	_bleed.position.y = 0.3
	_bleed_time = bleed_duration * 2.0
	_say("hurt_crawl")
	if _has("die"):
		anim.speed_scale = 1.0
		anim.play(_c("die"), 0.1)
	else:
		# no death clip found: stop the walk/idle loop and topple him
		if anim:
			anim.pause()
		_proc_fall = true
		model.rotation.z = 0.0
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", PI * 0.5, 0.6).set_ease(Tween.EASE_IN)
	if death_pool and blood_enabled and splats_enabled:
		_grow_pool()
	await get_tree().create_timer(despawn_time).timeout
	queue_free()

# ======================================================================
# blood
# ======================================================================

func _blood_hit(pos: Vector3, normal: Vector3, big: bool = false) -> void:
	if not blood_enabled:
		return
	var p := pos
	if not p.is_finite():
		p = global_position + Vector3.UP * (0.4 if state == State.DOWNED else blood_height)

	var dir := normal
	if dir == Vector3.ZERO:
		var src := _find_target()
		dir = (global_position - src.global_position) if src else Vector3.BACK
		dir.y = 0.0
		dir = dir.normalized()

	var mult := 2.0 if big else 1.0
	var spray := (dir + Vector3.UP * 0.3).normalized()
	_spawn_blood(p, spray, int(blood_amount * mult))
	if mist_enabled:
		_spawn_mist(p, spray)
	_bleed_time = bleed_duration
	if splats_enabled:
		_splat_burst(p, dir, int(splats_per_hit * mult))

func _spawn_blood(pos: Vector3, dir: Vector3, amount: int) -> void:
	var pt := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = dir
	mat.spread = blood_spread
	mat.initial_velocity_min = blood_speed * 0.3
	mat.initial_velocity_max = blood_speed
	mat.gravity = Vector3(0, -14.0, 0)
	mat.scale_min = 0.5
	mat.scale_max = 2.0
	pt.process_material = mat
	pt.draw_pass_1 = _blood_mesh(0.025)
	pt.amount = amount
	pt.lifetime = 1.1
	pt.one_shot = true
	pt.explosiveness = 0.95
	pt.emitting = false
	pt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(pt)
	pt.global_position = pos
	pt.emitting = true
	get_tree().create_timer(1.6).timeout.connect(pt.queue_free)

func _spawn_mist(pos: Vector3, dir: Vector3) -> void:
	var c := blood_color
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, 0.45), Color(c.r, c.g, c.b, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = g

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 2.4))
	var ct := CurveTexture.new()
	ct.curve = curve

	var mat := ParticleProcessMaterial.new()
	mat.direction = dir
	mat.spread = 60.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 2.5
	mat.gravity = Vector3(0, -1.0, 0)
	mat.color_ramp = gt
	mat.scale_curve = ct

	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 8
	mesh.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	mesh.material = m

	var pt := GPUParticles3D.new()
	pt.process_material = mat
	pt.draw_pass_1 = mesh
	pt.amount = 10
	pt.lifetime = 0.7
	pt.one_shot = true
	pt.explosiveness = 1.0
	pt.emitting = false
	pt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(pt)
	pt.global_position = pos
	pt.emitting = true
	get_tree().create_timer(1.2).timeout.connect(pt.queue_free)

func _splat_burst(origin: Vector3, dir: Vector3, count: int) -> void:
	var space := get_world_3d().direct_space_state
	var flat_dir := Vector3(dir.x, 0.0, dir.z)
	for i in count:
		var from := origin
		var to: Vector3
		if i % 2 == 0:
			var rnd := Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6), randf_range(-1.0, 1.0)).normalized()
			var d := (dir * 0.7 + rnd).normalized()
			to = from + d * randf_range(1.0, splat_radius)
		else:
			var off := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * splat_radius * 0.5
			off += flat_dir * randf_range(0.0, splat_radius * 0.6)
			from = Vector3(origin.x + off.x, origin.y + 0.3, origin.z + off.z)
			to = from + Vector3.DOWN * 5.0
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		if hit.collider is CharacterBody3D:
			continue
		_place_splat(hit.position, hit.normal, randf_range(splat_size_min, splat_size_max), 1.0)

func _floor_splat(from: Vector3, size: float) -> void:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	_place_splat(hit.position, hit.normal, size, 1.0)

func _place_splat(pos: Vector3, n: Vector3, size: float, start_scale: float) -> MeshInstance3D:
	if _splat_mats.is_empty():
		return null
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = _splat_mats[randi() % _splat_mats.size()]

	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos + n * randf_range(0.01, 0.025)
	var up_hint := Vector3.RIGHT if absf(n.y) > 0.99 else Vector3.UP
	mi.global_transform.basis = Basis.looking_at(-n, up_hint).rotated(n, randf() * TAU)
	mi.scale = Vector3.ONE * start_scale

	_splats.append(mi)
	while _splats.size() > max_splats:
		var old = _splats.pop_front()
		if is_instance_valid(old):
			old.queue_free()

	if start_scale >= 1.0:
		var tw := mi.create_tween()
		tw.tween_interval(splat_lifetime)
		tw.tween_property(mi, "scale", Vector3.ZERO, 2.0)
		tw.tween_callback(mi.queue_free)
	return mi

func _grow_pool() -> void:
	await get_tree().create_timer(0.9).timeout
	var from := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var mi := _place_splat(hit.position, hit.normal, pool_size, 0.15)
	if mi == null:
		return
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 7.0).set_ease(Tween.EASE_OUT)
	tw.tween_interval(splat_lifetime)
	tw.tween_property(mi, "scale", Vector3.ZERO, 2.0)
	tw.tween_callback(mi.queue_free)

func _ensure_splat_assets() -> void:
	if not _splat_mats.is_empty():
		return
	for v in 3:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7001 + v * 97
		var size := 64
		var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(blood_color.r, blood_color.g, blood_color.b, 0.0))

		var blobs: Array = []
		var centre := Vector2(32.0, 32.0)
		blobs.append([centre, rng.randf_range(7.0, 11.0)])
		for i in rng.randi_range(9, 15):
			var a := rng.randf() * TAU
			var d := rng.randf_range(8.0, 25.0)
			blobs.append([centre + Vector2(cos(a), sin(a)) * d, rng.randf_range(1.2, 4.0)])

		for y in size:
			for x in size:
				var p := Vector2(x, y)
				var best := 0.0
				for b in blobs:
					var r: float = b[1]
					var val := 1.0 - p.distance_to(b[0]) / r
					if val > best:
						best = val
				if best > 0.0:
					img.set_pixel(x, y, Color(blood_color.r, blood_color.g, blood_color.b, clampf(best * 3.0, 0.0, 1.0) * 0.92))

		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.roughness = 0.25
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_splat_mats.append(m)

# ======================================================================
# sound
# ======================================================================

func _say(kind: String) -> void:
	var stream: AudioStream = null
	match kind:
		"sniff": stream = sfx_sniff
		"growl": stream = sfx_growl
		"hurt_half": stream = sfx_hurt_half
		"hurt_crawl": stream = sfx_hurt_crawl
		"idle": stream = sfx_idle
		"bite": stream = sfx_bite
	if stream == null:
		return

	if kind == "bite":
		_sfx.stream = stream
		_sfx.pitch_scale = randf_range(0.95, 1.05)
		_sfx.play()
		return

	if (kind == "idle" or kind == "sniff") and _voice.playing:
		return
	_voice.stream = stream
	_voice.pitch_scale = randf_range(0.93, 1.07)
	_voice.play()
