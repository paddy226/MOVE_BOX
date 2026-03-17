extends Node3D
# editor.gd - 支援圖示化 Palette、預覽恢復與自動載入前次進度的編輯器

@onready var level = $Level
@onready var tool_label = $CanvasLayer/HUD/ToolLabel
@onready var ghost_player = $GhostPlayer
@onready var camera_pivot = $CameraPivot

# 彈窗
@onready var prop_popup = $CanvasLayer/PropertyPopup
@onready var save_popup = $CanvasLayer/SavePopup
@onready var load_popup = $CanvasLayer/LoadPopup
@onready var del_popup = $CanvasLayer/DeletePopup
@onready var alert_popup = $CanvasLayer/AlertPopup
@onready var alert_label = $CanvasLayer/AlertPopup/VBoxContainer/Msg

@onready var load_list = $CanvasLayer/LoadPopup/VBoxContainer/ScrollContainer/List
@onready var file_name_edit = $CanvasLayer/SavePopup/VBoxContainer/FileNameEdit
@onready var del_label = $CanvasLayer/DeletePopup/VBoxContainer/LevelName

# UI 容器
@onready var toolbar = $CanvasLayer/HUD/Toolbar
@onready var palette = $CanvasLayer/HUD/ToolPalette

@export var move_speed: float = 10.0

var current_editing_file_name: String = ""
var current_tool_idx: int = 0
enum EditMode { TILE, PLAYER_START }
var current_mode = EditMode.TILE

var editing_tile: Tile = null
var pending_delete_path: String = ""

const AUTOSAVE_PATH = "user://editor_autosave.json"

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
		# 1. 優先處理預覽返回 (記憶體恢復)
		level.generate_from_data(GameState.preview_level_data)
		GameState.preview_level_data = {}
		print("已從預覽恢復")
	elif FileAccess.file_exists(AUTOSAVE_PATH):
		# 2. 其次處理自動存檔載入 (磁碟恢復)
		_load_autosave()
		print("已載入前次編輯進度")
	else:
		# 3. 都沒有則生成空白
		level.generate_empty_grid()
		current_editing_file_name = ""
		print("生成新畫布")
		
	_make_all_tiles_editable()
	_setup_popup_ui()
	_setup_palette_ui()
	_update_tool_ui()
	_update_ghost_pos()
	
	# 連接功能按鈕
	$CanvasLayer/HUD/BackButton.pressed.connect(_on_back_pressed)
	toolbar.get_node("SaveButton").pressed.connect(_on_save_pressed)
	toolbar.get_node("LoadButton").pressed.connect(_on_load_pressed)
	toolbar.get_node("PlayButton").pressed.connect(play_level)
	if toolbar.has_node("ImportButton"):
		toolbar.get_node("ImportButton").pressed.connect(_on_import_pressed)
	if toolbar.has_node("ShareButton"):
		toolbar.get_node("ShareButton").pressed.connect(_on_share_pressed)
	toolbar.get_node("ClearButton").pressed.connect(_on_clear_pressed)
	
	# 彈窗按鈕
	$CanvasLayer/PropertyPopup/VBoxContainer/CloseButton.pressed.connect(func(): prop_popup.visible = false)
	$CanvasLayer/SavePopup/VBoxContainer/HBoxContainer/ConfirmSave.pressed.connect(_on_confirm_save)
	$CanvasLayer/SavePopup/VBoxContainer/HBoxContainer/CancelSave.pressed.connect(func(): save_popup.visible = false)
	$CanvasLayer/LoadPopup/VBoxContainer/CloseLoad.pressed.connect(func(): load_popup.visible = false)
	$CanvasLayer/DeletePopup/VBoxContainer/HBox/ConfirmDel.pressed.connect(_on_confirm_delete)
	$CanvasLayer/DeletePopup/VBoxContainer/HBox/CancelDel.pressed.connect(func(): del_popup.visible = false)
	$CanvasLayer/AlertPopup/VBoxContainer/CloseAlert.pressed.connect(func(): alert_popup.visible = false)

func _setup_palette_ui() -> void:
	palette.get_node("Btn_Tile").pressed.connect(func(): _select_tool(0))
	palette.get_node("Btn_Goal").pressed.connect(func(): _select_tool(1))
	palette.get_node("Btn_Wall").pressed.connect(func(): _select_tool(2))
	palette.get_node("Btn_Hole").pressed.connect(func(): _select_tool(3))
	palette.get_node("Btn_Changer").pressed.connect(func(): _select_tool(4))
	palette.get_node("Btn_Start").pressed.connect(func(): 
		current_mode = EditMode.PLAYER_START
		AudioManager.play("ui_click")
		_update_tool_ui()
	)

func _select_tool(idx: int) -> void:
	current_mode = EditMode.TILE
	current_tool_idx = idx
	AudioManager.play("ui_click")
	_update_tool_ui()

func _validate_level() -> String:
	var goals = []
	var changers = []
	var start_tile = null
	for pos in level.tiles:
		var tile = level.tiles[pos]
		if tile.type == Tile.TileType.GOAL: goals.append(tile)
		elif tile.type == Tile.TileType.COLOR_CHANGER: changers.append(tile)
		if tile.grid_pos == level.player_start_grid_pos: start_tile = tile
	if goals.is_empty(): return "Missing GOAL! You need at least one target."
	if start_tile == null or start_tile.type == Tile.TileType.HOLE or start_tile.type == Tile.TileType.OBSTACLE:
		return "Invalid START POS! Player cannot start on a wall or hole."
	
	var reachable_coords = []
	var queue = [level.player_start_grid_pos]
	var visited = {level.player_start_grid_pos: true}
	while not queue.is_empty():
		var current = queue.pop_front()
		reachable_coords.append(current)
		for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var neighbor = current + offset
			if neighbor in level.tiles and not neighbor in visited:
				var t = level.tiles[neighbor]
				if t.type != Tile.TileType.OBSTACLE and t.type != Tile.TileType.HOLE:
					visited[neighbor] = true
					queue.push_back(neighbor)
	for g in goals:
		if not g.grid_pos in reachable_coords: return "Unreachable GOAL! Check your walls/holes."
	var required_colors = []
	for g in goals:
		if g.target_color != Color.WHITE and not g.target_color in required_colors: required_colors.append(g.target_color)
	for req in required_colors:
		var color_found = false
		for c in changers:
			if c.target_color == req and c.grid_pos in reachable_coords: color_found = true; break
		if not color_found: return "Unreachable or Missing CHANGER for [" + _get_color_name(req) + "]!"
	return ""

func _on_clear_pressed() -> void:
	AudioManager.play("ui_click")
	level.generate_empty_grid()
	current_editing_file_name = ""
	_make_all_tiles_editable()
	_update_ghost_pos()
	_autosave() # 清除後也自動儲存狀態

func _on_back_pressed() -> void:
	_autosave() # 離開前自動儲存
	GameState.is_preview_mode = false
	GameState.preview_level_data = {}
	get_tree().change_scene_to_file("res://menu.tscn")

func _process(delta: float) -> void:
	var any_popup = prop_popup.visible or save_popup.visible or load_popup.visible or del_popup.visible or alert_popup.visible
	if not any_popup: _handle_camera_movement(delta)

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
		btn.custom_minimum_size = Vector2(80, 80)
		var style = StyleBoxFlat.new()
		style.bg_color = color
		btn.add_theme_stylebox_override("normal", style)
		btn.pressed.connect(func(): _on_popup_color_selected(color))
		color_container.add_child(btn)
	var value_container = $CanvasLayer/PropertyPopup/VBoxContainer/ValueSection/ValueButtons
	for i in range(1, 7):
		var btn = Button.new()
		btn.text = str(i)
		btn.custom_minimum_size = Vector2(70, 70)
		btn.add_theme_font_size_override("font_size", 32)
		btn.pressed.connect(func(): _on_popup_value_selected(i))
		value_container.add_child(btn)

func _on_tile_clicked(tile: Tile) -> void:
	var any_popup = prop_popup.visible or save_popup.visible or load_popup.visible or del_popup.visible or alert_popup.visible
	if any_popup: return
	if current_mode == EditMode.PLAYER_START:
		level.player_start_grid_pos = tile.grid_pos
		_update_ghost_pos()
		AudioManager.play("ui_click")
		_autosave() # 更新起點後也自動儲存
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
		_autosave() # 修改方塊後自動儲存

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
		_autosave()

func _on_popup_value_selected(val: int) -> void:
	if editing_tile: 
		editing_tile.target_value = val
		editing_tile._update_visuals()
		AudioManager.play("ui_click")
		_autosave()

func _on_share_pressed() -> void:
	var err = _validate_level()
	if err != "":
		alert_label.text = err
		alert_popup.get_node("VBoxContainer/Title").text = "INVALID LEVEL"
		alert_popup.visible = true
		AudioManager.play("error")
		return
		
	var level_data = _get_current_level_data("Shared Level")
	var json_string = JSON.stringify(level_data)
	
	DisplayServer.clipboard_set(json_string)
	
	alert_label.text = "Level data copied to clipboard!\nYou can now paste it to share with others."
	alert_popup.get_node("VBoxContainer/Title").text = "SHARE SUCCESS"
	alert_popup.visible = true
	AudioManager.play("ui_click")

func _on_save_pressed() -> void:
	var err = _validate_level()
	if err != "": alert_label.text = err; alert_popup.visible = true; AudioManager.play("error"); return
	AudioManager.play("ui_click")
	file_name_edit.text = current_editing_file_name
	save_popup.visible = true

func _on_load_pressed() -> void:
	AudioManager.play("ui_click")
	_refresh_load_list()
	load_popup.visible = true

func _refresh_load_list() -> void:
	for child in load_list.get_children(): child.queue_free()
	var can_delete_res = (OS.get_name() != "Android")
	_add_levels_to_load_list("res://levels/", can_delete_res)
	var user_path = OS.get_user_data_dir() + "/levels/" if OS.get_name() == "Android" else "user://levels/"
	_add_levels_to_load_list(user_path, true)
	
func _add_levels_to_load_list(path: String, can_delete: bool) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	var dir = DirAccess.open(path)
	dir.list_dir_begin()
	var fn = dir.get_next()
	var levels = []
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".json"): levels.append(path + fn)
		fn = dir.get_next()
	levels.sort_custom(func(a, b): return a.get_file().to_lower() < b.get_file().to_lower())
	for full_path in levels:
		var hbox = HBoxContainer.new()
		hbox.custom_minimum_size = Vector2(0, 100)
		var btn = Button.new()
		btn.text = full_path.get_file().get_basename()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 32)
		btn.pressed.connect(func(): _load_level_to_editor(full_path))
		hbox.add_child(btn)
		if can_delete:
			var del = Button.new()
			del.text = " X "
			del.custom_minimum_size = Vector2(100, 0)
			del.add_theme_font_size_override("font_size", 32)
			del.add_theme_color_override("font_color", Color.RED)
			del.pressed.connect(func(): _on_delete_requested(full_path))
			hbox.add_child(del)
		load_list.add_child(hbox)

func _on_delete_requested(path: String) -> void:
	AudioManager.play("ui_click"); pending_delete_path = path; del_label.text = path.get_file().get_basename(); del_popup.visible = true

func _on_confirm_delete() -> void:
	var path = pending_delete_path
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path); AudioManager.play("error")
	del_popup.visible = false; _refresh_load_list()

func _load_level_to_editor(path: String) -> void:
	AudioManager.play("ui_click"); current_editing_file_name = path.get_file().get_basename()
	level.load_level(path); call_deferred("_make_all_tiles_editable"); call_deferred("_update_ghost_pos"); load_popup.visible = false
	_autosave()

func _get_current_level_data(custom_name: String = "My Level") -> Dictionary:
	var level_data = {
		"metadata": {"level_name": custom_name, "author": GameState.author_name, "date": Time.get_datetime_string_from_system(), "current_file": current_editing_file_name},
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

# 自動儲存邏輯 (Autosave)
func _autosave() -> void:
	var level_data = _get_current_level_data("Autosave")
	var file = FileAccess.open(AUTOSAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(level_data))
		# print("自動儲存完成")

# 載入自動儲存
func _load_autosave() -> void:
	var file = FileAccess.open(AUTOSAVE_PATH, FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data = json.get_data()
			level.generate_from_data(data)
			# 恢復當時正在編輯的檔名
			current_editing_file_name = data.get("metadata", {}).get("current_file", "")

func _on_confirm_save() -> void:
	var file_name = file_name_edit.text.strip_edges()
	if file_name == "": file_name = "level_" + str(Time.get_unix_time_from_system()).substr(0, 5)
	current_editing_file_name = file_name
	var level_data = _get_current_level_data(file_name)
	var dir_path = OS.get_user_data_dir() + "/levels/" if OS.get_name() == "Android" else "res://levels/"
	if not DirAccess.dir_exists_absolute(dir_path): DirAccess.make_dir_recursive_absolute(dir_path)
	var file_path = dir_path + file_name + ".json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(level_data, "\t")); AudioManager.play("goal"); save_popup.visible = false
	else: AudioManager.play("error")
	_autosave()

func play_level() -> void:
	var err = _validate_level()
	if err != "": alert_label.text = err; alert_popup.visible = true; AudioManager.play("error"); return
	_autosave() # 預覽前先存檔
	GameState.preview_level_data = _get_current_level_data("Preview")
	GameState.current_mode = GameState.GameMode.CUSTOM; GameState.selected_level_path = ""; GameState.is_preview_mode = true
	AudioManager.play("ui_click"); get_tree().change_scene_to_file("res://main.tscn")

func _update_ghost_pos() -> void:
	ghost_player.global_position = Vector3(level.player_start_grid_pos.x, 0.5, level.player_start_grid_pos.y)

func _unhandled_input(event: InputEvent) -> void:
	var any_popup = prop_popup.visible or save_popup.visible or load_popup.visible or del_popup.visible or alert_popup.visible
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
			_select_tool(event.keycode - KEY_1)
		elif event.keycode == KEY_B: current_mode = EditMode.PLAYER_START; _update_tool_ui()

func _update_tool_ui() -> void:
	for i in range(palette.get_child_count()):
		var btn = palette.get_child(i)
		if btn is TextureButton:
			if current_mode == EditMode.PLAYER_START:
				btn.modulate.a = 1.0 if btn.name == "Btn_Start" else 0.6
			else:
				btn.modulate.a = 1.0 if i == current_tool_idx else 0.6

	if current_mode == EditMode.PLAYER_START: tool_label.text = "Tool: START POS"; return
	var type_name = ""
	match tools[current_tool_idx]:
		Tile.TileType.DEFAULT: type_name = "TILE"
		Tile.TileType.GOAL: type_name = "GOAL"
		Tile.TileType.OBSTACLE: type_name = "WALL"
		Tile.TileType.HOLE: type_name = "HOLE"
		Tile.TileType.COLOR_CHANGER: type_name = "CHANGER"
	tool_label.text = "Tool: " + type_name

func _get_color_name(c: Color) -> String:
	if c == Color.RED: return "Red"; if c == Color.GREEN: return "Green"; if c == Color.BLUE: return "Blue"
	if c == Color.YELLOW: return "Yellow"; if c == Color.PURPLE: return "Purple"; if c == Color.DARK_GREEN: return "Dark Green"
	return "White"

func _on_import_pressed() -> void:
	var clipboard = DisplayServer.clipboard_get().strip_edges()
	if clipboard == "":
		_show_alert("Clipboard is empty!", "IMPORT ERROR")
		return
		
	var json = JSON.new()
	var error = json.parse(clipboard)
	if error != OK:
		_show_alert("Invalid level data in clipboard!\nMake sure you copied the full JSON.", "IMPORT ERROR")
		return
		
	var data = json.get_data()
	# 基本結構驗證
	if not data is Dictionary or not data.has("tiles") or not data.has("settings"):
		_show_alert("Incompatible level data format!", "IMPORT ERROR")
		return
		
	level.generate_from_data(data)
	current_editing_file_name = "Imported_" + str(Time.get_unix_time_from_system()).substr(-4)
	_make_all_tiles_editable()
	_update_ghost_pos()
	_autosave()
	_show_alert("Level imported successfully from clipboard!", "IMPORT SUCCESS")
	AudioManager.play("goal")

func _show_alert(msg: String, title: String = "ALERT") -> void:
	alert_label.text = msg
	alert_popup.get_node("VBoxContainer/Title").text = title
	alert_popup.visible = true
