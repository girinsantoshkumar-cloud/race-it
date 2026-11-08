@tool
class_name ScatterCategory
extends Resource
## One scattering rule-set (e.g. "trees", "rocks", "streetlights").
## Create as a .tres (New Resource -> ScatterCategory) and add to the manager's `categories` array.
## Categories run in array order: put trees BEFORE branches/bushes that use `near_category`.

enum Mode { AREA, ALONG_ROADS }
enum Render { MULTIMESH, NODES }

@export var category_name := "trees"
@export var enabled := true

@export_group("Assets")
## Drag your imported .glb scenes here (each = one variation).
@export var scenes: Array[PackedScene] = []
## Optional per-variant weights (same order as scenes). Empty = equal.
@export var weights: PackedFloat32Array = []
## MULTIMESH = fast, no per-instance nodes. NODES = real scene instances (use only for few items).
@export var render: Render = Render.MULTIMESH

@export_group("Amount & Distribution")
@export var mode: Mode = Mode.AREA
@export var count := 1000
## Max placement attempts = count * this.
@export var attempts_multiplier := 6.0
@export_range(0.0, 1.0) var cluster_fraction := 0.6
@export var cluster_count := 40
@export var cluster_radius := 25.0
## Noise mask (forest patches / clearings).
@export var use_noise := false
@export var noise_frequency := 0.012
@export_range(0.0, 1.0) var noise_threshold := 0.45
@export_range(0.01, 0.5) var noise_softness := 0.12

@export_group("Near other things (branches near trees, bushes near rocks/buildings)")
## Name of an earlier category whose placements act as anchors. Empty = off.
@export var near_category := ""
## Node group whose Node3D positions act as anchors (e.g. "scatter_building"). Empty = off.
@export var near_group: StringName = &""
@export_range(0.0, 1.0) var near_fraction := 0.7
@export var near_min_distance := 0.5
@export var near_max_distance := 6.0

@export_group("Terrain filters")
@export_range(0.0, 90.0) var max_slope_deg := 35.0
@export var min_height := -10000.0
@export var max_height := 10000.0

@export_group("Roads / exclusion")
## Hard no-spawn distance from road EDGE (AREA mode).
@export var road_clear_distance := 6.0
## Beyond clear distance density ramps 0->1 over this many metres (forest-to-town transition).
@export var road_fade_distance := 30.0
@export_range(0.0, 1.0) var min_density_near_road := 0.0
## Extra margin around ScatterExclusion shapes.
@export var exclusion_margin := 0.0

@export_group("Spacing")
## Approx. ground radius at scale 1.
@export var footprint_radius := 1.0
@export var spacing_gap := 0.5
## Reject if overlapping other registered large props.
@export var avoid_large := true
## Register so later props avoid this one.
@export var register_as_large := true

@export_group("Transform")
@export var scale_min := 0.8
@export var scale_max := 1.3
@export_range(0.0, 0.5) var scale_xz_jitter := 0.08
@export var random_yaw := true
@export_range(0.0, 45.0) var tilt_max_deg := 0.0
@export_range(0.0, 1.0) var align_to_normal := 0.0
## Sink into ground (metres at scale 1).
@export var sink := 0.0

@export_group("Along roads (mode = ALONG_ROADS)")
@export var road_spacing := 25.0
@export_range(0.0, 1.0) var road_spacing_jitter := 0.3
## Distance from road edge to prop.
@export var road_side_offset := 1.5
@export var road_both_sides := true
@export_range(0.0, 1.0) var road_side_chance := 0.7
@export var group_min := 1
@export var group_max := 1
@export var group_radius := 1.5
@export var face_road := false
## Added to yaw when face_road (depends on your model's forward axis).
@export var yaw_offset_deg := 0.0

@export_group("Rendering / collision")
@export var cast_shadows := false
## 0 = unlimited.
@export var draw_distance := 200.0
@export var chunk_size := 64.0
## >0 adds one cylinder collider per instance (grouped per chunk). Use for trunks / poles / big rocks.
@export var collision_radius := 0.0
@export var collision_height := 3.0
@export_flags_3d_physics var collision_layer := 1
