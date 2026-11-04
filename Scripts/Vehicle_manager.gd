extends Node

var character: CharacterBody3D = null
var vehicles: Array[RigidBody3D] = []
var current: RigidBody3D = null                  # car Rob is driving
var nearby: RigidBody3D = null                   # car whose zone Rob stands in

# old name: reading gives the driven car, assigning registers a car
var vehicle: RigidBody3D:
	get:
		return current
	set(v):
		register_vehicle(v)

@export var interact_action := "interact"
@export var show_exit_prompt := true
@export var press_cooldown := 0.3                # stops one E press from entering AND exiting
@export var character_collision_path: NodePath = ^"CollisionShape3D"
@export var character_camera_path: NodePath = ^"CameraPivot/car_cam"   # fallback if Rob has no 'camera' export

var _label: Label
var _cooldown := 0.0


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_left = -250.0
	_label.offset_right = 250.0
	_label.offset_top = -150.0
	_label.offset_bottom = -100.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	_label.visible = false
	layer.add_child(_label)


func register_vehicle(v: RigidBody3D) -> void:
	if is_instance_valid(v) and not vehicles.has(v):
		vehicles.append(v)


func unregister_vehicle(v: RigidBody3D) -> void:
	vehicles.erase(v)
	if current == v:
		current = null
	if nearby == v:
		nearby = null


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)

	if not is_instance_valid(character):
		_label.visible = false
		return

	# driving: exit prompt, interact exits
	if is_instance_valid(current):
		nearby = null
		_label.visible = show_exit_prompt
		_label.text = "[%s] Exit" % _key_text()
		if _cooldown <= 0.0 and Input.is_action_just_pressed(interact_action):
			exit_vehicle()
		return

	# on foot: find the car whose zone Rob is standing in
	nearby = _find_nearby()
	if nearby == null or not bool(character.get("is_active")):
		_label.visible = false
		return

	var verb = nearby.get("prompt_text")
	_label.text = "[%s] %s" % [_key_text(), verb if verb else "Drive"]
	_label.visible = true
	if _cooldown <= 0.0 and Input.is_action_just_pressed(interact_action):
		enter_vehicle(nearby)


func _find_nearby() -> RigidBody3D:
	var best: RigidBody3D = null
	var best_d := INF
	for v in vehicles:
		if not is_instance_valid(v) or bool(v.get("is_active")):
			continue
		var area := v.get("enter_area") as Area3D
		if area == null:
			continue
		area.collision_mask |= character.collision_layer   # zone always detects Rob
		if not area.overlaps_body(character):
			continue
		var d := character.global_position.distance_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	return best


func _key_text() -> String:
	for ev in InputMap.action_get_events(interact_action):
		if ev is InputEventKey:
			var code: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
			return OS.get_keycode_string(code)
	return "E"


func _character_camera() -> Camera3D:
	var cam := character.get("camera") as Camera3D
	if cam == null:
		cam = character.get_node_or_null(character_camera_path) as Camera3D
	return cam


func enter_vehicle(v: RigidBody3D = null) -> void:
	if not is_instance_valid(character):
		push_warning("VehicleManager: Character is missing.")
		return
	if v == null:
		v = nearby
	if not is_instance_valid(v):
		push_warning("VehicleManager: Vehicle is missing.")
		return
	if is_instance_valid(current):
		return
	if not bool(character.get("is_active")):
		return
	if bool(v.get("is_active")):
		return

	current = v
	nearby = null
	_cooldown = press_cooldown
	register_vehicle(v)

	# Stop and hide the character.
	character.velocity = Vector3.ZERO
	character.set("is_active", false)
	character.visible = false

	var collision := character.get_node_or_null(character_collision_path) as CollisionShape3D
	if collision:
		collision.set_deferred("disabled", true)

	# Switch cameras.
	var character_camera := _character_camera()
	if character_camera:
		character_camera.current = false

	v.set("is_active", true)
	v.sleeping = false

	var car_camera := v.get("drive_camera") as Camera3D
	if car_camera:
		car_camera.current = true
	else:
		push_warning("VehicleManager: %s has no drive camera." % v.name)


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

	var collision := character.get_node_or_null(character_collision_path) as CollisionShape3D
	if collision:
		collision.set_deferred("disabled", false)

	character.set("is_active", true)

	var character_camera := _character_camera()
	if character_camera:
		character_camera.current = true

	current = null
