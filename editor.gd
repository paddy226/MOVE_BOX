extends Node3D
# editor.gd - 支援彈窗屬性編輯的編輯器

@onready var level = $Level
@onready var tool_label = $CanvasLayer/HUD/ToolLabel
@onready var ghost_player = $GhostPlayer
@onready var camera_pivot = $CameraPivot

# 彈窗相關
@onready var prop_popup = $CanvasLayer/PropertyPopup
@onready var color_container = $CanvasLayer/PropertyPopup/VBoxContainer/ColorButtons
@onready var value_container = $CanvasLayer/PropertyPopup/VBoxContainer/ValueSection/ValueButtons
@onready var value_section = $CanvasLayer/PropertyPopup/VBoxContainer/ValueSection

@export var move_speed: float = 10.0

var current_tool_idx: int = 0
enum EditMode { TILE, PLAYER_START }
var current_mode = EditMode.TILE

var editing_tile: Tile = null # 當前正在透過彈窗編輯的方塊

var tools = [
	Tile.TileType.DEFAULT,
	Tile.TileType.GOAL,
	Tile.TileType.OBSTACLE,
	Tile.TileType.HOLE,
	Tile.TileType.COLOR_CHANGER
]

func _ready() -> void:
	level.generate_empty_grid()
	_make_all_tiles_editable()
	_setup_popup_ui()
	_update_tool_ui()
	_update_ghost_pos()
	
	$CanvasLayer/HUD/BackButton.pressed.connect(func(): get_tree().change_scene_to_file("res://menu.tscn"))
	$CanvasLayer/HUD/SaveButton.pressed.connect(save_level)
	$CanvasLayer/PropertyPopup/VBoxContainer/CloseButton.pressed.connect(func(): prop_popup.visible = false)

func _process(delta: float) -> void:
	if not prop_popup.visible:
		_handle_camera_movement(delta)

func _handle_camera_movement(delta: float) -> void:
	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.z += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.z -= 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1
	
	if input_dir != Vector3.ZERO:
		input_dir = input_dir.normalized()
		var rot_y = camera_pivot.rotation.y
		var forward = Vector3.FORWARD.rotated(Vector3.UP, rot_y)
		var right = Vector3.RIGHT.rotated(Vector3.UP, rot_y)
		var move_vec = (forward * input_dir.z + right * input_dir.x)
		camera_pivot.global_position += move_vec * move_speed * delta

func _make_all_tiles_editable() -> void:
	for pos in level.tiles:
		var tile = level.tiles[pos]
		if not tile.clicked.is_connected(_on_tile_clicked):
			tile.clicked.connect(_on_tile_clicked)

func _setup_popup_ui() -> void:
	# 1. 建立顏色按鈕
	for color in level.possible_colors:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(60, 60)
		var style = StyleBoxFlat.new()
		style.bg_color = color
		btn.add_theme_stylebox_override("normal", style)
		btn.pressed.connect(func(): _on_popup_color_selected(color))
		color_container.add_child(btn)
	
	# 2. 建立數值按鈕 (1-6)
	for i in range(1, 7):
		var btn = Button.new()
		btn.text = str(i)
		btn.custom_minimum_size = Vector2(50, 50)
		btn.pressed.connect(func(): _on_popup_value_selected(i))
		value_container.add_child(btn)

func _on_tile_clicked(tile: Tile) -> void:
	# 點擊起點模式
	if current_mode == EditMode.PLAYER_START:
		level.player_start_grid_pos = tile.grid_pos
		_update_ghost_pos()
		AudioManager.play("ui_click")
		return

	var tool_type = tools[current_tool_idx]
	
	# 如果點擊的是同類型的 GOAL 或 CHANGER，或是原本就有內容的格位，開啟彈窗
	if tile.type == tool_type and (tile.type == Tile.TileType.GOAL or tile.type == Tile.TileType.COLOR_CHANGER):
		_open_property_popup(tile)
	else:
		# 切換類型
		tile.type = tool_type
		# 預設初始化
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
	# 只有 GOAL 才顯示數值設定
	value_section.visible = (tile.type == Tile.TileType.GOAL)
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

func save_level() -> void:
	var level_data = {
		"metadata": {
			"level_name": "My Custom Level",
			"author": GameState.author_name,
			"date": Time.get_datetime_string_from_system()
		},
		"settings": {
			"grid_width": level.grid_width,
			"grid_height": level.grid_height,
			"start_pos": {"x": level.player_start_grid_pos.x, "z": level.player_start_grid_pos.y}
		},
		"tiles": []
	}
	
	for pos in level.tiles:
		var tile = level.tiles[pos]
		if tile.type == Tile.TileType.DEFAULT: continue
		var tile_info = {
			"pos": {"x": tile.grid_pos.x, "z": tile.grid_pos.y},
			"type": "",
			"color": tile.target_color.to_html(),
			"value": tile.target_value,
			"uses": tile.uses
		}
		match tile.type:
			Tile.TileType.GOAL: tile_info["type"] = "GOAL"
			Tile.TileType.COLOR_CHANGER: tile_info["type"] = "COLOR_CHANGER"
			Tile.TileType.OBSTACLE: tile_info["type"] = "OBSTACLE"
			Tile.TileType.HOLE: tile_info["type"] = "HOLE"
		level_data["tiles"].append(tile_info)
	
	var dir_path = OS.get_user_data_dir() + "/levels/" if OS.get_name() == "Android" else "res://levels/"
	if not DirAccess.dir_exists_absolute(dir_path): DirAccess.make_dir_recursive_absolute(dir_path)
	var file_path = dir_path + "my_level.json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(level_data, "\t"))
		print("關卡已儲存至: ", file_path)
		AudioManager.play("goal")
	else:
		print("儲存失敗！")
		AudioManager.play("error")

func _update_ghost_pos() -> void:
	ghost_player.global_position = Vector3(level.player_start_grid_pos.x, 0.5, level.player_start_grid_pos.y)

func _unhandled_input(event: InputEvent) -> void:
	# 只有在彈窗關閉時才允許拖曳鏡頭
	if prop_popup.visible: return

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
		tool_label.text = "當前工具: PLAYER START (起點)"
		return
	var type_name = ""
	match tools[current_tool_idx]:
		Tile.TileType.DEFAULT: type_name = "DEFAULT (地板)"
		Tile.TileType.GOAL: type_name = "GOAL (目標)"
		Tile.TileType.OBSTACLE: type_name = "OBSTACLE (方塊)"
		Tile.TileType.HOLE: type_name = "HOLE (孔洞)"
		Tile.TileType.COLOR_CHANGER: type_name = "CHANGER (換色點)"
	tool_label.text = "當前工具: " + type_name
