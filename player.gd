extends Node3D
# player.gd - 優化手感：加入持續翻滾與輸入緩衝

@export var roll_speed: float = 0.2
@export var grid_size: float = 1.0

var is_moving: bool = false
var current_bottom_value: int = 6 
var current_color: Color = Color.WHITE # 預設為白色
var error_cooldown: float = 0.0 # 錯誤音效冷卻時間
var buffered_input: Vector3 = Vector3.ZERO # 快速換向的緩衝
var active_intent_dir: Vector3 = Vector3.ZERO # 當前按住的方向

@onready var box_mesh: MeshInstance3D = $BoxMesh
@onready var face_labels_container: Node3D = $BoxMesh/FaceLabels

signal stepped(count: int)

func _ready() -> void:
	GameState.current_steps = 0 # 重啟時歸零
	_setup_material() # 初始化材質
	_update_bottom_face()
	
	# 連接手勢偵測器
	if has_node("SwipeDetector"):
		$SwipeDetector.direction_changed.connect(_on_swipe_direction_changed)

func _process(_delta: float) -> void:
	if error_cooldown > 0:
		error_cooldown -= _delta

func _unhandled_input(event: InputEvent) -> void:
	# 處理鍵盤按下的事件 (支援連續按住)
	if event is InputEventKey:
		var dir = Vector3.ZERO
		match event.keycode:
			KEY_W, KEY_UP: dir = Vector3.FORWARD
			KEY_S, KEY_DOWN: dir = Vector3.BACK
			KEY_A, KEY_LEFT: dir = Vector3.LEFT
			KEY_D, KEY_RIGHT: dir = Vector3.RIGHT
		
		if dir != Vector3.ZERO:
			if event.pressed:
				if active_intent_dir != dir:
					active_intent_dir = dir
					if not is_moving:
						roll_box(_get_camera_relative_dir(dir))
			else:
				# 放開按鍵時，如果放開的是當前方向，則清除
				if active_intent_dir == dir:
					active_intent_dir = Vector3.ZERO

func _on_swipe_direction_changed(intent_dir: Vector3) -> void:
	# SwipeDetector 在放開時會傳入 Vector3.ZERO
	active_intent_dir = intent_dir
	if intent_dir == Vector3.ZERO: return
	
	var world_dir = _get_camera_relative_dir(intent_dir)
	if is_moving:
		buffered_input = world_dir
	else:
		roll_box(world_dir)

func _get_camera_relative_dir(intent: Vector3) -> Vector3:
	var cam = get_viewport().get_camera_3d()
	if not cam: return intent
	
	var cam_basis = cam.global_transform.basis
	var cam_forward = -cam_basis.z
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()
	
	var cam_right = cam_basis.x
	cam_right.y = 0
	cam_right = cam_right.normalized()
	
	var target_vec = Vector3.ZERO
	if intent == Vector3.FORWARD: target_vec = cam_forward
	elif intent == Vector3.BACK: target_vec = -cam_forward
	elif intent == Vector3.LEFT: target_vec = -cam_right
	elif intent == Vector3.RIGHT: target_vec = cam_right
	
	if abs(target_vec.x) > abs(target_vec.z):
		return Vector3(round(target_vec.x), 0, 0)
	else:
		return Vector3(0, 0, round(target_vec.z))

func _setup_material() -> void:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = current_color
	mat.roughness = 0.5
	box_mesh.set_surface_override_material(0, mat)

func change_color(new_color: Color) -> void:
	current_color = new_color
	var mat = box_mesh.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		mat.albedo_color = new_color
	print("箱子顏色已更換為: ", new_color)

func flash() -> void:
	var mat = box_mesh.get_surface_override_material(0)
	if not mat is StandardMaterial3D: return
	var old_emission = mat.emission_enabled
	var old_energy = mat.emission_energy_multiplier
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 1.2
	var tween = get_tree().create_tween()
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func(): 
		mat.emission_enabled = old_emission
		mat.emission_energy_multiplier = old_energy
	)

func roll_box(dir: Vector3) -> void:
	if is_moving: return
	
	# 邊界與障礙物檢查 (維持原本不允許跌落的設計)
	var next_pos = Vector2i(round(global_position.x + dir.x * grid_size), round(global_position.z + dir.z * grid_size))
	var level = get_parent().get_node_or_null("Level")
	if level:
		var tile = level.get_tile_at(next_pos)
		if tile == null or tile.type == Tile.TileType.OBSTACLE or tile.type == Tile.TileType.HOLE:
			if error_cooldown <= 0:
				AudioManager.play("error")
				error_cooldown = 0.5
			return
			
	is_moving = true
	AudioManager.play("roll")
	
	GameState.current_steps += 1
	GameState.total_steps += 1 # 累加總步數
	stepped.emit(GameState.current_steps)
	
	var pivot_pos: Vector3 = global_position + (dir * grid_size * 0.5) + (Vector3.DOWN * grid_size * 0.5)
	var pivot_node = Node3D.new()
	get_parent().add_child(pivot_node)
	pivot_node.global_position = pivot_pos
	
	var original_parent = get_parent()
	self.reparent(pivot_node, true)
	
	var axis: Vector3 = dir.cross(Vector3.DOWN).normalized()
	var tween = get_tree().create_tween()
	tween.tween_method(
		func(angle: float): pivot_node.basis = Basis(axis, angle),
		0.0, PI/2, roll_speed
	)
	
	await tween.finished
	
	self.reparent(original_parent, true)
	pivot_node.queue_free()
	
	_snap_to_grid()
	_update_bottom_face()
	_check_tile_effect()
	
	is_moving = false
	
	# 處理連續翻滾
	# 優先處理快速操作的緩衝
	if buffered_input != Vector3.ZERO:
		var next_dir = buffered_input
		buffered_input = Vector3.ZERO
		roll_box(next_dir)
	# 其次檢查是否還按住方向
	elif active_intent_dir != Vector3.ZERO:
		roll_box(_get_camera_relative_dir(active_intent_dir))

func _check_tile_effect() -> void:
	var level = get_parent().get_node_or_null("Level")
	if level:
		var grid_pos = Vector2i(round(global_position.x), round(global_position.z))
		var tile = level.get_tile_at(grid_pos)
		if tile:
			tile.on_stepped(self)

func _update_bottom_face() -> void:
	var best_dot = -1.0
	var new_value = 1
	for label in face_labels_container.get_children():
		if label is Label3D:
			var face_normal = label.global_transform.basis.z.normalized()
			var dot = face_normal.dot(Vector3.DOWN)
			if dot > best_dot:
				best_dot = dot
				new_value = int(label.text)
	current_bottom_value = new_value

func _snap_to_grid() -> void:
	global_position.y = 0.0
	global_position.x = round(global_position.x / grid_size) * grid_size
	global_position.z = round(global_position.z / grid_size) * grid_size
	var b = global_transform.basis
	var x = Vector3(round(b.x.x), round(b.x.y), round(b.x.z))
	var y = Vector3(round(b.y.x), round(b.y.y), round(b.y.z))
	var z = Vector3(round(b.z.x), round(b.z.y), round(b.z.z))
	global_transform.basis = Basis(x, y, z).orthonormalized()
