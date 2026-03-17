extends Control
# level_select.gd - 關卡選擇清單 (支援刪除確認)

@onready var list_container = $ScrollContainer/VBoxContainer
@onready var del_popup = $DeletePopup
@onready var del_label = $DeletePopup/VBoxContainer/LevelName

var pending_delete_path: String = ""

func _ready() -> void:
	$BackButton.pressed.connect(func(): 
		GameState.reset_level_state()
		get_tree().change_scene_to_file("res://menu.tscn")
	)
	
	# 連接刪除彈窗按鈕
	$DeletePopup/VBoxContainer/HBox/ConfirmDel.pressed.connect(_on_confirm_delete)
	$DeletePopup/VBoxContainer/HBox/CancelDel.pressed.connect(func(): del_popup.visible = false)
	
	_refresh_level_list()

func _refresh_level_list() -> void:
	for child in list_container.get_children(): child.queue_free()
	var can_delete_res = (OS.get_name() != "Android")
	_add_levels_from_dir("res://levels/", can_delete_res)
	var user_path = OS.get_user_data_dir() + "/levels/" if OS.get_name() == "Android" else "user://levels/"
	_add_levels_from_dir(user_path, true)

func _add_levels_from_dir(path: String, can_delete: bool) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	var dir = DirAccess.open(path)
	dir.list_dir_begin()
	var fn = dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".json"):
			_create_level_row(path + fn, can_delete)
		fn = dir.get_next()

func _create_level_row(file_path: String, can_delete: bool) -> void:
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 100) # 加大按鈕高度
	var select_btn = Button.new()
	select_btn.text = file_path.get_file().get_basename()
	select_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_btn.add_theme_font_size_override("font_size", 32) # 加大字體
	select_btn.pressed.connect(func(): _on_level_selected(file_path))
	hbox.add_child(select_btn)
	if can_delete:
		var del_btn = Button.new()
		del_btn.text = " X "
		del_btn.custom_minimum_size = Vector2(100, 0)
		del_btn.add_theme_font_size_override("font_size", 32) # 加大字體
		del_btn.add_theme_color_override("font_color", Color.RED)
		del_btn.pressed.connect(func(): _on_delete_request(file_path))
		hbox.add_child(del_btn)
	list_container.add_child(hbox)

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
