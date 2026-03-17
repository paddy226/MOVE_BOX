extends Node3D
# level.gd - 支援 JSON 載入與隨機生成

@export var tile_scene: PackedScene = preload("res://tile.tscn")
@export var grid_width: int = 10
@export var grid_height: int = 10

var tiles: Dictionary = {} 
var total_goals: int = 0
var completed_goals: int = 0
var possible_colors = [
	Color.RED, 
	Color.GREEN, 
	Color.BLUE, 
	Color.YELLOW, 
	Color.PURPLE,
	Color.DARK_GREEN
]
var player_start_grid_pos: Vector2i = Vector2i(0, 0) # 方塊初始位置

signal level_cleared

const LEVEL_DIR = "res://levels/"

func _ready() -> void:
	randomize()
	
	# 核心邏輯：根據模式與資料狀態決定載入方式
	var should_use_preview = not GameState.preview_level_data.is_empty() and (
		GameState.current_mode == GameState.GameMode.CHALLENGE or 
		GameState.current_mode == GameState.GameMode.EDITOR or 
		GameState.is_preview_mode
	)
	
	if should_use_preview:
		# 載入預覽/挑戰資料
		generate_from_data(GameState.preview_level_data)
	elif GameState.current_mode == GameState.GameMode.CUSTOM and GameState.selected_level_path != "":
		load_level(GameState.selected_level_path)
	elif GameState.current_mode == GameState.GameMode.RANDOM:
		generate_random_grid()
	else:
		# 預設保險：隨機生成
		generate_random_grid()
	
	# 初始化玩家位置
	call_deferred("_initialize_player_position")

func _initialize_player_position() -> void:
	var player = get_parent().get_node_or_null("Player")
	if player:
		player.global_position = Vector3(player_start_grid_pos.x, 0, player_start_grid_pos.y)
		if player.has_method("_snap_to_grid"):
			player._snap_to_grid()
		print("玩家已初始化於起點: ", player_start_grid_pos)

# 核心邏輯：從 JSON 載入關卡
func load_level(file_path: String) -> void:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("無法讀取檔案: ", file_path)
		generate_random_grid()
		return
		
	var json_string = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error != OK:
		print("JSON 解析錯誤: ", json.get_error_message())
		generate_random_grid()
		return
		
	var data = json.get_data()
	generate_from_data(data)

# 根據解析後的資料生成地圖
func generate_from_data(data: Dictionary) -> void:
	# 1. 清除舊地圖
	for child in get_children():
		child.queue_free()
	tiles.clear()
	total_goals = 0
	completed_goals = 0
	
	# 2. 讀取設定
	var settings = data.get("settings", {})
	grid_width = settings.get("grid_width", 10)
	grid_height = settings.get("grid_height", 10)
	
	var start_pos_data = settings.get("start_pos", {"x": 0, "z": 0})
	player_start_grid_pos = Vector2i(int(start_pos_data.x), int(start_pos_data.z))
	
	# 3. 處理特殊格資料
	var special_tiles = {} # Vector2i -> {type, color, value, uses}
	var hole_coords = []
	
	for tile_data in data.get("tiles", []):
		var pos_data = tile_data.get("pos", {"x":0, "z":0})
		var pos = Vector2i(int(pos_data.x), int(pos_data.z))
		
		var type_str = tile_data.get("type", "DEFAULT")
		var type = Tile.TileType.DEFAULT
		
		match type_str:
			"COLOR_CHANGER": type = Tile.TileType.COLOR_CHANGER
			"GOAL": type = Tile.TileType.GOAL
			"OBSTACLE": type = Tile.TileType.OBSTACLE
			"HOLE": 
				# 關鍵：如果是編輯器模式，我們需要方塊來顯示紅色預覽並接收點擊
				if GameState.current_mode == GameState.GameMode.EDITOR:
					type = Tile.TileType.HOLE
				else:
					# 正式遊戲模式，完全不生成物件
					hole_coords.append(pos)
					continue
		
		special_tiles[pos] = {
			"type": type,
			"color": Color.from_string(tile_data.get("color", "#FFFFFF"), Color.WHITE),
			"value": int(tile_data.get("value", 0)),
			"uses": int(tile_data.get("uses", -1))
		}
		
		if type == Tile.TileType.GOAL:
			total_goals += 1

	# 4. 完整生成網格
	var start_x = -grid_width / 2
	var start_z = -grid_height / 2
	
	for x in range(start_x, start_x + grid_width):
		for z in range(start_z, start_z + grid_height):
			var pos = Vector2i(x, z)
			if pos in hole_coords: continue
			
			var tile = tile_scene.instantiate()
			tile.grid_pos = pos
			
			if pos in special_tiles:
				var d = special_tiles[pos]
				tile.type = d.type
				tile.target_color = d.color
				tile.target_value = d.value
				tile.uses = d.uses
			else:
				tile.type = Tile.TileType.DEFAULT
				
			add_child(tile)
			tile.position = Vector3(x, -0.5, z)
			tile.name = "Tile_%d_%d" % [x, z]
			tiles[pos] = tile
	
	print("關卡載入成功: ", data.get("metadata", {}).get("level_name", "未命名"))

# 生成一個全滿的預設地圖 (供編輯器使用)
func generate_empty_grid() -> void:
	for child in get_children(): child.queue_free()
	tiles.clear()
	total_goals = 0
	completed_goals = 0
	player_start_grid_pos = Vector2i(0, 0)
	
	var start_x = -grid_width / 2
	var start_z = -grid_height / 2
	
	for x in range(start_x, start_x + grid_width):
		for z in range(start_z, start_z + grid_height):
			var tile = tile_scene.instantiate()
			var pos = Vector2i(x, z)
			tile.grid_pos = pos
			tile.type = Tile.TileType.DEFAULT
			
			add_child(tile)
			tile.position = Vector3(x, -0.5, z)
			tile.name = "Tile_%d_%d" % [x, z]
			tiles[pos] = tile

# 原有的隨機生成邏輯
func generate_random_grid() -> void:
	for child in get_children(): child.queue_free()
	tiles.clear()
	total_goals = 0
	completed_goals = 0
	player_start_grid_pos = Vector2i(0, 0)
	
	var all_coords = []
	var start_x = -grid_width / 2
	var start_z = -grid_height / 2
	for x in range(start_x, start_x + grid_width):
		for z in range(start_z, start_z + grid_height):
			if x == 0 and z == 0: continue
			all_coords.append(Vector2i(x, z))
	all_coords.shuffle()
	
	var goal_count = 3
	var required_colors = []
	var special_tiles = {}
	for i in range(goal_count):
		if all_coords.is_empty(): break
		var pos = all_coords.pop_front()
		var color = possible_colors.pick_random()
		var value = randi_range(1, 6)
		special_tiles[pos] = {"type": Tile.TileType.GOAL, "color": color, "value": value, "uses": -1}
		if not color in required_colors: required_colors.append(color)
		total_goals += 1

	for color in required_colors:
		if all_coords.is_empty(): break
		var pos = all_coords.pop_front()
		special_tiles[pos] = {"type": Tile.TileType.COLOR_CHANGER, "color": color, "value": 0, "uses": -1}

	var obstacle_count = 3
	for i in range(obstacle_count):
		if all_coords.is_empty(): break
		var pos = all_coords.pop_front()
		special_tiles[pos] = {"type": Tile.TileType.OBSTACLE, "color": Color.BLACK, "value": 0, "uses": -1}

	var hole_coords = []
	for i in range(3):
		if all_coords.is_empty(): break
		hole_coords.append(all_coords.pop_front())

	for x in range(start_x, start_x + grid_width):
		for z in range(start_z, start_z + grid_height):
			var pos = Vector2i(x, z)
			if pos in hole_coords: continue
			var tile = tile_scene.instantiate()
			tile.grid_pos = pos
			if pos in special_tiles:
				var d = special_tiles[pos]
				tile.type = d.type
				tile.target_color = d.color
				tile.target_value = d.value
				tile.uses = d.uses
			else:
				tile.type = Tile.TileType.DEFAULT
			add_child(tile)
			tile.position = Vector3(x, -0.5, z)
			tile.name = "Tile_%d_%d" % [x, z]
			tiles[pos] = tile

func get_tile_at(grid_pos: Vector2i) -> Node3D:
	return tiles.get(grid_pos, null)

func notify_goal_completed() -> void:
	completed_goals += 1
	if completed_goals >= total_goals:
		AudioManager.play("win")
		level_cleared.emit()
