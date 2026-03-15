extends CanvasLayer
# ui.gd - 管理勝利 UI、重啟邏輯與返回選單

@onready var victory_panel: Control = $VictoryPanel
@onready var step_label: Label = $HUD/StepLabel
@onready var flash_rect: ColorRect = $FlashRect

func _ready() -> void:
	victory_panel.visible = false
	flash_rect.visible = false
	flash_rect.modulate.a = 0.0
	step_label.text = "Steps: 0"
	
	# 顯示版本號
	_setup_version_label()
	
	# 設定重新開始按鈕 (右上)
	_setup_restart_button()
	
	# 設定返回選單按鈕 (左下)
	_setup_back_button()
	
	# 連接勝利面板的按鈕
	var restart_btn = $VictoryPanel/VBoxContainer/RestartButton
	restart_btn.pressed.connect(_on_restart_button_pressed)
	
	# 連接 Player 的信號
	var player = get_tree().current_scene.get_node_or_null("Player")
	if player:
		player.stepped.connect(_on_player_stepped)
	
	# 連接 Level 的信號
	var level = get_tree().current_scene.get_node_or_null("Level")
	if level:
		level.level_cleared.connect(_on_level_cleared)

func _setup_version_label() -> void:
	var hud = get_node_or_null("HUD")
	if not hud: return
	
	var version_label = hud.get_node_or_null("VersionLabel")
	if not version_label:
		version_label = Label.new()
		version_label.name = "VersionLabel"
		hud.add_child(version_label)
		version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		version_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		version_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		version_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
		version_label.add_theme_color_override("font_outline_color", Color.BLACK)
		version_label.add_theme_constant_override("outline_size", 4)
	
	version_label.text = GameState.version_number + " by " + GameState.author_name
	version_label.move_to_front()

func _setup_restart_button() -> void:
	var hud = get_node_or_null("HUD")
	if not hud: return
	
	var restart_btn = hud.get_node_or_null("ManualRestartButton")
	if not restart_btn:
		restart_btn = TextureButton.new()
		restart_btn.name = "ManualRestartButton"
		hud.add_child(restart_btn)
		var icon_tex = load("res://assets/kenney_game-icons/PNG/White/2x/return.png")
		restart_btn.texture_normal = icon_tex
		restart_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 30)
		restart_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		restart_btn.custom_minimum_size = Vector2(64, 64)
		restart_btn.ignore_texture_size = true
		restart_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		restart_btn.modulate = Color(1, 1, 1, 0.8)
		restart_btn.pressed.connect(_on_restart_button_pressed)
	restart_btn.move_to_front()

func _setup_back_button() -> void:
	var hud = get_node_or_null("HUD")
	if not hud: return
	
	var back_btn = hud.get_node_or_null("BackButton")
	if not back_btn:
		back_btn = TextureButton.new()
		back_btn.name = "BackButton"
		hud.add_child(back_btn)
		
		# 載入左箭頭圖示
		var icon_tex = load("res://assets/kenney_game-icons/PNG/White/2x/arrowLeft.png")
		back_btn.texture_normal = icon_tex
		
		# 設定位置 (左下角，留 30 像素邊距)
		back_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 30)
		
		# 調整大小
		back_btn.custom_minimum_size = Vector2(64, 64)
		back_btn.ignore_texture_size = true
		back_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		
		# 設定半透明白色
		back_btn.modulate = Color(1, 1, 1, 0.8)
		
		# 連接按下事件
		back_btn.pressed.connect(_on_back_button_pressed)
	back_btn.move_to_front()

func _on_back_button_pressed() -> void:
	AudioManager.play("ui_click")
	# 智慧導向：如果是預覽模式，回編輯器；否則回選單
	if GameState.is_preview_mode:
		get_tree().change_scene_to_file("res://editor.tscn")
	else:
		get_tree().change_scene_to_file("res://menu.tscn")

func _on_player_stepped(count: int) -> void:
	step_label.text = "Steps: " + str(count)

func flash_screen() -> void:
	flash_rect.visible = true
	flash_rect.modulate.a = 0.5
	var tween = get_tree().create_tween()
	tween.tween_property(flash_rect, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func(): flash_rect.visible = false)

func _on_level_cleared() -> void:
	victory_panel.visible = true

func _on_restart_button_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	if victory_panel.visible and event.is_action_pressed("ui_accept"):
		_on_restart_button_pressed()
