extends VehicleBody3D

@export var acc:float=10.0
@export var max_steer:float=3.0
@export var steer_speed:float=2.0
 
@export_group("Wheels")
@export var front_left:VehicleWheel3D
@export var back_left:VehicleWheel3D
@export var front_right:VehicleWheel3D
@export var back_right:VehicleWheel3D

@export_group("Suspension")
