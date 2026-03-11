extends Node3D
# camera_controller.gd - 優化後的鏡頭旋轉 (右鍵環繞)

@export var rotation_speed: float = 0.005
@export var min_pitch: float = deg_to_rad(-80) # 俯視角度限制
@export var max_pitch: float = deg_to_rad(-10)
@export var follow_speed: float = 5.0 # 跟隨速度
@export var zoom_speed: float = 0.5
@export var min_zoom: float = 3.0
@export var max_zoom: float = 15.0
@export var keyboard_rotation_speed: float = 2.0 # 鍵盤旋轉速度

var player: Node3D
var is_rotating: bool = false # 新增：旋轉鎖定
@onready var cam: Camera3D = $Camera3D

func _ready() -> void:
	# 讀取全域變數中的最後角度與距離
	rotation = GameState.last_camera_rotation
	cam.position.z = GameState.last_camera_distance
	
	# 尋找玩家節點並連接手勢信號
	player = get_tree().current_scene.get_node_or_null("Player")
	if player:
		var detector = player.get_node_or_null("SwipeDetector")
		if detector:
			detector.pinched.connect(_on_pinched)
			detector.camera_dragged.connect(_on_camera_dragged)
			detector.camera_reset_requested.connect(_reset_camera) # 新增：連接雙指復位信號

func _on_camera_dragged(relative: Vector2) -> void:
	# 手機雙指拖曳旋轉
	rotate_y(-relative.x * rotation_speed)
	
	var change = -relative.y * rotation_speed
	var new_pitch = rotation.x + change
	rotation.x = clamp(new_pitch, min_pitch, max_pitch)
	GameState.last_camera_rotation = rotation

func _on_pinched(delta: float) -> void:
	# 手機雙指縮放 (delta > 0 代表手指張開，應該拉近鏡頭)
	cam.position.z = clamp(cam.position.z - delta * 0.02, min_zoom, max_zoom)
	GameState.last_camera_distance = cam.position.z

func _process(delta: float) -> void:
	if player:
		# 平滑跟隨玩家位置
		global_position = global_position.lerp(player.global_position, follow_speed * delta)

func _unhandled_input(event: InputEvent) -> void:
	# 鏡頭旋轉 (Q/E 鍵 - 轉動 45 度)
	if not is_rotating and event is InputEventKey and event.pressed:
		var rot_dir = 0.0
		if event.keycode == KEY_Q: rot_dir = 1.0
		elif event.keycode == KEY_E: rot_dir = -1.0
		
		if rot_dir != 0.0:
			_rotate_camera_step(rot_dir * deg_to_rad(30))
			return

	# 鏡頭復位 (右鍵雙擊 或 鍵盤 R)
	var is_r_pressed = event is InputEventKey and event.pressed and event.keycode == KEY_R
	var is_right_double_click = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.double_click
	
	if is_r_pressed or is_right_double_click:
		_reset_camera()
		return

	# 鏡頭旋轉 (右鍵)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		# 水平旋轉：繞世界 Y 軸旋轉，避免傾斜
		rotate_y(-event.relative.x * rotation_speed)
		
		# 垂直旋轉：繞局部 X 軸旋轉，並限制角度
		var change = -event.relative.y * rotation_speed
		var new_pitch = rotation.x + change
		rotation.x = clamp(new_pitch, min_pitch, max_pitch)
		
		# 更新全域變數
		GameState.last_camera_rotation = rotation
		
	# 鏡頭縮放 (滾輪)
	if event is InputEventMouseButton:
		var changed = false
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.position.z = clamp(cam.position.z - zoom_speed, min_zoom, max_zoom)
			changed = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.position.z = clamp(cam.position.z + zoom_speed, min_zoom, max_zoom)
			changed = true
			
		if changed:
			GameState.last_camera_distance = cam.position.z

func _rotate_camera_step(angle_delta: float) -> void:
	is_rotating = true
	var target_y = rotation.y + angle_delta
	
	var tween = get_tree().create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation:y", target_y, 0.25) # 0.25 秒轉完 45 度
	
	await tween.finished
	is_rotating = false
	GameState.last_camera_rotation = rotation

func _reset_camera() -> void:
	# 預設值 (對應 game_state.gd 的初始值)
	var target_rotation = Vector3(-PI/3, 0, 0)
	var target_distance = 7.0
	
	# 建立動畫
	var tween = get_tree().create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
	# 平滑旋轉 (注意：這裡旋轉 Y 與 X 需要同時進行)
	tween.tween_property(self, "rotation", target_rotation, 0.6)
	
	# 平滑縮放
	tween.tween_property(cam, "position:z", target_distance, 0.6)
	
	# 同步更新全域變數
	GameState.last_camera_rotation = target_rotation
	GameState.last_camera_distance = target_distance
	
	print("鏡頭已復位")
