extends Node
# game_state.gd - 全域單例

enum GameMode { RANDOM, CUSTOM, EDITOR, CHALLENGE } # 新增 CHALLENGE 模式

var current_mode: GameMode = GameMode.RANDOM
var selected_level_path: String = ""
var preview_level_data: Dictionary = {}
var is_preview_mode: bool = false

# GitHub 挑戰關卡設定
const GITHUB_USER = "paddy226"
const GITHUB_REPO = "MOVE_BOX"
const GITHUB_API_URL = "https://api.github.com/repos/paddy226/MOVE_BOX/contents/challenges"
const GITHUB_RAW_URL = "https://raw.githubusercontent.com/paddy226/MOVE_BOX/main/challenges/"

# 進度管理
var cleared_challenges: Array = [] # 存放已過關的 level_X 數字
const PROGRESS_FILE = "user://challenge_progress.json"

func _ready() -> void:
	load_progress()

func save_progress(level_id: int) -> void:
	if not level_id in cleared_challenges:
		cleared_challenges.append(level_id)
		var file = FileAccess.open(PROGRESS_FILE, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({"cleared": cleared_challenges}))

func load_progress() -> void:
	if FileAccess.file_exists(PROGRESS_FILE):
		var file = FileAccess.open(PROGRESS_FILE, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var data = json.get_data()
				cleared_challenges = data.get("cleared", [])

var last_camera_rotation: Vector3 = Vector3(-PI/3, 0, 0)
var last_camera_distance: float = 9.0
var current_steps: int = 0
var version_number: String = "v1.0.12"
var author_name: String = "Paddyliu"
