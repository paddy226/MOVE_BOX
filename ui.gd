extends CanvasLayer
# ui.gd - 管理勝利 UI 與重啟邏輯

@onready var victory_panel: Control = $VictoryPanel
@onready var step_label: Label = $HUD/StepLabel
@onready var flash_rect: ColorRect = $FlashRect

func _ready() -> void:
	victory_panel.visible = false
	flash_rect.visible = false
	flash_rect.modulate.a = 0.0 # 初始透明
	step_label.text = "Steps: 0"
	
	# 顯示版本號 (動態建立以確保出現在右下角)
	_setup_version_label()
	
	# 連接按鈕信號
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
		
		# 設定文字樣式與對齊
		version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		version_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		
		# 重要：設定水平生長方向為「起始端 (左)」，這樣文字變長會往左邊長
		version_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		
		# 設定錨點為右下角，並增加 20 像素的邊距
		version_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
		
		# 加上黑邊，確保在任何背景都看得見
		version_label.add_theme_color_override("font_outline_color", Color.BLACK)
		version_label.add_theme_constant_override("outline_size", 4)
	
	version_label.text = GameState.version_number
	version_label.move_to_front()

func _on_player_stepped(count: int) -> void:
	step_label.text = "Steps: " + str(count)

func flash_screen() -> void:
	flash_rect.visible = true
	flash_rect.modulate.a = 0.5 # 閃爍強度
	var tween = get_tree().create_tween()
	tween.tween_property(flash_rect, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func(): flash_rect.visible = false)

func _on_level_cleared() -> void:
	# 顯示勝利面板
	victory_panel.visible = true
	# 暫停遊戲邏輯 (可選)
	# get_tree().paused = true

func _on_restart_button_pressed() -> void:
	# 重啟關卡
	# get_tree().paused = false
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	if victory_panel.visible and event.is_action_pressed("ui_accept"):
		_on_restart_button_pressed()
