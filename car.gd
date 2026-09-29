extends VehicleBody3D

var steer=0.9
var power=400
func _physics_process(delta: float) -> void:
	steering=move_toward(steering,Input.get_axis("right","left")*steer,delta*10)
	engine_force=Input.get_axis("backward","forward")*power
