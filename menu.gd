extends Control
# menu.gd - 起始頁面邏輯

func _ready() -> void:
	# 設定按鈕連接
	$VBoxContainer/RandomButton.pressed.connect(_on_random_pressed)
	$VBoxContainer/CustomButton.pressed.connect(_on_custom_pressed)
	if $VBoxContainer.has_node("ChallengeButton"):
		$VBoxContainer/ChallengeButton.pressed.connect(_on_challenge_pressed)
	$VBoxContainer/EditorButton.pressed.connect(_on_editor_pressed)
	
	# 1. 隱藏原本在 .tscn 中的標籤，避免邏輯干擾
	if has_node("VersionLabel"):
		$VersionLabel.visible = false
	
	# 2. 使用統一邏輯建立對稱標籤
	var rank = _get_rank_name(GameState.total_steps)
	_create_bottom_label("Total Steps: " + str(GameState.total_steps) + " (" + rank + ")", Control.PRESET_BOTTOM_LEFT)
	_create_bottom_label(GameState.version_number + " by " + GameState.author_name, Control.PRESET_BOTTOM_RIGHT)

func _get_rank_name(steps: int) -> String:
	if steps < 1000: return "Newbie"
	if steps < 10000: return "Walker"
	if steps < 100000: return "Runner"
	if steps < 1000000: return "Master"
	return "Legend"

func _create_bottom_label(text_content: String, anchor_preset: int) -> void:
	var label = Label.new()
	add_child(label)
	label.text = text_content
	
	# 設定統一的視覺樣式
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0)) # 淺灰色，比較淡
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	
	# 設定統一的佈局樣式
	label.set_anchors_and_offsets_preset(anchor_preset, Control.PRESET_MODE_MINSIZE, 20)
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	
	# 根據左右對齊決定成長方向
	if anchor_preset == Control.PRESET_BOTTOM_LEFT:
		label.grow_horizontal = Control.GROW_DIRECTION_END
	else:
		label.grow_horizontal = Control.GROW_DIRECTION_BEGIN

func _on_random_pressed() -> void:
	AudioManager.play("ui_click")
	GameState.reset_level_state()
	GameState.current_mode = GameState.GameMode.RANDOM
	get_tree().change_scene_to_file("res://main.tscn")

func _on_custom_pressed() -> void:
	AudioManager.play("ui_click")
	GameState.reset_level_state()
	get_tree().change_scene_to_file("res://level_select.tscn")

func _on_challenge_pressed() -> void:
	AudioManager.play("ui_click")
	GameState.reset_level_state()
	get_tree().change_scene_to_file("res://challenge_select.tscn")

func _on_editor_pressed() -> void:
	AudioManager.play("ui_click")
	GameState.reset_level_state()
	GameState.current_mode = GameState.GameMode.EDITOR
	get_tree().change_scene_to_file("res://editor.tscn")
