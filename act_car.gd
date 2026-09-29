extends VehicleBody3D

var steer=0.4
var power=100
var max_rpm=500
var max_torque=200


func _physics_process(delta: float) -> void:
	steering=move_toward(steering,Input.get_axis("right","left")*steer,delta*5)
	engine_force=Input.get_axis("backward","forward")*power
	#steering = lerp(steering,Input.get_axis("right","left")*0.4,5*delta)
	#var acc=Input.get_axis("backward","forward")
	#var rpm=$bl.get_rpm()
	#$bl.engine_force=acc*max_torque*(1-rpm/max_rpm)
	#rpm=$br.get_rpm()
	#$br.engine_force=acc*max_torque*(1-rpm/max_rpm)
	
	
