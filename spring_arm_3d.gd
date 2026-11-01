extends SpringArm3D

@export var spring_distance:float=7.0
@export var smooth:float=3.0
@export var camera_height:float=5.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	spring_length=spring_distance


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	position.y=lerp(position.y,
					camera_height,
					smooth*delta)
