extends Node
# game_state.gd - 全域單例 (Autoload)，存放跨場景或重啟後的資料

var last_camera_rotation: Vector3 = Vector3(-PI/3, 0, 0) # 預設俯視 60 度
var last_camera_distance: float = 9.0 # 預設距離 9
var current_steps: int = 0
var version_number: String = "v1.0.6"
var author_name: String = "Paddyliu"
