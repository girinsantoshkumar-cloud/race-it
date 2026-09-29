extends Node3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.get_axis("forward","backward"):
		$AnimationPlayer.play("mixamo_com")
