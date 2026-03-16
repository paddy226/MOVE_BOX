extends Control
# challenge_select.gd - 從 GitHub 取得關卡並顯示

@onready var list_container = $ScrollContainer/VBoxContainer
@onready var http_request = $HTTPRequest
@onready var status_label = $StatusLabel

var all_challenge_files = [] # 存放 GitHub 回傳的檔案資訊

func _ready() -> void:
	$BackButton.pressed.connect(func(): get_tree().change_scene_to_file("res://menu.tscn"))
	
	http_request.request_completed.connect(_on_request_completed)
	
	_fetch_challenge_list()

func _fetch_challenge_list() -> void:
	var url = GameState.GITHUB_API_URL
	status_label.text = "Fetching from: " + url
	print("正在嘗試連線 GitHub API: ", url)
	var err = http_request.request(url)
	if err != OK:
		status_label.text = "Connection Error!"

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	print("GitHub 回應代碼: ", response_code)
	if response_code != 200:
		status_label.text = "GitHub Error: " + str(response_code) + "\nCheck if Repo is Public and path is correct."
		print("回應內容: ", body.get_string_from_utf8())
		return
		
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		status_label.text = "JSON Parse Error"
		return
		
	var data = json.get_data()
	if not data is Array:
		status_label.text = "Invalid Data Format"
		return
		
	all_challenge_files = data
	status_label.text = "" # 隱藏狀態文字
	_display_levels()

func _display_levels() -> void:
	for child in list_container.get_children(): child.queue_free()
	
	# 依照檔名排序 (level_1, level_2...)
	all_challenge_files.sort_custom(func(a, b): 
		var num_a = _extract_number(a.name)
		var num_b = _extract_number(b.name)
		return num_a < num_b
	)
	
	for file_info in all_challenge_files:
		var file_name = file_info.get("name", "")
		if not file_name.ends_with(".json"): continue
		
		var level_id = _extract_number(file_name)
		_create_level_button(file_name, level_id, file_info.get("download_url", ""))

func _create_level_button(display_name: String, level_id: int, download_url: String) -> void:
	var btn = Button.new()
	btn.text = display_name.get_basename().replace("_", " ").to_upper()
	btn.custom_minimum_size = Vector2(0, 100)
	btn.add_theme_font_size_override("font_size", 32)
	
	# 根據進度顯示顏色
	if level_id in GameState.cleared_challenges:
		# 已過關：綠色系
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.6, 0.2, 0.8)
		btn.add_theme_stylebox_override("normal", style)
	
	btn.pressed.connect(func(): _on_level_pressed(download_url, level_id))
	list_container.add_child(btn)

func _on_level_pressed(url: String, _level_id: int) -> void:
	AudioManager.play("ui_click")
	# 我們需要一個專門的邏輯來下載 JSON 內容並進入遊戲
	# 這裡我暫時將邏輯存在 GameState，並跳轉至下載畫面或直接進入
	GameState.current_mode = GameState.GameMode.CHALLENGE
	# 這裡我們可以直接用另一個 HTTPRequest 或是傳遞 URL
	_start_challenge(url)

func _start_challenge(url: String) -> void:
	# 下載具體關卡內容
	var downloader = HTTPRequest.new()
	add_child(downloader)
	downloader.request_completed.connect(func(res, code, hdr, body):
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				GameState.preview_level_data = json.get_data()
				get_tree().change_scene_to_file("res://main.tscn")
		downloader.queue_free()
	)
	downloader.request(url)

func _extract_number(s: String) -> int:
	var regex = RegEx.new()
	regex.compile("\\d+")
	var result = regex.search(s)
	if result:
		return int(result.get_string())
	return 0
