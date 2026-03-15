extends Control
# menu.gd - 起始頁面邏輯

func _ready() -> void:
	# 設定按鈕連接
	$VBoxContainer/RandomButton.pressed.connect(_on_random_pressed)
	$VBoxContainer/CustomButton.pressed.connect(_on_custom_pressed)
	$VBoxContainer/EditorButton.pressed.connect(_on_editor_pressed)
	
	# 顯示版本號
	$VersionLabel.text = GameState.version_number + " by " + GameState.author_name

func _on_random_pressed() -> void:
	AudioManager.play("ui_click")
	GameState.current_mode = GameState.GameMode.RANDOM
	get_tree().change_scene_to_file("res://main.tscn")

func _on_custom_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().change_scene_to_file("res://level_select.tscn")

func _on_editor_pressed() -> void:
	AudioManager.play("ui_click")
	GameState.current_mode = GameState.GameMode.EDITOR
	get_tree().change_scene_to_file("res://editor.tscn")
