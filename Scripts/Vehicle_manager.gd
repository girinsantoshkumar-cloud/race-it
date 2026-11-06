extends Node

var character: CharacterBody3D = null
var vehicles: Array[RigidBody3D] = []
var current: RigidBody3D = null
var nearby: RigidBody3D = null

var vehicle: RigidBody3D:
	get:
		return current
	set(v):
		register_vehicle(v)

@export var interact_action := "interact"
@export var show_exit_prompt := true
@export var press_cooldown := 0.3
@export var debug_overlay := false               # set true to see the yellow status box
@export var character_collision_path: NodePath = ^"CollisionShape3D"
@export var character_camera_path: NodePath = ^"CameraPivot/car_cam"

var _label: Label
var _dbg: Label
var _cooldown := 0.0
var _scan_timer := 0.0
var _find_timer := 0.0
var _e_prev := false
var _warned_action := false


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	_label = Label.new()
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 0.0
	_label.offset_right = 0.0
	_label.offset_top = -170.0
	_label.offset_bottom = -110.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	_label.visible = false
	layer.add_child(_label)

	_dbg = Label.new()
	_dbg.position = Vector2(10, 10)
	_dbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dbg.add_theme_font_size_override("font_size", 16)
	_dbg.add_theme_color_override("font_color", Color(1, 1, 0.3))
	_dbg.add_theme_color_override("font_outline_color", Color.BLACK)
	_dbg.add_theme_constant_override("outline_size", 6)
	_dbg.visible = debug_overlay
	layer.add_child(_dbg)


func register_vehicle(v: RigidBody3D) -> void:
	if is_instance_valid(v) and not vehicles.has(v):
		vehicles.append(v)


func unregister_vehicle(v: RigidBody3D) -> void:
	vehicles.erase(v)
	if current == v:
		current = null
	if nearby == v:
		nearby = null


# ---------------------------------------------------------------- helpers

func _find_character() -> CharacterBody3D:
	for n in get_tree().get_nodes_in_group("player"):
		if n is CharacterBody3D:
			return n as CharacterBody3D
	var root := get_tree().current_scene
	if root == null:
		return null
	var r := root.find_child("Rob", true, false)
	if r is CharacterBody3D:
		return r as CharacterBody3D
	for n in root.find_children("*", "CharacterBody3D", true, false):
		if "is_active" in n and not n.is_in_group("enemies") and not n.is_in_group("car"):
			return n as CharacterBody3D
	return null


func _char_active() -> bool:
	var a = character.get("is_active")
	return a == null or bool(a)


func _interact_pressed() -> bool:
	if InputMap.has_action(interact_action):
		return Input.is_action_just_pressed(interact_action)
	if not _warned_action:
		_warned_action = true
		push_warning("VehicleManager: input action '%s' missing, using the E key." % interact_action)
	var now := Input.is_key_pressed(KEY_E)
	var pressed := now and not _e_prev
	_e_prev = now
	return pressed


func _key_text() -> String:
	if InputMap.has_action(interact_action):
		for ev in InputMap.action_get_events(interact_action):
			if ev is InputEventKey:
				var code: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
				return OS.get_keycode_string(code)
	return "E"


func _collision_of_character() -> CollisionShape3D:
	var c := character.get_node_or_null(character_collision_path) as CollisionShape3D
	if c == null:
		var shapes := character.find_children("*", "CollisionShape3D", false, false)
		if not shapes.is_empty():
			c = shapes[0] as CollisionShape3D
	return c


func _character_camera() -> Camera3D:
	var cam := character.get("camera") as Camera3D
	if cam == null:
		cam = character.get_node_or_null(character_camera_path) as Camera3D
	if cam == null:
		var cams := character.find_children("*", "Camera3D", true, false)
		if not cams.is_empty():
			cam = cams[0] as Camera3D
	return cam


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	_tick(delta)
	_dbg.visible = debug_overlay
	if debug_overlay:
		_update_debug()


func _tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)

	if not is_instance_valid(character):
		_find_timer -= delta
		if _find_timer <= 0.0:
			_find_timer = 0.5
			character = _find_character()
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 1.0
		for n in get_tree().get_nodes_in_group("car"):
			if n is RigidBody3D:
				register_vehicle(n)

	if not is_instance_valid(character):
		_label.visible = false
		return

	if is_instance_valid(current):
		nearby = null
		_label.visible = show_exit_prompt
		_label.text = "[%s] Exit" % _key_text()
		if _interact_pressed() and _cooldown <= 0.0:
			exit_vehicle()
		return

	nearby = _find_nearby()
	if nearby == null or not _char_active():
		_label.visible = false
		_interact_pressed()
		return

	var verb = nearby.get("prompt_text")
	_label.text = "[%s] %s" % [_key_text(), verb if verb else "Drive"]
	_label.visible = true
	if _interact_pressed() and _cooldown <= 0.0:
		enter_vehicle(nearby)


func _zone_center(v: RigidBody3D) -> Vector3:
	var area := v.get("enter_area") as Area3D
	return area.global_position if area else v.global_position


func _enter_radius(v: RigidBody3D) -> float:
	var r = v.get("enter_distance")
	return 4.0 if r == null else float(r)


func _find_nearby() -> RigidBody3D:
	var best: RigidBody3D = null
	var best_d := INF
	for v in vehicles:
		if not is_instance_valid(v) or bool(v.get("is_active")):
			continue
		var area := v.get("enter_area") as Area3D
		var inside := false
		if area:
			area.monitoring = true
			area.collision_mask |= character.collision_layer
			inside = area.overlaps_body(character)
		var d := character.global_position.distance_to(_zone_center(v))
		if inside or d <= _enter_radius(v):
			if d < best_d:
				best_d = d
				best = v
	return best


func _update_debug() -> void:
	var lines: Array[String] = []
	if is_instance_valid(character):
		lines.append("Rob: %s  active=%s  pos=%s" % [character.name, str(character.get("is_active")), str(character.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
	else:
		lines.append("Rob: NOT FOUND")
	lines.append("cars registered: %d | driving: %s | can enter: %s" % [vehicles.size(), str(current.name) if current else "-", str(nearby.name) if nearby else "-"])
	for v in vehicles:
		if not is_instance_valid(v):
			continue
		var d := -1.0
		if is_instance_valid(character):
			d = character.global_position.distance_to(_zone_center(v))
		lines.append("  %s: dist=%.1f / need <= %.1f | active=%s" % [v.name, d, _enter_radius(v), str(v.get("is_active"))])
	_dbg.text = "\n".join(lines)


# ---------------------------------------------------------------- enter / exit

func enter_vehicle(v: RigidBody3D = null) -> void:
	if not is_instance_valid(character):
		return
	if v == null:
		v = nearby
	if not is_instance_valid(v):
		return
	if is_instance_valid(current):
		return
	if not _char_active():
		return
	if bool(v.get("is_active")):
		return

	current = v
	nearby = null
	_cooldown = press_cooldown
	register_vehicle(v)

	character.velocity = Vector3.ZERO
	character.set("is_active", false)
	character.visible = false

	var collision := _collision_of_character()
	if collision:
		collision.set_deferred("disabled", true)

	var character_camera := _character_camera()
	if character_camera:
		character_camera.current = false

	v.set("is_active", true)
	v.sleeping = false

	var car_camera := v.get("drive_camera") as Camera3D
	if car_camera:
		car_camera.current = true


func exit_vehicle() -> void:
	if not is_instance_valid(character) or not is_instance_valid(current):
		current = null
		return

	var v := current
	_cooldown = press_cooldown
	v.set("is_active", false)

	var car_camera := v.get("drive_camera") as Camera3D
	if car_camera:
		car_camera.current = false

	var exit_point := v.get("exit_point") as Node3D
	if exit_point:
		character.global_position = exit_point.global_position
	else:
		character.global_position = v.global_position + v.global_transform.basis.x * 2.0

	character.global_rotation.y = v.global_rotation.y
	character.velocity = Vector3.ZERO
	character.visible = true

	var collision := _collision_of_character()
	if collision:
		collision.set_deferred("disabled", false)

	character.set("is_active", true)

	var character_camera := _character_camera()
	if character_camera:
		character_camera.current = true

	current = null
