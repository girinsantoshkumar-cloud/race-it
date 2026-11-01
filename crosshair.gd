extends Control

@export var player: CharacterBody3D
@export var viewmodel: Node3D                # ViewmodelPivot
@export var only_with_gun := true            # false = always show (outside vehicles)
@export var fade_speed := 14.0

@export_group("Look")
@export var color := Color.WHITE
@export var outline_color := Color(0, 0, 0, 0.8)
@export var thickness := 2.0
@export var length := 8.0
@export var gap := 5.0
@export var center_dot := true
@export_group("Spread")
@export var move_spread := 8.0
@export var spread_lerp := 10.0

var _spread := 0.0
var _alpha := 0.0
var _show := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if viewmodel:
		_show = (not only_with_gun) or int(viewmodel.state) == 1
		_alpha = 1.0 if _show else 0.0
		viewmodel.state_changed.connect(_on_state_changed)
	else:
		push_warning("Crosshair: assign the 'viewmodel' export (ViewmodelPivot).")


func _on_state_changed(s: int) -> void:
	_show = (not only_with_gun) or s == 1     # 1 = GUN


func _process(delta: float) -> void:
	if player == null:
		return

	var goal := 1.0 if (_show and player.is_active) else 0.0
	_alpha = lerpf(_alpha, goal, 1.0 - exp(-fade_speed * delta))
	visible = _alpha > 0.01
	if not visible:
		return

	var h_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var target := clampf(h_speed / player.sprint_speed, 0.0, 1.0) * move_spread
	_spread = lerpf(_spread, target, 1.0 - exp(-spread_lerp * delta))
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var g := gap + _spread
	var dirs := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]

	for pass_i in 2:
		var col := outline_color if pass_i == 0 else color
		col.a *= _alpha
		var w := thickness + (2.0 if pass_i == 0 else 0.0)
		for d in dirs:
			draw_line(c + d * (g - (1.0 if pass_i == 0 else 0.0)),
					c + d * (g + length + (1.0 if pass_i == 0 else 0.0)), col, w)
		if center_dot:
			draw_circle(c, (thickness + (2.0 if pass_i == 0 else 0.0)) * 0.5, col)
