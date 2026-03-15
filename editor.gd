extends Node3D
# editor.gd - 支援完整自訂流程、載入、清除與刪除確認的編輯器

@onready var level = $Level
@onready var tool_label = $CanvasLayer/HUD/ToolLabel
@onready var ghost_player = $GhostPlayer
@onready var camera_pivot = $CameraPivot

# 彈窗們 (Popups)
@onready var prop_popup = $CanvasLayer/PropertyPopup
@onready var save_popup = $CanvasLayer/SavePopup
@onready var load_popup = $CanvasLayer/LoadPopup
@onready var del_popup = $CanvasLayer/DeletePopup
@onready var load_list = $CanvasLayer/LoadPopup/VBoxContainer/ScrollContainer/List
@onready var file_name_edit = $CanvasLayer/SavePopup/VBoxContainer/FileNameEdit
@onready var del_label = $CanvasLayer/DeletePopup/VBoxContainer/LevelName

@export var move_speed: float = 10.0

var current_editing_file_name: String = ""
var current_tool_idx: int = 0
enum EditMode { TILE, PLAYER_START }
var current_mode = EditMode.TILE

var editing_tile: Tile = null
var pending_delete_path: String = ""

var tools = [
	Tile.TileType.DEFAULT,
	Tile.TileType.GOAL,
	Tile.TileType.OBSTACLE,
	Tile.TileType.HOLE,
	Tile.TileType.COLOR_CHANGER
]

func _ready() -> void:
	GameState.current_mode = GameState.GameMode.EDITOR
	if not GameState.preview_level_data.is_empty():
		level.generate_from_data(GameState.preview_level_data)
		GameState.preview_level_data = {}
	else:
		level.generate_empty_grid()
		current_editing_file_name = ""
		
	_make_all_tiles_editable()
	_setup_popup_ui()
	_update_tool_ui()
	_update_ghost_pos()
	
	# 連接按鈕
	$CanvasLayer/HUD/BackButton.pressed.connect(_on_back_pressed)
	$CanvasLayer/HUD/SaveButton.pressed.connect(_on_save_pressed)
	$CanvasLayer/HUD/LoadButton.pressed.connect(_on_load_pressed)
	$CanvasLayer/HUD/PlayButton.pressed.connect(play_level)
	$CanvasLayer/HUD/ClearButton.pressed.connect(_on_clear_pressed)
	
	# 彈窗關閉按鈕
	$CanvasLayer/PropertyPopup/VBoxContainer/CloseButton.pressed.connect(func(): prop_popup.visible = false)
	$CanvasLayer/SavePopup/VBoxContainer/HBoxContainer/ConfirmSave.pressed.connect(_on_confirm_save)
	$CanvasLayer/SavePopup/VBoxContainer/HBoxContainer/CancelSave.pressed.connect(func(): save_popup.visible = false)
	$CanvasLayer/LoadPopup/VBoxContainer/CloseLoad.pressed.connect(func(): load_popup.visible = false)
	$CanvasLayer/DeletePopup/VBoxContainer/HBox/ConfirmDel.pressed.connect(_on_confirm_delete)
	$CanvasLayer/DeletePopup/VBoxContainer/HBox/CancelDel.pressed.connect(func(): del_popup.visible = false)

func _on_clear_pressed() -> void:
	AudioManager.play("ui_click")
	level.generate_empty_grid()
	current_editing_file_name = ""
	_make_all_tiles_editable()
	_update_ghost_pos()

func _on_back_pressed() -> void:
	GameState.is_preview_mode = false
	GameState.preview_level_data = {}
	get_tree().change_scene_to_file("res://menu.tscn")

func _process(delta: float) -> void:
	var any_popup = prop_popup.visible or save_popup.visible or load_popup.visible or del_popup.visible
	if not any_popup:
		_handle_camera_movement(delta)

func _handle_camera_movement(delta: float) -> void:
	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.z += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.z -= 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1
	if input_dir != Vector3.ZERO:
		var rot_y = camera_pivot.rotation.y
		var forward = Vector3.FORWARD.rotated(Vector3.UP, rot_y)
		var right = Vector3.RIGHT.rotated(Vector3.UP, rot_y)
		var move_vec = (forward * input_dir.z + right * input_dir.x).normalized()
		camera_pivot.global_position += move_vec * move_speed * delta

func _make_all_tiles_editable() -> void:
	for pos in level.tiles:
		var tile = level.tiles[pos]
		if not tile.clicked.is_connected(_on_tile_clicked): tile.clicked.connect(_on_tile_clicked)

func _setup_popup_ui() -> void:
	var color_container = $CanvasLayer/PropertyPopup/VBoxContainer/ColorButtons
	for color in level.possible_colors:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(60, 60)
		var style = StyleBoxFlat.new()
		style.bg_color = color
		btn.add_theme_stylebox_override("normal", style)
		btn.pressed.connect(func(): _on_popup_color_selected(color))
		color_container.add_child(btn)
	var value_container = $CanvasLayer/PropertyPopup/VBoxContainer/ValueSection/ValueButtons
	for i in range(1, 7):
		var btn = Button.new()
		btn.text = str(i)
		btn.custom_minimum_size = Vector2(50, 50)
		btn.pressed.connect(func(): _on_popup_value_selected(i))
		value_container.add_child(btn)

func _on_tile_clicked(tile: Tile) -> void:
	var any_popup = prop_popup.visible or save_popup.visible or load_popup.visible or del_popup.visible
	if any_popup: return
	
	if current_mode == EditMode.PLAYER_START:
		level.player_start_grid_pos = tile.grid_pos
		_update_ghost_pos()
		AudioManager.play("ui_click")
		return
	var tool_type = tools[current_tool_idx]
	if tile.type == tool_type and (tile.type == Tile.TileType.GOAL or tile.type == Tile.TileType.COLOR_CHANGER):
		_open_property_popup(tile)
	else:
		tile.type = tool_type
		if tile.type == Tile.TileType.GOAL:
			tile.target_value = 1
			tile.target_color = level.possible_colors[0]
		elif tile.type == Tile.TileType.COLOR_CHANGER:
			tile.target_color = level.possible_colors[0]
			tile.uses = -1
		tile._update_visuals()
		AudioManager.play("ui_click")

func _open_property_popup(tile: Tile) -> void:
	editing_tile = tile
	prop_popup.visible = true
	$CanvasLayer/PropertyPopup/VBoxContainer/ValueSection.visible = (tile.type == Tile.TileType.GOAL)
	AudioManager.play("ui_click")

func _on_popup_color_selected(color: Color) -> void:
	if editing_tile:
		editing_tile.target_color = color
		editing_tile._update_visuals()
		AudioManager.play("ui_click")

func _on_popup_value_selected(val: int) -> void:
	if editing_tile:
		editing_tile.target_value = val
		editing_tile._update_visuals()
		AudioManager.play("ui_click")

func _on_save_pressed() -> void:
	AudioManager.play("ui_click")
	file_name_edit.text = current_editing_file_name
	save_popup.visible = true

func _on_load_pressed() -> void:
	AudioManager.play("ui_click")
	_refresh_load_list()
	load_popup.visible = true

func _refresh_load_list() -> void:
	for child in load_list.get_children(): child.queue_free()
	
	var levels = []
	levels.append_array(_get_json_files("res://levels/"))
	var user_path = OS.get_user_data_dir() + "/levels/" if OS.get_name() == "Android" else "user://levels/"
	levels.append_array(_get_json_files(user_path))
	
	# 實作字母排序
	levels.sort_custom(func(a, b): return a.get_file().to_lower() < b.get_file().to_lower())
	
	for file_path in levels:
		var can_delete = not file_path.begins_with("res://") or (OS.get_name() != "Android")
		_add_single_level_to_list(file_path, can_delete)

func _add_single_level_to_list(file_path: String, can_delete: bool) -> void:
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 100)
	var btn = Button.new()
	btn.text = file_path.get_file().get_basename()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 32)
	btn.pressed.connect(func(): _load_level_to_editor(file_path))
	hbox.add_child(btn)
	if can_delete:
		var del = Button.new()
		del.text = " X "
		del.custom_minimum_size = Vector2(100, 0)
		del.add_theme_font_size_override("font_size", 32)
		del.add_theme_color_override("font_color", Color.RED)
		del.pressed.connect(func(): _on_delete_requested(file_path))
		hbox.add_child(del)
	load_list.add_child(hbox)

func _on_delete_requested(path: String) -> void:
	AudioManager.play("ui_click")
	pending_delete_path = path
	del_label.text = path.get_file().get_basename()
	del_popup.visible = true

func _on_confirm_delete() -> void:
	var path = pending_delete_path
	if OS.get_name() == "Android":
		path = path.replace("user://", OS.get_user_data_dir() + "/")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		AudioManager.play("error")
	del_popup.visible = false
	_refresh_load_list()

func _get_json_files(path: String) -> Array:
	var files = []
	if DirAccess.dir_exists_absolute(path):
		var dir = DirAccess.open(path)
		dir.list_dir_begin()
		var fn = dir.get_next()
		while fn != "":
			if not dir.current_is_dir() and fn.ends_with(".json"): files.append(path + fn)
			fn = dir.get_next()
	return files

func _load_level_to_editor(path: String) -> void:
	AudioManager.play("ui_click")
	current_editing_file_name = path.get_file().get_basename()
	level.load_level(path)
	call_deferred("_make_all_tiles_editable")
	call_deferred("_update_ghost_pos")
	load_popup.visible = false

func _get_current_level_data(custom_name: String = "My Level") -> Dictionary:
	var level_data = {
		"metadata": {"level_name": custom_name, "author": GameState.author_name, "date": Time.get_datetime_string_from_system()},
		"settings": {"grid_width": level.grid_width, "grid_height": level.grid_height, "start_pos": {"x": level.player_start_grid_pos.x, "z": level.player_start_grid_pos.y}},
		"tiles": []
	}
	for pos in level.tiles:
		var tile = level.tiles[pos]
		if tile.type == Tile.TileType.DEFAULT: continue
		var tile_info = {"pos": {"x": tile.grid_pos.x, "z": tile.grid_pos.y}, "type": "", "color": tile.target_color.to_html(), "value": tile.target_value, "uses": tile.uses}
		match tile.type:
			Tile.TileType.GOAL: tile_info["type"] = "GOAL"
			Tile.TileType.COLOR_CHANGER: tile_info["type"] = "COLOR_CHANGER"
			Tile.TileType.OBSTACLE: tile_info["type"] = "OBSTACLE"
			Tile.TileType.HOLE: tile_info["type"] = "HOLE"
		level_data["tiles"].append(tile_info)
	return level_data

func _on_confirm_save() -> void:
	var file_name = file_name_edit.text.strip_edges()
	if file_name == "": file_name = "level_" + str(Time.get_unix_time_from_system()).substr(0, 5)
	current_editing_file_name = file_name
	var level_data = _get_current_level_data(file_name)
	var dir_path = OS.get_user_data_dir() + "/levels/" if OS.get_name() == "Android" else "res://levels/"
	if not DirAccess.dir_exists_absolute(dir_path): DirAccess.make_dir_recursive_absolute(dir_path)
	var file_path = dir_path + file_name + ".json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(level_data, "\t"))
		AudioManager.play("goal")
		save_popup.visible = false
	else:
		AudioManager.play("error")

func play_level() -> void:
	GameState.preview_level_data = _get_current_level_data("Preview")
	GameState.current_mode = GameState.GameMode.CUSTOM
	GameState.selected_level_path = ""
	GameState.is_preview_mode = true
	AudioManager.play("ui_click")
	get_tree().change_scene_to_file("res://main.tscn")

func _update_ghost_pos() -> void:
	ghost_player.global_position = Vector3(level.player_start_grid_pos.x, 0.5, level.player_start_grid_pos.y)

func _unhandled_input(event: InputEvent) -> void:
	var any_popup = prop_popup.visible or save_popup.visible or load_popup.visible or del_popup.visible
	if any_popup: return
	
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var cam = get_viewport().get_camera_3d()
		if cam:
			var rot_y = camera_pivot.rotation.y
			var forward = Vector3.FORWARD.rotated(Vector3.UP, rot_y)
			var right = Vector3.RIGHT.rotated(Vector3.UP, rot_y)
			var sensitivity = 0.01 * (camera_pivot.get_node("Camera3D").position.z / 9.0)
			var move_vec = (right * -event.relative.x + forward * event.relative.y) * sensitivity
			camera_pivot.global_position += move_vec

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			if current_mode == EditMode.TILE: current_tool_idx = (current_tool_idx + 1) % tools.size()
			else: current_mode = EditMode.TILE
			_update_tool_ui()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_5:
			current_mode = EditMode.TILE
			current_tool_idx = event.keycode - KEY_1
			_update_tool_ui()
		elif event.keycode == KEY_B:
			current_mode = EditMode.PLAYER_START
			_update_tool_ui()

func _update_tool_ui() -> void:
	if current_mode == EditMode.PLAYER_START:
		tool_label.text = "Tool: START POS"
		return
	var type_name = ""
	match tools[current_tool_idx]:
		Tile.TileType.DEFAULT: type_name = "TILE"
		Tile.TileType.GOAL: type_name = "GOAL"
		Tile.TileType.OBSTACLE: type_name = "WALL"
		Tile.TileType.HOLE: type_name = "HOLE"
		Tile.TileType.COLOR_CHANGER: type_name = "CHANGER"
	tool_label.text = "Tool: " + type_name
