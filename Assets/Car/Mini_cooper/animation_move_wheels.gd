extends Node3D

@export var wheel_fl: Node3D
@export var wheel_fr: Node3D
@export var wheel_rl: Node3D
@export var wheel_rr: Node3D

@export var wheel_radius: float = 0.35  # set to your actual wheel radius in meters
@export var test_speed: float = 5.0     # for testing — replace with real speed later

func _process(delta):
	var rotation_amount = (test_speed / wheel_radius) * delta
	wheel_fl.rotate_z(rotation_amount)
	wheel_fr.rotate_z(rotation_amount)
	wheel_rl.rotate_z(rotation_amount)
	wheel_rr.rotate_z(rotation_amount)
