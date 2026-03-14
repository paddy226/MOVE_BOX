extends Node3D
# editor.gd - 支援自訂起點與 WASD 移動地圖的編輯器

@onready var level = $Level
@onready var tool_label = $CanvasLayer/HUD/ToolLabel
@onready var ghost_player = $GhostPlayer
@onready var camera_pivot = $CameraPivot

@export var move_speed: float = 10.0 # 地圖平移速度

var current_tool_idx: int = 0
enum EditMode { TILE, PLAYER_START }
var current_mode = EditMode.TILE

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
	_update_tool_ui()
	_update_ghost_pos()
	
	$CanvasLayer/HUD/BackButton.pressed.connect(func(): get_tree().change_scene_to_file("res://menu.tscn"))

func _process(delta: float) -> void:
	_handle_camera_movement(delta)

func _handle_camera_movement(delta: float) -> void:
	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.z += 1 # 修正：朝前進方向移動
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.z -= 1 # 修正：朝後退方向移動
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1
	
	if input_dir != Vector3.ZERO:
		input_dir = input_dir.normalized()
		# 根據攝影機 Y 軸旋轉來調整移動方向，讓操作更直覺
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

func _on_tile_clicked(tile: Tile) -> void:
	if current_mode == EditMode.PLAYER_START:
		level.player_start_grid_pos = tile.grid_pos
		_update_ghost_pos()
		AudioManager.play("ui_click")
	else:
		var tool_type = tools[current_tool_idx]
		tile.type = tool_type
		tile._update_visuals()
		AudioManager.play("ui_click")

func _update_ghost_pos() -> void:
	ghost_player.global_position = Vector3(level.player_start_grid_pos.x, 0.5, level.player_start_grid_pos.y)

func _unhandled_input(event: InputEvent) -> void:
	# 處理滑鼠左鍵拖曳
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var cam = get_viewport().get_camera_3d()
		if cam:
			# 根據攝影機 Y 軸旋轉來計算平移向量
			var rot_y = camera_pivot.rotation.y
			var forward = Vector3.FORWARD.rotated(Vector3.UP, rot_y)
			var right = Vector3.RIGHT.rotated(Vector3.UP, rot_y)
			
			# 位移量根據攝影機高度縮放，讓拖曳感更平滑
			var sensitivity = 0.01 * (camera_pivot.get_node("Camera3D").position.z / 9.0)
			var move_vec = (right * -event.relative.x + forward * event.relative.y) * sensitivity
			camera_pivot.global_position += move_vec

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			if current_mode == EditMode.TILE:
				current_tool_idx = (current_tool_idx + 1) % tools.size()
			else:
				current_mode = EditMode.TILE # 切換回方塊模式
			_update_tool_ui()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_5:
			current_mode = EditMode.TILE
			current_tool_idx = event.keycode - KEY_1
			_update_tool_ui()
		elif event.keycode == KEY_B: # 改為 B 鍵
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
