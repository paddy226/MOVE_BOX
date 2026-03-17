extends CanvasLayer
# ui.gd - 管理勝利 UI、重啟邏輯與挑戰模式 NEXT 功能

@onready var victory_panel: Control = $VictoryPanel
@onready var next_btn: Button = $VictoryPanel/VBoxContainer/NextButton
@onready var step_label: Label = $HUD/StepLabel
@onready var flash_rect: ColorRect = $FlashRect

func _ready() -> void:
	victory_panel.visible = false
	flash_rect.visible = false
	flash_rect.modulate.a = 0.0
	step_label.text = "Steps: 0"
	
	_setup_version_label()
	_setup_restart_button()
	_setup_back_button()
	
	# 連接按鈕
	$VictoryPanel/VBoxContainer/RestartButton.pressed.connect(_on_restart_button_pressed)
	next_btn.pressed.connect(_on_next_button_pressed)
	
	var player = get_tree().current_scene.get_node_or_null("Player")
	if player: player.stepped.connect(_on_player_stepped)
	
	var level = get_tree().current_scene.get_node_or_null("Level")
	if level: level.level_cleared.connect(_on_level_cleared)

func _on_level_cleared() -> void:
	victory_panel.visible = true
	
	# 只有在挑戰模式下顯示 NEXT 按鈕
	if GameState.current_mode == GameState.GameMode.CHALLENGE:
		# 儲存 ID 與當前的內容 Hash
		GameState.save_progress(GameState.current_challenge_id, GameState.current_level_sha)
		next_btn.visible = true
	else:
		next_btn.visible = false

func _on_next_button_pressed() -> void:
	AudioManager.play("ui_click")
	# 挑戰模式下一關邏輯
	var next_id = GameState.current_challenge_id + 1
	var next_url = GameState.GITHUB_RAW_URL + "level_" + str(next_id) + ".json"
	
	_download_and_start_next(next_url, next_id)

func _download_and_start_next(url: String, new_id: int) -> void:
	print("[UI] 嘗試連線下一關: ", url)
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_res, code, _hdr, body):
		print("[UI] GitHub 回應碼: ", code)
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				GameState.current_challenge_id = new_id
				GameState.preview_level_data = json.get_data()
				
				# 從快取更新目前的 SHA
				var file_name = "level_" + str(new_id) + ".json"
				GameState.current_level_sha = GameState.github_shas.get(file_name, "")
				
				print("[UI] 下一關載入成功，準備重啟場景. Hash:", GameState.current_level_sha)
				get_tree().reload_current_scene()
		else:
			print("[UI] 找不到下一關或連線失敗。網址: ", url)
			get_tree().change_scene_to_file("res://challenge_select.tscn")
		http.queue_free()
	)
	http.request(url)

# --- 基礎 UI 設定 ---
func _setup_version_label() -> void:
	var hud = $HUD
	var label = Label.new()
	label.name = "VersionLabel"
	hud.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.text = GameState.version_number + " by " + GameState.author_name
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)

func _setup_restart_button() -> void:
	var btn = TextureButton.new()
	btn.name = "ManualRestartButton"
	$HUD.add_child(btn)
	btn.texture_normal = load("res://assets/kenney_game-icons/PNG/White/2x/return.png")
	btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 30)
	btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btn.custom_minimum_size = Vector2(80, 80)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.modulate = Color(1, 1, 1, 0.8)
	btn.pressed.connect(_on_restart_button_pressed)

func _setup_back_button() -> void:
	var btn = TextureButton.new()
	btn.name = "BackButton"
	$HUD.add_child(btn)
	btn.texture_normal = load("res://assets/kenney_game-icons/PNG/White/2x/arrowLeft.png")
	btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 30)
	btn.offset_top = -110
	btn.offset_right = 110
	btn.custom_minimum_size = Vector2(80, 80)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.modulate = Color(1, 1, 1, 0.8)
	btn.pressed.connect(_on_back_button_pressed)

func _on_back_button_pressed() -> void:
	AudioManager.play("ui_click")
	GameState.save_total_steps() # 儲存總步數
	if GameState.is_preview_mode: get_tree().change_scene_to_file("res://editor.tscn")
	elif GameState.current_mode == GameState.GameMode.CHALLENGE: get_tree().change_scene_to_file("res://challenge_select.tscn")
	elif GameState.current_mode == GameState.GameMode.CUSTOM: get_tree().change_scene_to_file("res://level_select.tscn")
	else: get_tree().change_scene_to_file("res://menu.tscn")

func _on_player_stepped(count: int) -> void:
	step_label.text = "Steps: " + str(count)

func _on_restart_button_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	if victory_panel.visible and event.is_action_pressed("ui_accept"):
		if next_btn.visible: _on_next_button_pressed()
		else: _on_restart_button_pressed()
