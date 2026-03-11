extends Node3D
class_name Tile
# tile.gd - 視覺強化：目標點(平面) vs 換色點(立體半透明)

enum TileType { DEFAULT, COLOR_CHANGER, GOAL, OBSTACLE }

@export var type: TileType = TileType.DEFAULT
@export var target_color: Color = Color.WHITE
@export var target_value: int = 0
@export var uses: int = -1 

var is_active: bool = true
var grid_pos: Vector2i
var active_tween: Tween

@onready var label: Label3D = $Label3D
@onready var base_mesh: MeshInstance3D = $Base
@onready var color_box: MeshInstance3D = $ColorBox
@onready var icon: Sprite3D = $Icon

func _ready() -> void:
	_update_visuals()
	if type == TileType.COLOR_CHANGER:
		_animate_color_box()

# 更新格子的視覺顯示
func _update_visuals() -> void:
	if not is_inside_tree(): return
	
	# 初始化或獲取地板材質
	var base_mat = base_mesh.get_surface_override_material(0)
	base_mat = base_mat.duplicate() if base_mat else StandardMaterial3D.new()
	
	match type:
		TileType.DEFAULT:
			label.visible = false
			color_box.visible = false
			base_mat.albedo_color = Color(0.2, 0.2, 0.2)
			
		TileType.COLOR_CHANGER:
			color_box.visible = true
			base_mat.albedo_color = Color(0.2, 0.2, 0.2) # 地板保持深灰
			
			# 設定半透明方塊的顏色
			var box_mat = color_box.get_surface_override_material(0).duplicate()
			var transparent_color = target_color
			transparent_color.a = 0.5 # 設定透明度
			box_mat.albedo_color = transparent_color
			box_mat.emission = target_color # 讓它微微發光
			color_box.set_surface_override_material(0, box_mat)
			
			if uses < 0:
				label.visible = false
			else:
				label.visible = true
				label.text = str(uses)
				label.position.y = 1.0 # 數字浮在方塊上方
			
		TileType.GOAL:
			label.visible = true
			color_box.visible = false
			base_mat.albedo_color = target_color # 目標點就是彩色地板
			label.text = str(target_value)
			label.position.y = 0.01
			
		TileType.OBSTACLE:
			label.visible = false
			color_box.visible = false
			base_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
			base_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8) # 更加不透明
			# 讓障礙物變高
			base_mesh.scale.y = 10.0 # 變成實心的方塊高度
			base_mesh.position.y = 0.45
	
	base_mesh.set_surface_override_material(0, base_mat)

# 讓換色方塊飄浮 (改用遞迴式 Tween 避開 Infinite loop 警告)
func _animate_color_box(up: bool = true) -> void:
	if not is_inside_tree() or type != TileType.COLOR_CHANGER: return
	
	if active_tween:
		active_tween.kill()
		
	active_tween = get_tree().create_tween()
	var target_y = 0.4 if up else 0.2
	
	active_tween.tween_property(color_box, "position:y", target_y, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	active_tween.finished.connect(func(): _animate_color_box(not up))

# 當箱子踩上這格時被呼叫
func on_stepped(player: Node3D) -> void:
	if not is_active: return
	
	match type:
		TileType.COLOR_CHANGER:
			if player.current_color == target_color: return
			if uses != 0:
				player.change_color(target_color)
				AudioManager.play("color_change")
				if uses > 0:
					uses -= 1
					if uses == 0: _become_default()
					else: _update_visuals()
		TileType.GOAL:
			if player.current_bottom_value == target_value and player.current_color == target_color:
				_complete_goal()

func _complete_goal() -> void:
	is_active = false

	# 地板變為暗灰色，並啟動高能閃爍效果
	var mat = base_mesh.get_surface_override_material(0).duplicate()
	mat.albedo_color = Color(0.25, 0.25, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.5) # 暖白光
	mat.emission_energy_multiplier = 2.5 # 進一步調低能量
	base_mesh.set_surface_override_material(0, mat)

	# 隱藏數字，顯示圖案
	label.visible = false
	icon.visible = true

	# 質感閃爍動畫：先保持一瞬間再迅速衰減
	var flash_tween = get_tree().create_tween()
	flash_tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	flash_tween.chain().tween_callback(func(): mat.emission_enabled = false)

	AudioManager.play("goal")
	
	# 通知玩家也閃爍一下 (增強反饋)
	var player = get_tree().current_scene.get_node_or_null("Player")
	if player and player.has_method("flash"):
		player.flash()

	if get_parent().has_method("notify_goal_completed"):
		get_parent().notify_goal_completed()

	print("座標 ", grid_pos, " 的目標已達成！")

func _become_default() -> void:
	if active_tween:
		active_tween.kill()
	type = TileType.DEFAULT
	_update_visuals()
