extends Node
# game_state.gd - 全域單例，除錯強化版

enum GameMode { RANDOM, CUSTOM, EDITOR, CHALLENGE }

var current_mode: GameMode = GameMode.RANDOM
var selected_level_path: String = ""
var preview_level_data: Dictionary = {}
var is_preview_mode: bool = false
var current_challenge_id: int = -1

const GITHUB_USER = "paddy226"
const GITHUB_REPO = "MOVE_BOX"
const GITHUB_API_URL = "https://api.github.com/repos/paddy226/MOVE_BOX/contents/challenges"
const GITHUB_RAW_URL = "https://raw.githubusercontent.com/paddy226/MOVE_BOX/master/challenges/"

var cleared_challenges: Array = []
const PROGRESS_FILE = "user://challenge_progress.json"

var last_camera_rotation: Vector3 = Vector3(-PI/3, 0, 0)
var last_camera_distance: float = 9.0
var current_steps: int = 0
var version_number: String = "v1.0.14"
var author_name: String = "Paddyliu"

func _ready() -> void:
	print("--- GameState 初始化 ---")
	load_progress()

func save_progress(level_id: int) -> void:
	if not level_id in cleared_challenges:
		cleared_challenges.append(level_id)
		
	var data = {"cleared": cleared_challenges}
	var file = FileAccess.open(PROGRESS_FILE, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(data)
		file.store_string(json_string)
		file.close()
		print("[GameState] 已過關:", level_id, " 目前紀錄:", cleared_challenges)
		print("[GameState] 儲存路徑:", ProjectSettings.globalize_path(PROGRESS_FILE))
	else:
		print("[GameState] 儲存失敗！無法寫入:", PROGRESS_FILE)

func load_progress() -> void:
	if not FileAccess.file_exists(PROGRESS_FILE):
		print("[GameState] 進度檔不存在:", PROGRESS_FILE)
		cleared_challenges = []
		return
		
	var file = FileAccess.open(PROGRESS_FILE, FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		file.close()
		print("[GameState] 讀取進度文字:", json_text)
		
		var json = JSON.new()
		if json.parse(json_text) == OK:
			var data = json.get_data()
			if data.has("cleared"):
				cleared_challenges = Array(data["cleared"])
				print("[GameState] 載入成功，已過關關卡:", cleared_challenges)
		else:
			print("[GameState] 解析進度失敗:", json.get_error_message())
