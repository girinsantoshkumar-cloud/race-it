class_name CarHealthBar
extends TextureProgressBar

@export var car_icon: Texture2D
@export var show_only_when_driving := true
@export var full_color := Color(0.3, 1.0, 0.3)
@export var mid_color := Color(1.0, 0.85, 0.2)
@export var low_color := Color(1.0, 0.2, 0.15)
@export var empty_tint := Color(0.15, 0.15, 0.15, 0.7)   # the "lost health" part of the icon
@export var smooth_speed := 8.0

var _car: Node = null
var _shown_value := 100.0


func _ready() -> void:
	if car_icon:
		texture_under = car_icon
		texture_progress = car_icon
	fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	nine_patch_stretch = true          # lets you resize the bar freely in the editor
	min_value = 0.0
	max_value = 100.0
	step = 0.1
	tint_under = empty_tint
	visible = false


func _process(delta: float) -> void:
	var car := _find_car()
	if car != _car:
		_car = car
		if _car:
			_shown_value = _percent(_car)
	if _car == null:
		visible = false
		return

	visible = true
	var target := _percent(_car)
	_shown_value = lerpf(_shown_value, target, clampf(smooth_speed * delta, 0.0, 1.0))
	value = _shown_value

	var f := _shown_value / 100.0
	if f < 0.5:
		tint_progress = low_color.lerp(mid_color, clampf(f * 2.0, 0.0, 1.0))
	else:
		tint_progress = mid_color.lerp(full_color, clampf((f - 0.5) * 2.0, 0.0, 1.0))


func _find_car() -> Node:
	for c in get_tree().get_nodes_in_group("car"):
		if not ("health" in c):
			continue
		if show_only_when_driving and not bool(c.get("is_active")):
			continue
		return c
	return null


func _percent(c: Node) -> float:
	var m: float = maxf(float(c.get("max_health")), 0.001)
	return clampf(float(c.get("health")) / m * 100.0, 0.0, 100.0)
