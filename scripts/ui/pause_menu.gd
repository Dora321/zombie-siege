extends Control
## 暂停菜单。树暂停时自身继续处理输入。

var game: Node

@onready var resume_button: Button = %ResumeButton
@onready var restart_button: Button = %RestartButton
@onready var music_button: Button = %MusicButton
@onready var sfx_button: Button = %SfxButton
@onready var shake_button: Button = %ShakeButton
@onready var quit_button: Button = %QuitButton


func setup(g: Node) -> void:
	game = g
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	resume_button.pressed.connect(close)
	restart_button.pressed.connect(_restart)
	quit_button.pressed.connect(_to_title)
	music_button.pressed.connect(_toggle_music)
	sfx_button.pressed.connect(_toggle_sfx)
	shake_button.pressed.connect(_toggle_shake)
	_refresh_labels()


func open() -> void:
	if get_tree().paused:
		return
	visible = true
	get_tree().paused = true
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_labels()
	resume_button.grab_focus()
	Sfx.play("ui_click")


func close() -> void:
	visible = false
	get_tree().paused = false
	Sfx.play("ui_click")


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause") and not event.is_echo():
		get_viewport().set_input_as_handled()
		close()


func _refresh_labels() -> void:
	music_button.text = "音乐：" + ("开" if Save.music_on else "关")
	sfx_button.text = "音效：" + ("开" if Save.sfx_on else "关")
	shake_button.text = "屏幕震动：" + ("开" if Save.shake_on else "关")


func _toggle_music() -> void:
	Save.music_on = not Save.music_on
	Save.save_all()
	Sfx.refresh_music()
	_refresh_labels()


func _toggle_sfx() -> void:
	Save.sfx_on = not Save.sfx_on
	Save.save_all()
	Sfx.play("ui_click")
	_refresh_labels()


func _toggle_shake() -> void:
	Save.shake_on = not Save.shake_on
	Save.save_all()
	_refresh_labels()


func _restart() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/title.tscn")
