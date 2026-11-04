extends Area3D

@export var veh:=VehicleBody3D
@export var exit_point:=Marker3D
@export var rob:=CharacterBody3D
@onready var arv:Area3D=$'.'
var in_veh=true
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if rob.global_position == exit_point.global_position:
		in_veh=false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
		
		
