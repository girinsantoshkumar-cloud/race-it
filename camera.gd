extends Node3D

@export var target:Node3D
@export_category("Follows")
@export var follow_speed: float=6.0
@export var rotation_speed: float=5.0

@export_category("Camera")
@export var height:float=2.5
@export var distance:float=6.0
@export var look_height:float=1.2
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if target==null:
		target=get_parent()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if target==null:
		return 
	var target_position:=target.global_position
	var backward:=-target.global_transform.basis.z
	var desired_position:=target_position*backward*distance
	desired_position.y +=height
	global_position=global_position.lerp(desired_position,1.0-exp(-follow_speed*delta))
	var look_position:=target_position
	look_position.y+=look_height
	
	var desired_rotation:=global_transform.looking_at(
		look_position,
		Vector3.UP
	).basis.get_euler()
	
	global_rotation=Vector3(
		global_rotation.x,
		global_rotation.y,
		global_rotation.z
	)
	
