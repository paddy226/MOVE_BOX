extends Node
# game_state.gd - 全域單例，除錯強化版

enum GameMode { RANDOM, CUSTOM, EDITOR, CHALLENGE }

var current_mode: GameMode = GameMode.RANDOM
var selected_level_path: String = ""
var preview_level_data: Dictionary = {}
var is_preview_mode: bool = false
var current_challenge_id: int = -1
var challenge_page: int = 0 # 記錄挑戰模式當前分頁

const GITHUB_USER = "paddy226"
const GITHUB_REPO = "MOVE_BOX"
const GITHUB_API_URL = "https://api.github.com/repos/paddy226/MOVE_BOX/contents/challenges"
const GITHUB_RAW_URL = "https://raw.githubusercontent.com/paddy226/MOVE_BOX/master/challenges/"

# { "level_id_string": "content_sha_hash" }
var cleared_challenges: Dictionary = {} 
var total_steps: int = 0
const PROGRESS_FILE = "user://challenge_progress.json"

var last_camera_rotation: Vector3 = Vector3(-PI/3, 0, 0)
var last_camera_distance: float = 9.0
var current_steps: int = 0
var current_level_sha: String = "" # 暫存目前關卡的 SHA
var github_shas: Dictionary = {}   # 快取從 API 抓到的 { "level_1.json": "sha..." }

var version_number: String = "v1.0.21"
var author_name: String = "Paddyliu"

func update_challenge_page_by_id(level_id: int) -> void:
	# 假設每頁 10 關 (與 challenge_select.gd 保持一致)
	# Level 1-10 -> Page 0
	# Level 11-20 -> Page 1
	challenge_page = (level_id - 1) / 10
	print("[GameState] 自動同步頁碼至: ", challenge_page + 1, " (Level ID: ", level_id, ")")

func get_data_hash(data: Dictionary) -> String:
	var s = JSON.stringify(data)
	return s.md5_text()

func reset_level_state() -> void:
	print("[GameState] 重設關卡狀態")
	preview_level_data = {}
	selected_level_path = ""
	current_challenge_id = -1
	current_level_sha = "" # 清除 SHA
	is_preview_mode = false
	current_steps = 0

func _ready() -> void:
	print("--- GameState 初始化 ---")
	load_progress()

func save_progress(level_id: int, content_sha: String) -> void:
	var id_key = str(level_id)
	cleared_challenges[id_key] = content_sha
	_save_to_disk()
	print("[GameState] 已過關:", level_id, " Hash:", content_sha)

func save_total_steps() -> void:
	_save_to_disk()

func _save_to_disk() -> void:
	var data = {
		"cleared_dict": cleared_challenges,
		"total_steps": total_steps
	}
	var file = FileAccess.open(PROGRESS_FILE, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(data)
		file.store_string(json_string)
		file.close()
	else:
		print("[GameState] 儲存失敗！無法寫入:", PROGRESS_FILE)

func load_progress() -> void:
	if not FileAccess.file_exists(PROGRESS_FILE):
		print("[GameState] 進度檔不存在:", PROGRESS_FILE)
		cleared_challenges = {}
		total_steps = 0
		return
		
	var file = FileAccess.open(PROGRESS_FILE, FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(json_text) == OK:
			var data = json.get_data()
			# 讀取總步數
			total_steps = int(data.get("total_steps", 0))
			
			# 支援舊版本轉移或新版本讀取
			if data.has("cleared_dict"):
				cleared_challenges = Dictionary(data["cleared_dict"])
				print("[GameState] 載入字典進度成功，總步數:", total_steps)
			elif data.has("cleared"):
				cleared_challenges = {}
				print("[GameState] 偵測到舊版進度，重置為 Hash 模式")
		else:
			print("[GameState] 解析進度失敗:", json.get_error_message())
