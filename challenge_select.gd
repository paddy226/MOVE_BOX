extends Control
# challenge_select.gd - 支援分頁功能 (每頁 10 個) 的雲端關卡選擇

@onready var list_container = $ScrollContainer/GridContainer
@onready var http_request = $HTTPRequest
@onready var status_label = $StatusLabel

# 分頁 UI
@onready var prev_btn = $Pagination/PrevBtn
@onready var next_btn = $Pagination/NextBtn
@onready var page_label = $Pagination/PageLabel

var all_challenge_files = [] # 統一存放 { "name": "...", "sha": "...", "download_url": "...", "local": bool }
const ITEMS_PER_PAGE: int = 10

var download_queue = []
var is_syncing = false

func _ready() -> void:
	$BackButton.pressed.connect(func(): 
		GameState.reset_level_state()
		GameState.challenge_page = 0
		get_tree().change_scene_to_file("res://menu.tscn")
	)
	
	# 強制更新最新進度
	GameState.load_progress()
	GameState.load_manifest()
	
	prev_btn.pressed.connect(_on_prev_pressed)
	next_btn.pressed.connect(_on_next_pressed)
	
	http_request.request_completed.connect(_on_list_request_completed)
	_fetch_challenge_list()

func _fetch_challenge_list() -> void:
	var url = GameState.GITHUB_API_URL
	status_label.text = "Checking for updates..."
	var err = http_request.request(url)
	if err != OK: 
		_handle_offline_mode("Connection Error!")

func _handle_offline_mode(msg: String) -> void:
	print("[ChallengeSelect] 進入離線模式: ", msg)
	status_label.text = "Offline Mode (Cached)"
	all_challenge_files = []
	for filename in GameState.local_manifest.keys():
		var info = GameState.local_manifest[filename]
		all_challenge_files.append({
			"name": filename,
			"sha": info.get("sha", ""),
			"download_url": info.get("download_url", ""),
			"is_local": true
		})
	_finalize_list_and_display()

func _on_list_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		_handle_offline_mode("GitHub Error: " + str(response_code))
		return
		
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_handle_offline_mode("JSON Parse Error")
		return
		
	var data = json.get_data()
	if not data is Array:
		_handle_offline_mode("Invalid Format")
		return
		
	# 比對與同步
	_sync_with_remote(data)

func _sync_with_remote(remote_data: Array) -> void:
	all_challenge_files = []
	download_queue = []
	
	var remote_filenames = []
	for f in remote_data:
		if f.name.ends_with(".json"):
			remote_filenames.append(f.name)
			var remote_sha = f.get("sha", "")
			var local_info = GameState.local_manifest.get(f.name, {})
			var local_sha = local_info.get("sha", "")
			
			var file_item = {
				"name": f.name,
				"sha": remote_sha,
				"download_url": f.download_url,
				"is_local": false
			}
			
			# 檢查是否需要下載 (本地不存在或 SHA 不同)
			var local_path = GameState.LOCAL_CHALLENGE_DIR + f.name
			if local_sha != remote_sha or not FileAccess.file_exists(local_path):
				download_queue.append(file_item)
			else:
				file_item.is_local = true
				
			all_challenge_files.append(file_item)

	# 移除本地多餘檔案 (不在遠端清單中的)
	var to_remove = []
	for local_f in GameState.local_manifest.keys():
		if not local_f in remote_filenames:
			to_remove.append(local_f)
	
	for r in to_remove:
		var p = GameState.LOCAL_CHALLENGE_DIR + r
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
			print("[Sync] 刪除本地過時檔案: ", r)
		GameState.local_manifest.erase(r)
	
	if to_remove.size() > 0: GameState.save_manifest()

	if download_queue.size() > 0:
		_process_download_queue()
	else:
		_finalize_list_and_display()

func _process_download_queue() -> void:
	if download_queue.is_empty():
		status_label.text = "Sync Complete!"
		GameState.save_manifest()
		_finalize_list_and_display()
		return
		
	is_syncing = true
	var current_item = download_queue[0]
	status_label.text = "Syncing... (" + str(all_challenge_files.size() - download_queue.size() + 1) + "/" + str(all_challenge_files.size()) + ")"
	
	var downloader = HTTPRequest.new()
	add_child(downloader)
	downloader.request_completed.connect(func(_res, code, _hdr, body):
		if code == 200:
			var path = GameState.LOCAL_CHALLENGE_DIR + current_item.name
			var file = FileAccess.open(path, FileAccess.WRITE)
			if file:
				file.store_string(body.get_string_from_utf8())
				file.close()
				# 更新 Manifest
				GameState.local_manifest[current_item.name] = {
					"sha": current_item.sha,
					"download_url": current_item.download_url,
					"id": _extract_number(current_item.name)
				}
				current_item.is_local = true
				print("[Sync] 下載成功: ", current_item.name)
		
		downloader.queue_free()
		download_queue.pop_front()
		_process_download_queue()
	)
	downloader.request(current_item.download_url)

func _finalize_list_and_display() -> void:
	is_syncing = false
	status_label.text = "" # 清除同步狀態文字，避免重疊
	all_challenge_files.sort_custom(func(a, b): 
		return _extract_number(a.name) < _extract_number(b.name)
	)
	_display_levels()

func _display_levels() -> void:
	for child in list_container.get_children(): child.queue_free()
	
	var total_items = all_challenge_files.size()
	var total_pages = int(ceil(float(total_items) / ITEMS_PER_PAGE))
	if total_pages == 0: total_pages = 1
	
	GameState.challenge_page = clamp(GameState.challenge_page, 0, total_pages - 1)
	page_label.text = str(GameState.challenge_page + 1) + " / " + str(total_pages)
	prev_btn.disabled = (GameState.challenge_page == 0)
	next_btn.disabled = (GameState.challenge_page >= total_pages - 1)
	
	var start_idx = GameState.challenge_page * ITEMS_PER_PAGE
	var end_idx = min(start_idx + ITEMS_PER_PAGE, total_items)
	
	for i in range(start_idx, end_idx):
		var file_info = all_challenge_files[i]
		var level_id = _extract_number(file_info.name)
		_create_level_button(file_info, level_id)

func _create_level_button(file_info: Dictionary, level_id: int) -> void:
	var btn = Button.new()
	btn.text = "LEVEL " + str(level_id)
	btn.custom_minimum_size = Vector2(300, 100)
	btn.add_theme_font_size_override("font_size", 32)
	
	var id_key = str(level_id)
	var local_hash = GameState.cleared_challenges.get(id_key, "")
	var is_cleared = (local_hash != "" and local_hash == file_info.sha)
	
	if is_cleared:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.6, 0.2, 0.8) 
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		
	if not file_info.is_local:
		btn.disabled = true # 正在同步中或遺失且離線
		btn.text += " (Syncing...)"
		
	btn.pressed.connect(func(): _on_level_pressed(file_info, level_id))
	list_container.add_child(btn)

func _on_level_pressed(file_info: Dictionary, level_id: int) -> void:
	AudioManager.play("ui_click")
	GameState.current_mode = GameState.GameMode.CHALLENGE
	GameState.current_challenge_id = level_id
	GameState.current_level_sha = file_info.sha
	GameState.update_challenge_page_by_id(level_id)
	
	# 從本地讀取
	var local_path = GameState.LOCAL_CHALLENGE_DIR + file_info.name
	if FileAccess.file_exists(local_path):
		var file = FileAccess.open(local_path, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			GameState.preview_level_data = json.get_data()
			get_tree().change_scene_to_file("res://main.tscn")
		file.close()
	else:
		# 理論上同步完不應該發生，但作為保險：
		status_label.text = "Error: Local file missing!"

func _on_prev_pressed() -> void:
	AudioManager.play("ui_click")
	GameState.challenge_page -= 1
	_display_levels()

func _on_next_pressed() -> void:
	AudioManager.play("ui_click")
	GameState.challenge_page += 1
	_display_levels()

func _extract_number(s: String) -> int:
	var regex = RegEx.new()
	regex.compile("\\d+")
	var result = regex.search(s)
	if result: return int(result.get_string())
	return 0
