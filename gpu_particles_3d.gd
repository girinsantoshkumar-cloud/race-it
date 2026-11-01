extends GPUParticles3D
## Attach this to YOUR existing GPUParticles3D node.
## It only sets up the emission and motion (ParticleProcessMaterial) so the
## particles fall like leaves. Your draw pass / mesh / material stay untouched.
## Put the node inside the canopy and run the scene.

@export_group("Emission")
@export var leaves_per_second := 4.0
## Seconds each leaf lives. Must be long enough to reach the ground.
@export var leaf_lifetime := 12.0
@export var emit_extents := Vector3(2.5, 0.5, 2.5)
@export var leaf_scale := Vector2(0.8, 1.3)

@export_group("Motion")
## Rough falling speed in m/s (gravity / damping).
@export_range(0.2, 4.0, 0.05) var fall_speed := 1.0
## Swirl and flutter strength.
@export_range(0.0, 4.0, 0.05) var flutter := 1.0
@export_range(0.0, 360.0) var wind_direction_deg := 0.0
@export_range(0.0, 5.0, 0.1) var wind_speed := 0.6
@export_range(0.0, 360.0) var spin_deg_per_sec := 90.0

@export_group("Ground")
## Make leaves vanish when they touch a GPUParticlesCollision node (add a
## GPUParticlesCollisionHeightField3D covering your terrain).
@export var hide_on_ground_contact := false


func _ready() -> void:
	var mat := ParticleProcessMaterial.new()

	# Spawn area
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = emit_extents

	# Gentle initial push, mostly downward
	mat.direction = Vector3.DOWN
	mat.spread = 20.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.4

	# Gravity + damping gives a terminal velocity of about gravity / damping,
	# so leaves float down at a steady slow speed instead of accelerating.
	var damping := 2.0
	var yaw := deg_to_rad(wind_direction_deg)
	var wind := Vector3(sin(yaw), 0.0, cos(yaw)) * wind_speed * damping
	mat.gravity = Vector3(wind.x, -fall_speed * damping, wind.z)
	mat.damping_min = damping * 0.8
	mat.damping_max = damping * 1.2

	# Turbulence = the side-to-side drifting and fluttering
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 1.5 * flutter
	mat.turbulence_noise_scale = 2.0
	mat.turbulence_noise_speed = Vector3(0.3, 0.1, 0.3)
	mat.turbulence_influence_min = 0.05
	mat.turbulence_influence_max = 0.15

	# Spinning
	mat.angle_min = 0.0
	mat.angle_max = 360.0
	mat.angular_velocity_min = -spin_deg_per_sec
	mat.angular_velocity_max = spin_deg_per_sec
	mat.particle_flag_rotate_y = true

	# Size variation
	mat.scale_min = leaf_scale.x
	mat.scale_max = leaf_scale.y

	if hide_on_ground_contact:
		mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT

	process_material = mat

	# World-space so leaves don't swing with the swaying tree
	local_coords = false
	lifetime = leaf_lifetime
	amount = maxi(int(ceil(leaves_per_second * leaf_lifetime)), 1)
	preprocess = leaf_lifetime
	explosiveness = 0.0
	randomness = 1.0
	one_shot = false
	visibility_aabb = AABB(Vector3(-15, -40, -15), Vector3(30, 50, 30))
	emitting = true
