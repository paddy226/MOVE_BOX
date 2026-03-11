extends Node
# swipe_detector.gd - 處理滑動與實體按鍵操作 (排除連發)

signal direction_changed(direction: Vector3)
signal pinched(delta: float)
signal camera_dragged(relative: Vector2)
signal camera_reset_requested # 新增：鏡頭復位信號

var swipe_start_pos: Vector2 = Vector2.ZERO
var min_swipe_distance: float = 50.0 
var current_direction: Vector3 = Vector3.ZERO # 當前按住的方向

# 多指觸控管理
var touches: Dictionary = {}
var last_pinch_distance: float = 0.0
var last_pinch_center: Vector2 = Vector2.ZERO

# 雙指連點偵測
var last_two_finger_tap_time: int = 0
const DOUBLE_TAP_DELAY_MS: int = 350 # 350 毫秒內的連點判定為雙擊

func _input(event: InputEvent) -> void:
	# 處理多指觸控
	if event is InputEventScreenTouch:
		if event.is_pressed():
			touches[event.index] = event.position
			if touches.size() == 1:
				swipe_start_pos = event.position
			elif touches.size() == 2:
				# 偵測雙指連點
				var current_time = Time.get_ticks_msec()
				if current_time - last_two_finger_tap_time < DOUBLE_TAP_DELAY_MS:
					camera_reset_requested.emit()
					last_two_finger_tap_time = 0 # 觸發後重置，避免三連點變兩次雙擊
				else:
					last_two_finger_tap_time = current_time
				
				last_pinch_distance = touches[0].distance_to(touches[1])
				last_pinch_center = (touches[0] + touches[1]) * 0.5
		else:
			touches.erase(event.index)
			if touches.size() < 2:
				last_pinch_distance = 0.0
				last_pinch_center = Vector2.ZERO
			
			if touches.size() == 0:
				current_direction = Vector3.ZERO
				direction_changed.emit(current_direction)
	
	if event is InputEventScreenDrag:
		touches[event.index] = event.position
		
		# 如果是雙指觸控
		if touches.size() == 2:
			var pos1 = touches[0]
			var pos2 = touches[1]
			
			# 1. 處理縮放 (Pinch)
			var dist = pos1.distance_to(pos2)
			if last_pinch_distance > 0:
				var delta_dist = dist - last_pinch_distance
				pinched.emit(delta_dist)
			last_pinch_distance = dist
			
			# 2. 處理鏡頭旋轉 (Drag)
			var center = (pos1 + pos2) * 0.5
			if last_pinch_center != Vector2.ZERO:
				var relative = center - last_pinch_center
				camera_dragged.emit(relative)
			last_pinch_center = center
			
		# 如果是單指，處理方向
		elif touches.size() == 1:
			_calculate_swipe(event.position)

	# 滑動偵測 (支援滑鼠點擊)
	if event is InputEventMouseButton:
		if event.is_pressed():
			swipe_start_pos = event.position
		else:
			current_direction = Vector3.ZERO
			direction_changed.emit(current_direction)
	
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_calculate_swipe(event.position)

func _calculate_swipe(end_pos: Vector2) -> void:
	var diff = end_pos - swipe_start_pos
	if diff.length() < min_swipe_distance:
		return
		
	var new_dir = Vector3.ZERO
	if abs(diff.x) > abs(diff.y):
		if diff.x > 0: new_dir = Vector3.RIGHT
		else: new_dir = Vector3.LEFT
	else:
		if diff.y > 0: new_dir = Vector3.BACK
		else: new_dir = Vector3.FORWARD
	
	if new_dir != current_direction:
		current_direction = new_dir
		direction_changed.emit(current_direction)
