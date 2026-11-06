extends Area3D
@export_group("Dont float")
@export var player: VehicleBody3D
@export var rob: CharacterBody3D
var last_stable: Vector3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	
	# Check if the player or rob collides with this Area3D (water)
	if player and player.has_method("die") or rob and rob.has_method("die"):
		# Transfer to "land" logic here if needed
		# For now, trigger death when hitting water
		if player:
			player.die()
		if rob:
			rob.die()
		
		# Optional: Remove player from scene after death
		player.queue_free()
		rob.queue_free()

# Called when the area is touched by a body
func _area_entered(body: Node3D) -> void:
	if body == player or body == rob:
		print("Player hit water!")
		body.die()
		body.queue_free()
