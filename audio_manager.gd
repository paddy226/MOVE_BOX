extends Node
# audio_manager.gd - 全域音效管理

var sounds = {
	"roll": preload("res://assets/kenney_interface-sounds/Audio/click_002.ogg"),
	"color_change": preload("res://assets/kenney_interface-sounds/Audio/switch_001.ogg"),
	"goal": preload("res://assets/kenney_interface-sounds/Audio/confirmation_001.ogg"),
	"win": preload("res://assets/kenney_interface-sounds/Audio/drop_004.ogg"),
	"error": preload("res://assets/kenney_interface-sounds/Audio/glass_006.ogg"),
	"ui_click": preload("res://assets/kenney_interface-sounds/Audio/click_001.ogg")
}

func play(sound_name: String) -> void:
	if sounds.has(sound_name):
		var player = AudioStreamPlayer.new()
		add_child(player)
		player.stream = sounds[sound_name]
		player.play()
		player.finished.connect(func(): player.queue_free())
