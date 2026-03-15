extends Node
# game_state.gd - 全域單例

enum GameMode { RANDOM, CUSTOM, EDITOR }

var current_mode: GameMode = GameMode.RANDOM
var selected_level_path: String = ""
var preview_level_data: Dictionary = {}
var is_preview_mode: bool = false # 新增：是否處於預覽模式
 # 新增：編輯器預覽資料

var last_camera_rotation: Vector3 = Vector3(-PI/3, 0, 0)
var last_camera_distance: float = 9.0
var current_steps: int = 0
var version_number: String = "v1.0.11"
var author_name: String = "Paddyliu"
