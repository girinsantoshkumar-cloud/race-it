@tool
extends EditorScript

const TERRAIN_NAME := "HTerrain"
const LAYER_INDEX := 0

func _run() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var terrain = root.find_child(TERRAIN_NAME, true, false)
	if terrain == null:
		push_error("FILL: HTerrain node not found, check TERRAIN_NAME")
		return
	var data = terrain.get_data()
	if data == null:
		push_error("FILL: terrain has no data")
		return
	while data.get_map_count(data.CHANNEL_DETAIL) <= LAYER_INDEX:
		data._edit_add_map(data.CHANNEL_DETAIL)
		print("FILL: added a detail map")
	var img: Image = data.get_image(data.CHANNEL_DETAIL, LAYER_INDEX)
	if img == null:
		push_error("FILL: could not get detail image")
		return
	img.fill(Color(1, 0, 0, 1))
	data.notify_region_change(Rect2i(0, 0, img.get_width(), img.get_height()), data.CHANNEL_DETAIL, LAYER_INDEX)
	print("FILL: detail map filled ", img.get_size())
