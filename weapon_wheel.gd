extends Control

@export var viewmodel: Node3D                # ViewmodelPivot
@export var slot_names: PackedStringArray = ["Unarmed", "Pistol", "Bat"]
@export var open_key: Key = KEY_G

@export_group("Font")
@export var font: Font                       # drag your handwriting .ttf here
@export var label_size := 32
@export var label_tilt_deg: PackedFloat32Array = [-4.0, 3.0, -2.0]

@export_group("Style")
@export_enum("Marker Green", "Ink Red", "Chalk White", "Neon Blue", "Custom") var preset := 0
@export var wobble := 2.5                    # hand-drawn edge shake in px (0 = clean)
@export var boil_fps := 8.0                  # how often the shake changes (0 = still)
@export var stroke := 3.0

@export_group("Glow")
@export var glow := true
@export var glow_strength := 1.0             # overall brightness of the glow
@export var glow_layers := 7                 # more = smoother, softer
@export var glow_spread := 5.0               # px added per layer (bigger = wider glow)
@export var glow_pulse := 0.25               # breathing amount (0 = steady)
@export var glow_pulse_speed := 3.0
@export var equipped_glow := 0.5             # glow on the equipped slice (0 = off)
@export var text_glow := true

@export_group("Custom Colors (preset = Custom)")
@export var custom_bg := Color(0.05, 0.05, 0.08, 0.8)
@export var custom_accent := Color(0.9, 0.5, 0.2)
@export var custom_text := Color(1.0, 0.85, 0.7)
@export var custom_hover_text := Color(0.1, 0.05, 0.02)
@export var custom_equipped := Color(1.0, 0.92, 0.35)

@export_group("Shape")
@export var inner_radius := 75.0
@export var outer_radius := 175.0
@export var gap_deg := 5.0
@export var pop := 14.0
@export var dim := 0.45
@export var fade_speed := 16.0

@export_group("Control")
@export var mouse_sens := 1.0
@export var deadzone := 35.0

var _open := false
var _alpha := 0.0
var _cursor := Vector2.ZERO
var _hover := -1
var _glow: Array[float] = [0.0, 0.0, 0.0]
var _seed := 0.0
var _boil_t := 0.0
var _time := 0.0

var _bg := Color.BLACK
var _accent := Color.WHITE
var _text := Color.WHITE
var _htext := Color.BLACK
var _eq := Color.YELLOW


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_setup_palette()
	if viewmodel == null:
		push_warning("WeaponWheel: assign the 'viewmodel' export (ViewmodelPivot).")


func _setup_palette() -> void:
	match preset:
		0:  # Marker Green
			_bg = Color(0.04, 0.08, 0.05, 0.78)
			_accent = Color(0.25, 0.78, 0.38)
			_text = Color(0.62, 0.95, 0.68)
			_htext = Color(0.03, 0.09, 0.04)
			_eq = Color(1.0, 0.92, 0.35)
		1:  # Ink Red
			_bg = Color(0.09, 0.04, 0.04, 0.8)
			_accent = Color(0.9, 0.2, 0.2)
			_text = Color(1.0, 0.75, 0.7)
			_htext = Color(0.1, 0.02, 0.02)
			_eq = Color(1.0, 0.85, 0.3)
		2:  # Chalk White
			_bg = Color(0.07, 0.07, 0.08, 0.8)
			_accent = Color(0.92, 0.92, 0.9)
			_text = Color(0.95, 0.95, 0.92)
			_htext = Color(0.05, 0.05, 0.06)
			_eq = Color(0.5, 0.85, 1.0)
		3:  # Neon Blue
			_bg = Color(0.03, 0.05, 0.1, 0.8)
			_accent = Color(0.2, 0.65, 1.0)
			_text = Color(0.7, 0.9, 1.0)
			_htext = Color(0.02, 0.05, 0.1)
			_eq = Color(1.0, 0.35, 0.75)
		_:  # Custom
			_bg = custom_bg
			_accent = custom_accent
			_text = custom_text
			_htext = custom_hover_text
			_eq = custom_equipped


func _input(event: InputEvent) -> void:
	if viewmodel == null:
		return

	if event is InputEventKey and event.physical_keycode == open_key \
			and event.pressed and not event.echo:
		if not _open and viewmodel.player.is_active \
				and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_open = true
			_cursor = Vector2.ZERO
			_hover = -1

	elif _open and event is InputEventMouseMotion:
		_cursor += event.relative * mouse_sens
		if _cursor.length() > outer_radius:
			_cursor = _cursor.normalized() * outer_radius
		get_viewport().set_input_as_handled()


func _close() -> void:
	_open = false
	if _hover != -1:
		viewmodel.equip(_hover)


func _process(delta: float) -> void:
	if viewmodel == null:
		return

	if _open and (not Input.is_physical_key_pressed(open_key) or not viewmodel.player.is_active):
		_close()

	if _open:
		if _cursor.length() < deadzone:
			_hover = -1
		else:
			var a := fposmod(atan2(_cursor.x, -_cursor.y), TAU)
			_hover = int(fposmod(a + TAU / 6.0, TAU) / (TAU / 3.0)) % 3

	var f := 1.0 - exp(-fade_speed * delta)
	_alpha = lerpf(_alpha, 1.0 if _open else 0.0, f)
	for i in 3:
		_glow[i] = lerpf(_glow[i], 1.0 if (_open and i == _hover) else 0.0, f)

	_time += delta
	if boil_fps > 0.0:
		_boil_t += delta
		if _boil_t >= 1.0 / boil_fps:
			_boil_t = 0.0
			_seed = randf() * 100.0

	visible = _alpha > 0.01
	if visible:
		queue_redraw()


func _pt(center: Vector2, t: float, r: float) -> Vector2:
	return center + Vector2(sin(t), -cos(t)) * r


func _slice(center: Vector2, i: int, r_in: float, r_out: float) -> PackedVector2Array:
	var ca := float(i) * TAU / 3.0
	var half := TAU / 6.0 - deg_to_rad(gap_deg) * 0.5
	var pts := PackedVector2Array()
	var steps := 24
	for s in steps + 1:
		pts.append(_pt(center, ca - half + (2.0 * half) * float(s) / float(steps), r_out))
	for s in steps + 1:
		pts.append(_pt(center, ca + half - (2.0 * half) * float(s) / float(steps), r_in))
	return pts


func _wobbled(pts: PackedVector2Array, seed_add: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in pts.size():
		var sd := _seed + seed_add + float(k)
		out.append(pts[k] + Vector2(sin(sd * 12.9898), cos(sd * 78.233)) * wobble)
	return out


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var c := pts.duplicate()
	c.append(pts[0])
	return c


func _text_at(fnt: Font, at: Vector2, txt: String, px: int, col: Color, tilt_deg: float) -> void:
	draw_set_transform(at, deg_to_rad(tilt_deg), Vector2.ONE)
	draw_string(fnt, Vector2(-80, px * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, 160, px, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _underline(fnt: Font, at: Vector2, txt: String, px: int, col: Color, tilt_deg: float) -> void:
	var w := fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * 0.5 + 6.0
	var line := PackedVector2Array()
	var steps := 14
	for s in steps + 1:
		var x := lerpf(-w, w, float(s) / float(steps))
		line.append(Vector2(x, px * 0.62 + sin(x * 0.12 + _seed) * 2.0))
	draw_set_transform(at, deg_to_rad(tilt_deg), Vector2.ONE)
	draw_polyline(line, col, 5.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Layered halo around a slice: stacked soft fills + fading outlines
func _halo(center: Vector2, i: int, r_out: float, col: Color, strength: float) -> void:
	if strength <= 0.01:
		return
	var n := maxi(glow_layers, 1)
	for L in range(n, 0, -1):
		var t := float(L) / float(n)                 # 1 = outermost layer
		var grow := float(L) * glow_spread
		var pts := _slice(center, i, maxf(inner_radius - grow * 0.6, 4.0), r_out + grow)
		var c := col
		c.a = strength * (1.0 - t) * 0.16 + strength * 0.02
		draw_colored_polygon(pts, c)
		var lc := col
		lc.a = strength * (1.0 - t) * 0.35
		draw_polyline(_closed(pts), lc, 2.0 + grow * 0.25, true)


func _draw() -> void:
	var a := _alpha
	var center := size / 2.0
	var fnt: Font = font if font != null else ThemeDB.fallback_font
	var pulse := 1.0 + sin(_time * glow_pulse_speed) * glow_pulse

	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, dim * a))

	var equipped := int(viewmodel.state)
	for i in 3:
		var g: float = _glow[i]
		var r_out := outer_radius + pop * g
		var base := _slice(center, i, inner_radius, r_out)

		# Glow: strong on hover, softer on the equipped slice
		if glow:
			if g > 0.01:
				_halo(center, i, r_out, _accent, glow_strength * g * a * pulse)
			if i == equipped and equipped_glow > 0.0:
				_halo(center, i, r_out, _eq, glow_strength * equipped_glow * a * pulse)

		# Fill: dark when idle, marker color when hovered
		var fill := _bg.lerp(_accent, g)
		fill.a *= a
		var w1 := _wobbled(base, 0.0)
		draw_colored_polygon(w1, fill)

		# Marker outline, drawn twice with a different shake
		var oc := _accent
		oc.a = (0.55 + 0.45 * g) * a
		draw_polyline(_closed(w1), oc, stroke + g * 2.0, true)
		var oc2 := oc
		oc2.a *= 0.6
		draw_polyline(_closed(_wobbled(base, 37.7)), oc2, stroke * 0.55, true)

		# Equipped: bold bright outline
		if i == equipped:
			var ec := _eq
			ec.a *= a
			draw_polyline(_closed(_wobbled(base, 71.3)), ec, stroke + 1.5, true)

		# Label (with glow copies behind it when hovered)
		var ca := float(i) * TAU / 3.0
		var mid := _pt(center, ca, (inner_radius + outer_radius) * 0.5)
		var tilt := label_tilt_deg[i] if i < label_tilt_deg.size() else 0.0
		var px := label_size + int(g * 4.0)
		if glow and text_glow and g > 0.01:
			var tg := _accent.lerp(Color.WHITE, 0.5)
			tg.a = 0.35 * g * a * glow_strength
			for off in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3),
					Vector2(-2, -2), Vector2(2, 2), Vector2(-2, 2), Vector2(2, -2)]:
				_text_at(fnt, mid + off, slot_names[i], px, tg, tilt)
		var tc := _text.lerp(_htext, g)
		tc.a *= a
		_text_at(fnt, mid, slot_names[i], px, tc, tilt)
		if i == equipped:
			var uc := _eq
			uc.a *= a
			_underline(fnt, mid, slot_names[i], px, uc, tilt)

	# Center ring with the current name
	var ring := PackedVector2Array()
	for k in 40:
		ring.append(_pt(center, TAU * float(k) / 40.0, inner_radius - 14.0))
	var wr := _wobbled(ring, 13.0)
	var rf := _bg
	rf.a *= a
	draw_colored_polygon(wr, rf)
	var rc := _accent
	rc.a = 0.7 * a
	draw_polyline(_closed(wr), rc, stroke * 0.8, true)

	var name_now := slot_names[_hover] if _hover != -1 else slot_names[equipped]
	var cc := _text
	cc.a *= a
	_text_at(fnt, center, name_now, label_size - 8, cc, 0.0)

	# Cursor with a soft glow
	var dc := _accent
	dc.a = a
	if glow:
		for r in [16.0, 12.0, 9.0]:
			draw_circle(center + _cursor, r, Color(dc.r, dc.g, dc.b, 0.12 * a * glow_strength))
	draw_circle(center + _cursor, 6.0, dc)
	draw_arc(center + _cursor, 10.0, 0.0, TAU, 20, Color(dc.r, dc.g, dc.b, 0.5 * a), 2.0, true)
