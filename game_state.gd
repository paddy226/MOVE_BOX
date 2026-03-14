extends Node
# game_state.gd - 全域單例

enum GameMode { RANDOM, CUSTOM, EDITOR }

var current_mode: GameMode = GameMode.RANDOM
var selected_level_path: String = ""

var last_camera_rotation: Vector3 = Vector3(-PI/3, 0, 0)
var last_camera_distance: float = 9.0
var current_steps: int = 0
var version_number: String = "v1.0.7"
var author_name: String = "Paddyliu"
