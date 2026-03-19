extends Control
# level_select.gd - 關卡選擇清單 (支援分頁與刪除確認)

@onready var list_container = $ScrollContainer/GridContainer
@onready var del_popup = $DeletePopup
@onready var del_label = $DeletePopup/VBoxContainer/LevelName

# 分頁 UI
@onready var prev_btn = $Pagination/PrevBtn
@onready var next_btn = $Pagination/NextBtn
@onready var page_label = $Pagination/PageLabel

var all_levels = [] # 格式: { "path": "...", "can_delete": bool }
var current_page: int = 0
const ITEMS_PER_PAGE: int = 10
var pending_delete_path: String = ""

func _ready() -> void:
	$BackButton.pressed.connect(func(): 
		GameState.reset_level_state()
		get_tree().change_scene_to_file("res://menu.tscn")
	)
	
	prev_btn.pressed.connect(func(): 
		AudioManager.play("ui_click")
		current_page -= 1
		_display_levels()
	)
	next_btn.pressed.connect(func(): 
		AudioManager.play("ui_click")
		current_page += 1
		_display_levels()
	)
	
	# 連接刪除彈窗按鈕
	$DeletePopup/VBoxContainer/HBox/ConfirmDel.pressed.connect(_on_confirm_delete)
	$DeletePopup/VBoxContainer/HBox/CancelDel.pressed.connect(func(): del_popup.visible = false)
	
	_refresh_level_list()

func _refresh_level_list() -> void:
	all_levels = []
	var can_delete_res = (OS.get_name() != "Android")
	_collect_levels_from_dir("res://levels/", can_delete_res)
	
	var user_path = OS.get_user_data_dir() + "/levels/" if OS.get_name() == "Android" else "user://levels/"
	_collect_levels_from_dir(user_path, true)
	
	# 依照檔名排序
	all_levels.sort_custom(func(a, b): return a.path.get_file() < b.path.get_file())
	
	current_page = 0
	_display_levels()

func _collect_levels_from_dir(path: String, can_delete: bool) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	var dir = DirAccess.open(path)
	dir.list_dir_begin()
	var fn = dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".json"):
			all_levels.append({"path": path + fn, "can_delete": can_delete})
		fn = dir.get_next()

func _display_levels() -> void:
	for child in list_container.get_children(): child.queue_free()
	
	var total_items = all_levels.size()
	var total_pages = int(ceil(float(total_items) / ITEMS_PER_PAGE))
	if total_pages == 0: total_pages = 1
	
	current_page = clamp(current_page, 0, total_pages - 1)
	page_label.text = str(current_page + 1) + " / " + str(total_pages)
	prev_btn.disabled = (current_page == 0)
	next_btn.disabled = (current_page >= total_pages - 1)
	
	var start_idx = current_page * ITEMS_PER_PAGE
	var end_idx = min(start_idx + ITEMS_PER_PAGE, total_items)
	
	for i in range(start_idx, end_idx):
		var level_info = all_levels[i]
		_create_level_cell(level_info.path, level_info.can_delete)

func _create_level_cell(file_path: String, can_delete: bool) -> void:
	# 建立一個容器來包裝按鈕與刪除鍵
	var container = Control.new()
	container.custom_minimum_size = Vector2(300, 100)
	
	var select_btn = Button.new()
	select_btn.text = file_path.get_file().get_basename()
	select_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	select_btn.add_theme_font_size_override("font_size", 28)
	select_btn.pressed.connect(func(): _on_level_selected(file_path))
	container.add_child(select_btn)
	
	if can_delete:
		var del_btn = Button.new()
		del_btn.text = "X"
		del_btn.custom_minimum_size = Vector2(50, 50)
		del_btn.add_theme_color_override("font_color", Color.RED)
		container.add_child(del_btn)
		del_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 5)
		del_btn.pressed.connect(func(): _on_delete_request(file_path))
		
	list_container.add_child(container)

func _on_level_selected(path: String) -> void:
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
