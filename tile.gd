extends Node3D
class_name Tile
# tile.gd - 視覺強化：修正目標點顯示邏輯與閃爍問題

enum TileType { DEFAULT, COLOR_CHANGER, GOAL, OBSTACLE, HOLE }

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
	
	# 基礎重置
	base_mesh.visible = true
	base_mesh.scale.y = 1.0
	base_mesh.position.y = 0.0
	base_mat.transparency = StandardMaterial3D.TRANSPARENCY_DISABLED
	base_mat.emission_enabled = false
	
	# 根據狀態決定 Icon 與 Label 的顯示
	if type == TileType.GOAL and not is_active:
		# 目標已達成狀態
		label.visible = false
		icon.visible = true
		icon.position.y = 0.1 # 確保在地面上方
		base_mat.albedo_color = Color(0.25, 0.25, 0.25) # 變成暗灰色
	else:
		# 一般狀態
		icon.visible = false
		
		match type:
			TileType.DEFAULT:
				label.visible = false
				color_box.visible = false
				base_mat.albedo_color = Color(0.2, 0.2, 0.2)
				
			TileType.COLOR_CHANGER:
				color_box.visible = true
				base_mat.albedo_color = Color(0.2, 0.2, 0.2)
				
				var box_mat = color_box.get_surface_override_material(0).duplicate()
				var transparent_color = target_color
				transparent_color.a = 0.5
				box_mat.albedo_color = transparent_color
				box_mat.emission = target_color
				color_box.set_surface_override_material(0, box_mat)
				
				if uses < 0:
					label.visible = false
				else:
					label.visible = true
					label.text = str(uses)
					label.position.y = 1.0
				
			TileType.GOAL:
				label.visible = true
				color_box.visible = false
				base_mat.albedo_color = target_color
				label.text = str(target_value)
				label.position.y = 0.1 # 提高位置防止閃爍
				
			TileType.OBSTACLE:
				label.visible = false
				color_box.visible = false
				base_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
				base_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
				base_mesh.scale.y = 10.0
				base_mesh.position.y = 0.45
				
			TileType.HOLE:
				label.visible = false
				color_box.visible = false
				icon.visible = false
				base_mesh.visible = false
	
	base_mesh.set_surface_override_material(0, base_mat)

# 讓換色方塊飄浮
func _animate_color_box(up: bool = true) -> void:
	if not is_inside_tree() or type != TileType.COLOR_CHANGER: return
	if active_tween: active_tween.kill()
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
	
	# 先更新視覺 (這會隱藏數字並顯示打勾，地板變灰)
	_update_visuals()

	# 額外的高能閃爍效果
	var mat = base_mesh.get_surface_override_material(0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.5) 
	mat.emission_energy_multiplier = 2.5
	
	var flash_tween = get_tree().create_tween()
	flash_tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	flash_tween.chain().tween_callback(func(): mat.emission_enabled = false)

	AudioManager.play("goal")
	
	var player = get_tree().current_scene.get_node_or_null("Player")
	if player and player.has_method("flash"):
		player.flash()

	if get_parent().has_method("notify_goal_completed"):
		get_parent().notify_goal_completed()

func _become_default() -> void:
	if active_tween: active_tween.kill()
	type = TileType.DEFAULT
	_update_visuals()
