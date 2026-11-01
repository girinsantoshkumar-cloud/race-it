
extends Node

var character: CharacterBody3D = null
var vehicle: RigidBody3D = null

@export var character_collision_path: NodePath = ^"CollisionShape3D"
@export var character_camera_path: NodePath = ^"CameraPivot/car_cam"
@export var vehicle_camera_path: NodePath = ^"SpringArm3D/car_cam"
@export var vehicle_exit_path: NodePath = ^"Exit_point"


func enter_vehicle() -> void:
	if not is_instance_valid(character):
		push_warning("VehicleManager: Character is missing.")
		return

	if not is_instance_valid(vehicle):
		push_warning("VehicleManager: Vehicle is missing.")
		return

	if not bool(character.get("is_active")):
		return

	if bool(vehicle.get("is_active")):
		return

	# Stop and hide the character.
	character.velocity = Vector3.ZERO
	character.set("is_active", false)
	character.visible = false

	var collision := character.get_node_or_null(
		character_collision_path
	) as CollisionShape3D

	if collision:
		collision.set_deferred("disabled", true)

	# Switch cameras.
	var character_camera := character.get_node_or_null(
		character_camera_path
	) as Camera3D

	if character_camera:
		character_camera.current = false

	vehicle.set("is_active", true)
	vehicle.sleeping = false

	var car_camera := vehicle.get_node_or_null(
		vehicle_camera_path
	) as Camera3D

	if car_camera:
		car_camera.current = true


func exit_vehicle() -> void:
	if not is_instance_valid(character):
		return

	if not is_instance_valid(vehicle):
		return

	if not bool(vehicle.get("is_active")):
		return

	vehicle.set("is_active", false)

	var car_camera := vehicle.get_node_or_null(
		vehicle_camera_path
	) as Camera3D

	if car_camera:
		car_camera.current = false

	# Move the character to the exit point.
	var exit_point := vehicle.get_node_or_null(
		vehicle_exit_path
	) as Node3D

	if exit_point:
		character.global_position = exit_point.global_position
	else:
		character.global_position = (
			vehicle.global_position
			+ vehicle.global_transform.basis.x * 2.0
		)

	character.global_rotation.y = vehicle.global_rotation.y
	character.velocity = Vector3.ZERO
	character.visible = true

	var collision := character.get_node_or_null(
		character_collision_path
	) as CollisionShape3D

	if collision:
		collision.set_deferred("disabled", false)

	character.set("is_active", true)

	var character_camera := character.get_node_or_null(
		character_camera_path
	) as Camera3D

	if character_camera:
		character_camera.current = true
