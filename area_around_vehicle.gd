extends Area3D

var rob_in_range:=false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
func _on_body_entered(body:Node3D)->void:
	if body==VehicleManager.character:
		rob_in_range=true
	
func _on_body_exited(body:Node3D)->void:
	if body==VehicleManager.character:
		rob_in_range=false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if rob_in_range and not VehicleManager.vehicle.is_active and Input.is_action_just_pressed("interact"):
		VehicleManager.enter_vehicle()
	
		
