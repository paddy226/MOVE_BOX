extends Node3D
# level.gd - 管理網格座標

@export var tile_scene: PackedScene = preload("res://tile.tscn")
@export var grid_width: int = 10
@export var grid_height: int = 10

var tiles: Dictionary = {} 
var total_goals: int = 0
var completed_goals: int = 0

var possible_colors = [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW, Color.PURPLE]

signal level_cleared

func _ready() -> void:
	# 設定隨機種子
	randomize()
	generate_grid()

func generate_grid() -> void:
	for child in get_children():
		child.queue_free()
	tiles.clear()
	total_goals = 0
	completed_goals = 0
	
	# 1. 建立所有可用座標列表 (確保 10x10 數量)
	var all_coords = []
	var start_x = -grid_width / 2
	var start_z = -grid_height / 2
	
	for x in range(start_x, start_x + grid_width):
		for z in range(start_z, start_z + grid_height):
			if x == 0 and z == 0: continue
			all_coords.append(Vector2i(x, z))
	
	# 隨機打亂座標順序
	all_coords.shuffle()
	
	# 2. 定義目標 (3 個)
	var goal_count = 3
	var required_colors = []
	var special_tiles = {} # 座標 -> {type, color, value}
	
	for i in range(goal_count):
		if all_coords.is_empty(): break
		var pos = all_coords.pop_front()
		var color = possible_colors.pick_random()
		var value = randi_range(1, 6)
		
		special_tiles[pos] = {
			"type": Tile.TileType.GOAL,
			"color": color,
			"value": value,
			"uses": -1
		}
		if not color in required_colors:
			required_colors.append(color)
		total_goals += 1

	# 3. 定義換色點 (根據目標顏色生成)
	for color in required_colors:
		if all_coords.is_empty(): break
		var pos = all_coords.pop_front()
		special_tiles[pos] = {
			"type": Tile.TileType.COLOR_CHANGER,
			"color": color,
			"value": 0,
			"uses": -1 # 無限次數
		}

	# 4. 定義障礙物 (3 個)
	var obstacle_count = 3
	for i in range(obstacle_count):
		if all_coords.is_empty(): break
		var pos = all_coords.pop_front()
		special_tiles[pos] = {
			"type": Tile.TileType.OBSTACLE,
			"color": Color.BLACK,
			"value": 0,
			"uses": -1
		}

	# 5. 生成所有地板
	for x in range(start_x, start_x + grid_width):
		for z in range(start_z, start_z + grid_height):
			var tile = tile_scene.instantiate()
			var pos = Vector2i(x, z)
			tile.grid_pos = pos
			
			if pos in special_tiles:
				var data = special_tiles[pos]
				tile.type = data.type
				tile.target_color = data.color
				tile.target_value = data.value
				tile.uses = data.uses
			else:
				tile.type = Tile.TileType.DEFAULT
			
			add_child(tile)
			tile.position = Vector3(x, -0.5, z)
			tile.name = "Tile_%d_%d" % [x, z]
			tiles[pos] = tile

func get_tile_at(grid_pos: Vector2i) -> Node3D:
	return tiles.get(grid_pos, null)

# 當某個格子達成目標時被呼叫
func notify_goal_completed() -> void:
	completed_goals += 1
	print("目標進度: ", completed_goals, "/", total_goals)
	if completed_goals >= total_goals:
		print("!!! 關卡完成 !!!")
		AudioManager.play("win")
		level_cleared.emit()
