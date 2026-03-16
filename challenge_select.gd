extends Control
# challenge_select.gd - 支援分頁功能 (每頁 10 個) 的雲端關卡選擇

@onready var list_container = $ScrollContainer/VBoxContainer
@onready var http_request = $HTTPRequest
@onready var status_label = $StatusLabel

# 分頁 UI
@onready var prev_btn = $Pagination/PrevBtn
@onready var next_btn = $Pagination/NextBtn
@onready var page_label = $Pagination/PageLabel

var all_challenge_files = []
var current_page: int = 0
const ITEMS_PER_PAGE: int = 10

func _ready() -> void:
	$BackButton.pressed.connect(func(): get_tree().change_scene_to_file("res://menu.tscn"))
	
	# 強制更新最新進度
	GameState.load_progress()
	
	prev_btn.pressed.connect(_on_prev_pressed)
	next_btn.pressed.connect(_on_next_pressed)
	
	http_request.request_completed.connect(_on_request_completed)
	_fetch_challenge_list()

func _fetch_challenge_list() -> void:
	var url = GameState.GITHUB_API_URL
	status_label.text = "Loading..."
	var err = http_request.request(url)
	if err != OK: status_label.text = "Connection Error!"

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		status_label.text = "GitHub Error: " + str(response_code)
		return
		
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		status_label.text = "JSON Parse Error"
		return
		
	var data = json.get_data()
	if not data is Array:
		status_label.text = "Invalid Format"
		return
		
	# 過濾掉非 JSON 檔案並排序
	all_challenge_files = []
	for f in data:
		if f.name.ends_with(".json"):
			all_challenge_files.append(f)
			
	all_challenge_files.sort_custom(func(a, b): 
		return _extract_number(a.name) < _extract_number(b.name)
	)
	
	status_label.text = ""
	_display_levels()

func _display_levels() -> void:
	for child in list_container.get_children(): child.queue_free()
	
	var total_items = all_challenge_files.size()
	var total_pages = int(ceil(float(total_items) / ITEMS_PER_PAGE))
	if total_pages == 0: total_pages = 1
	
	# 邊界修正
	current_page = clamp(current_page, 0, total_pages - 1)
	
	# 更新 UI 狀態
	page_label.text = str(current_page + 1) + " / " + str(total_pages)
	prev_btn.disabled = (current_page == 0)
	next_btn.disabled = (current_page >= total_pages - 1)
	
	# 計算本頁範圍
	var start_idx = current_page * ITEMS_PER_PAGE
	var end_idx = min(start_idx + ITEMS_PER_PAGE, total_items)
	
	for i in range(start_idx, end_idx):
		var file_info = all_challenge_files[i]
		var level_id = _extract_number(file_info.name)
		_create_level_button(file_info.name, level_id, file_info.download_url)

func _create_level_button(display_name: String, level_id: int, download_url: String) -> void:
	var btn = Button.new()
	btn.text = "LEVEL " + str(level_id)
	btn.custom_minimum_size = Vector2(0, 100)
	btn.add_theme_font_size_override("font_size", 32)
	
	if level_id in GameState.cleared_challenges:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.6, 0.2, 0.8)
		btn.add_theme_stylebox_override("normal", style)
	
	btn.pressed.connect(func(): _on_level_pressed(download_url, level_id))
	list_container.add_child(btn)

func _on_level_pressed(url: String, level_id: int) -> void:
	AudioManager.play("ui_click")
	GameState.current_mode = GameState.GameMode.CHALLENGE
	GameState.current_challenge_id = level_id
	_start_challenge(url)

func _start_challenge(url: String) -> void:
	var downloader = HTTPRequest.new()
	add_child(downloader)
	downloader.request_completed.connect(func(_res, code, _hdr, body):
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				GameState.preview_level_data = json.get_data()
				get_tree().change_scene_to_file("res://main.tscn")
		downloader.queue_free()
	)
	downloader.request(url)

func _on_prev_pressed() -> void:
	AudioManager.play("ui_click")
	current_page -= 1
	_display_levels()

func _on_next_pressed() -> void:
	AudioManager.play("ui_click")
	current_page += 1
	_display_levels()

func _extract_number(s: String) -> int:
	var regex = RegEx.new()
	regex.compile("\\d+")
	var result = regex.search(s)
	if result: return int(result.get_string())
	return 0
