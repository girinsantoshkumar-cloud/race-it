extends Node3D
## Non-destructive tree sway for Godot 4.x.
## Attach to the tree's root Node3D. It never edits meshes or materials;
## it only rotates this node (and optionally foliage children) by tiny angles
## on top of their original transforms.
##
## IMPORTANT: the node's origin should sit at the base of the trunk, so the
## tree stays planted while it leans. If your origin is elsewhere, put the tree
## inside a new Node3D placed at the trunk base and attach this script to that.

@export_group("Main sway")
## Direction the wind blows, in degrees around the Y axis.
@export_range(0.0, 360.0) var wind_direction_deg := 0.0
## Maximum lean from the wind in degrees. Keep small (1-3) for natural motion.
@export_range(0.0, 10.0, 0.1) var sway_angle_deg := 1.5
## Speed of the sway cycle.
@export_range(0.1, 5.0, 0.05) var sway_speed := 0.8
## Constant lean in the wind direction, in degrees.
@export_range(0.0, 5.0, 0.1) var constant_lean_deg := 0.5
## How much the wind strength varies over time (0 = steady).
@export_range(0.0, 1.0, 0.05) var gust_strength := 0.5
## Sideways motion as a fraction of the main sway.
@export_range(0.0, 1.0, 0.05) var side_sway := 0.35

@export_group("Foliage flutter (optional)")
## Adds a tiny extra rotation to child nodes whose names contain a keyword below.
@export var flutter_enabled := true
@export_range(0.0, 5.0, 0.1) var flutter_angle_deg := 0.8
@export_range(0.1, 10.0, 0.1) var flutter_speed := 2.5
@export var foliage_keywords: PackedStringArray = ["leaf", "leaves", "foliage", "canopy", "crown"]

@export_group("Misc")
## Gives each tree a different timing so a forest doesn't sway in sync.
@export var randomize_phase := true

var _base_basis: Basis
var _phase := 0.0
var _time := 0.0
var _foliage: Array[Node3D] = []
var _foliage_base: Array[Basis] = []


func _ready() -> void:
	_base_basis = basis
	if randomize_phase:
		_phase = randf() * 100.0
	if flutter_enabled:
		_collect_foliage(self)


func _collect_foliage(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D:
			var lname := String(child.name).to_lower()
			for key in foliage_keywords:
				if lname.contains(key.to_lower()):
					_foliage.append(child)
					_foliage_base.append(child.basis)
					break
		_collect_foliage(child)


func _process(delta: float) -> void:
	_time += delta
	var t := _time * sway_speed + _phase

	# Smooth, non-repeating motion from a few sines with unrelated frequencies.
	var main := sin(t) * 0.6 + sin(t * 1.7 + 1.3) * 0.3 + sin(t * 2.9 + 4.1) * 0.1
	var side := sin(t * 1.3 + 2.0) * 0.6 + sin(t * 2.3 + 0.7) * 0.4

	# Slow gusts raise and lower the overall strength.
	var gust := 1.0 + gust_strength * 0.5 * sin(_time * 0.23 + _phase) \
			+ gust_strength * 0.25 * sin(_time * 0.61 + _phase * 0.5)

	var yaw := deg_to_rad(wind_direction_deg)
	var wind_dir := Vector3(sin(yaw), 0.0, cos(yaw))
	var lean_axis := Vector3.UP.cross(wind_dir).normalized() # tilts the trunk along the wind
	var side_axis := wind_dir                                # tilts the trunk sideways

	var lean_angle := deg_to_rad(constant_lean_deg * gust + sway_angle_deg * main * gust)
	var side_angle := deg_to_rad(sway_angle_deg * side_sway * side * gust)

	var sway_basis := Basis(lean_axis, lean_angle) * Basis(side_axis, side_angle)
	basis = sway_basis * _base_basis

	if flutter_enabled:
		_update_flutter(gust)


func _update_flutter(gust: float) -> void:
	var amp := deg_to_rad(flutter_angle_deg) * gust
	for i in _foliage.size():
		var node := _foliage[i]
		if not is_instance_valid(node):
			continue
		var ft := _time * flutter_speed + _phase + float(i) * 1.37
		var rx := sin(ft) * amp
		var rz := sin(ft * 1.21 + 1.9) * amp
		node.basis = Basis.from_euler(Vector3(rx, 0.0, rz)) * _foliage_base[i]
