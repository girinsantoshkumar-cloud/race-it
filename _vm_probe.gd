extends SceneTree

var frames := 0
var scene_inst: Node = null
var cars: Array[VehicleBody3D] = []
var porche: VehicleBody3D = null

func _initialize() -> void:
	pass

func _process(_delta: float) -> bool:
	frames += 1
	if scene_inst == null:
		var packed: PackedScene = load("res://Start.tscn")
		scene_inst = packed.instantiate()
		root.add_child(scene_inst)
		for n in scene_inst.get_children():
			if n is VehicleBody3D:
				cars.append(n as VehicleBody3D)
	if frames == 30:
		for c in cars:
			c.set("is_active", true)
			Input.action_press("forward")
			Input.action_release("backward")
	if frames == 60:
		for c in cars:
			print("PROBE6 car=", c.name, " vel=", c.linear_velocity, " pos=", c.global_position, " engine_force=", c.engine_force, " brake=", c.brake, " sleeping=", c.sleeping, " is_active=", c.get("is_active"))
	if frames == 150:
		for c in cars:
			print("PROBE6 car=", c.name, " FINAL vel=", c.linear_velocity, " pos=", c.global_position, " engine_force=", c.engine_force, " brake=", c.brake)
		quit()
	return false
