extends VehicleBody3D
#input

@export_group("Wheels")
@export var front_left:VehicleWheel3D
@export var front_right:VehicleWheel3D
@export var back_right:VehicleWheel3D
@export var back_left:VehicleWheel3D

@export_group("Suspension")
@export var wheel_friction:float=10.5
@export var suspension_stiffness_value:float=0.0

@export_group("Recovery")
@export var flip_threshold:float=0.3
@export var flip_time_required:float=2.0
#active checker
var is_active:=false
##topple checker
var has_toppled=false
var flip_timer:float=0.0
var last_stable_transform:Transform3D
#steer, acceleration
const MAX_STEER=0.35
const ENGINE_FORCE=700
#ready_func
func _ready() -> void:
	#vehicle manager
	VehicleManager.vehicle=self
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

#physics process
func _physics_process(delta: float) -> void:
	##check topple
	_check_topple(delta)
	##if is_active is false dont inherit any actions from physics process
	if not is_active:
		return
	if Input.is_action_just_pressed("interact"):
		VehicleManager.exit_vehicle()
		return
	steering=move_toward(steering,Input.get_axis("right","left")*MAX_STEER,delta*2.5)
	engine_force=Input.get_axis("forward","backward")*ENGINE_FORCE
	if Input.is_action_pressed("hand_brake"):
		engine_force=0
		brake=7
	else:
		brake=0
	
func _check_topple(delta:float)->void:
	var up_dot=global_transform.basis.y.dot(Vector3.UP)
	if(up_dot<flip_threshold):
		has_toppled=true
		flip_timer+=delta
		if flip_timer>=flip_time_required:
			_reset_vehicle()
			flip_timer=0.0
	else:
		has_toppled=false
		flip_timer=0.0
		if linear_velocity.length()<=8.0:
			last_stable_transform=global_transform
			
func _reset_vehicle()->void:
	linear_velocity=Vector3.ZERO
	angular_velocity=Vector3.ZERO
	var reset_transforms=last_stable_transform
	reset_transforms.origin+=Vector3.UP*1.0
	var yaw=reset_transforms.basis.get_euler().y
	reset_transforms.basis=Basis(Vector3.UP,yaw)
	
	global_transform=reset_transforms
	has_toppled=false
	
	
	
	
			
			
	
