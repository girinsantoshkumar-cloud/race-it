extends Node

var character: CharacterBody3D
var vehicle: VehicleBody3D
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

#area3d -> Vehicle_manager ==>enter_vehicle
func enter_vehicle()->void:
	if not character or not vehicle:
		return
	character.is_active=false
	character.visible=false
	character.get_node("/root/Node3D/Rob/CollisionShape3D").disabled=true
	character.get_node("/root/Node3D/Rob/CameraPivot/car_cam").current=false
	
	vehicle.is_active=true
	vehicle.get_node("/root/Node3D/Player/CameraPivot/car_cam").current=true
	
	
func exit_vehicle():
	vehicle.is_active=false
	vehicle.get_node("/root/Node3D/Player/CameraPivot/car_cam").current=false
	character.global_position=vehicle.get_node("Exit_point").global_position
	character.rotation.y=vehicle.rotation.y
	
	character.visible=true
	character.get_node("/root/Node3D/Rob/CollisionShape3D").disabled=false
	character.is_active=true
	character.get_node("/root/Node3D/Rob/CameraPivot/car_cam").current=true
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
