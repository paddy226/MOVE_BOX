extends Control
# level_select_v2.gd - 關卡選擇清單 (支援搜尋、排序與平滑捲動)

@onready var scroll_container = $ScrollContainer
@onready var list_container = $ScrollContainer/VBoxContainer
@onready var search_box = $SearchBox
@onready var sort_name_btn = $SortBar/SortNameBtn
@onready var sort_time_btn = $SortBar/SortTimeBtn
@onready var del_popup = $DeletePopup
@onready var del_label = $DeletePopup/VBoxContainer/LevelName

var all_levels = [] # { "path": "...", "name": "...", "time": int, "can_delete": bool }
var sort_mode = "time" # "name" or "time"
var pending_delete_path: String = ""

# 拖曳捲動相關 (支援 PC 測試)
var is_dragging = false
var last_mouse_pos = Vector2.ZERO
var total_drag_distance = 0.0
const DRAG_THRESHOLD = 15.0 # 超過 15 像素視為拖曳而非點擊

func _ready() -> void:
	$BackButton.pressed.connect(func(): 
		GameState.reset_level_state()
		get_tree().change_scene_to_file("res://menu.tscn")
	)
	
	search_box.text_changed.connect(func(_new_text): _display_levels())
	sort_name_btn.pressed.connect(func(): _change_sort("name"))
	sort_time_btn.pressed.connect(func(): _change_sort("time"))
	
	# 初始化清單容器的過濾模式
	list_container.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# 連接刪除彈窗按鈕
	$DeletePopup/VBoxContainer/HBox/ConfirmDel.pressed.connect(_on_confirm_delete)
	$DeletePopup/VBoxContainer/HBox/CancelDel.pressed.connect(func(): del_popup.visible = false)
	
	_refresh_level_list()

func _input(event: InputEvent) -> void:
	# 實作滑鼠左鍵拖曳捲動 (僅用於模擬測試，不影響手機觸控)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 檢查滑鼠是否在捲動區域內
				if scroll_container.get_global_rect().has_point(event.global_position):
					is_dragging = true
					last_mouse_pos = event.global_position
					total_drag_distance = 0.0 # 重置拖曳距離
			else:
				# 放開滑鼠時延遲一小段時間才結束 dragging 狀態，或是在 selection 函式中檢查距離
				is_dragging = false
	
	elif event is InputEventMouseMotion and is_dragging:
		var delta = event.global_position.y - last_mouse_pos.y
		scroll_container.scroll_vertical -= delta
		total_drag_distance += abs(delta) # 累加移動距離
		last_mouse_pos = event.global_position

func _refresh_level_list() -> void:
	all_levels = []
	var can_delete_res = (OS.get_name() != "Android")
	_collect_levels_from_dir("res://levels/", can_delete_res)
	
	var user_path = OS.get_user_data_dir() + "/levels/" if OS.get_name() == "Android" else "user://levels/"
	_collect_levels_from_dir(user_path, true)
	
	_display_levels()

func _collect_levels_from_dir(path: String, can_delete: bool) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	var dir = DirAccess.open(path)
	dir.list_dir_begin()
	var fn = dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".json"):
			var full_path = path + fn
			var time = FileAccess.get_modified_time(full_path)
			all_levels.append({
				"path": full_path,
				"name": fn.get_basename(),
				"time": time,
				"can_delete": can_delete
			})
		fn = dir.get_next()

func _change_sort(mode: String) -> void:
	AudioManager.play("ui_click")
	sort_mode = mode
	_display_levels()

func _display_levels() -> void:
	for child in list_container.get_children(): child.queue_free()
	
	var search_text = search_box.text.to_lower()
	var filtered = []
	
	for lvl in all_levels:
		if search_text == "" or search_text in lvl.name.to_lower():
			filtered.append(lvl)
	
	# 執行排序
	if sort_mode == "name":
		filtered.sort_custom(func(a, b): return a.name.to_lower() < b.name.to_lower())
	else: # time (最新優先)
		filtered.sort_custom(func(a, b): return a.time > b.time)
	
	# 更新排序按鈕視覺
	sort_name_btn.modulate = Color.WHITE if sort_mode == "name" else Color(0.6, 0.6, 0.6)
	sort_time_btn.modulate = Color.WHITE if sort_mode == "time" else Color(0.6, 0.6, 0.6)
	
	for lvl in filtered:
		_create_level_row(lvl)

func _create_level_row(lvl: Dictionary) -> void:
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 100)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var select_btn = Button.new()
	select_btn.text = lvl.name
	# 如果是時間排序，可以在按鈕上顯示小日期
	if sort_mode == "time":
		var date_dict = Time.get_datetime_dict_from_unix_time(lvl.time)
		select_btn.text += " (%02d/%02d)" % [date_dict.month, date_dict.day]
		
	select_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_btn.add_theme_font_size_override("font_size", 32)
	select_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	select_btn.pressed.connect(func(): _on_level_selected(lvl.path))
	hbox.add_child(select_btn)
	
	if lvl.can_delete:
		var del_btn = Button.new()
		del_btn.text = " X "
		del_btn.custom_minimum_size = Vector2(100, 0)
		del_btn.add_theme_font_size_override("font_size", 32)
		del_btn.add_theme_color_override("font_color", Color.RED)
		del_btn.mouse_filter = Control.MOUSE_FILTER_PASS
		del_btn.pressed.connect(func(): _on_delete_request(lvl.path))
		hbox.add_child(del_btn)
		
	list_container.add_child(hbox)

func _on_level_selected(path: String) -> void:
	# 檢查是否為拖曳捲動
	if total_drag_distance > DRAG_THRESHOLD:
		print("[CustomV2] 偵測到大位移，取消點擊進入關卡 (Distance: ", total_drag_distance, ")")
		total_drag_distance = 0.0 # 歸零
		return
		
	AudioManager.play("ui_click")
	GameState.current_mode = GameState.GameMode.CUSTOM
	GameState.selected_level_path = path
	get_tree().change_scene_to_file("res://main.tscn")

func _on_delete_request(path: String) -> void:
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
	_refresh_level_list()
