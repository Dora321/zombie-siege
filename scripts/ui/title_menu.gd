extends Control
## 标题菜单：动态背景（僵尸列队走向围墙）、开始游戏、操作说明、排行榜。

const KINDS: Array[String] = ["walker", "walker", "runner", "walker", "spitter", "exploder", "tank", "walker", "runner", "shielder", "splitter", "screamer", "summoner", "balloon"]

@onready var start_button: Button = %StartButton
@onready var help_button: Button = %HelpButton
@onready var bestiary_button: Button = %BestiaryButton
@onready var bestiary_panel: Control = %BestiaryPanel
@onready var map_panel: Control = %MapPanel
@onready var clear_button: Button = %ClearButton
@onready var quit_button: Button = %QuitButton
@onready var help_panel: Control = %HelpPanel
@onready var help_close: Button = %HelpClose
@onready var scores_label: Label = %ScoresLabel
@onready var click_gate: Control = %ClickGate
@onready var click_label: Label = %ClickLabel

var _bg_tiles: Array[Texture2D] = []
var _bg_map: PackedInt32Array = PackedInt32Array()
var _walkers: Array = []
var _time := 0.0
var _confirm_clear := false


func _ready() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for img: Image in Art.tiles["grass"]:
		_bg_tiles.append(ImageTexture.create_from_image(img))
	_bg_map.resize(31 * 18)
	for i in _bg_map.size():
		_bg_map[i] = randi() % _bg_tiles.size()
	for i in 12:
		_walkers.append(_new_walker(randf_range(-20, 500)))
	start_button.pressed.connect(_on_start)
	help_button.pressed.connect(_on_help)
	bestiary_button.pressed.connect(_on_bestiary)
	bestiary_panel.closed.connect(func(): start_button.grab_focus())
	map_panel.closed.connect(func(): start_button.grab_focus())
	map_panel.chosen.connect(start_game)
	clear_button.pressed.connect(_on_clear)
	quit_button.pressed.connect(func(): Sfx.quit_game())
	help_close.pressed.connect(func():
		help_panel.visible = false
		Sfx.play("ui_click")
		start_button.grab_focus())
	for b: Button in [start_button, help_button, bestiary_button, clear_button, quit_button, help_close]:
		b.mouse_entered.connect(func(): Sfx.play("ui_hover"))
	help_panel.visible = false
	if OS.has_feature("web"):
		quit_button.visible = false
	_refresh_scores()
	start_button.grab_focus()
	if Sfx.audio_unlocked:
		Sfx.play_music("menu")
	else:
		click_gate.visible = true
	Harness.on_title_ready(self)


## 网页版的第一次点击或按键只用来解锁音频，不触发下面的菜单。
func _input(event: InputEvent) -> void:
	if not click_gate.visible:
		return
	if (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		get_viewport().set_input_as_handled()
		click_gate.visible = false
		Sfx.audio_unlocked = true
		Sfx.play_music("menu")


func _new_walker(x: float) -> Dictionary:
	return {
		"kind": KINDS[randi() % KINDS.size()], "x": x, "y": randf_range(150, 262),
		"speed": randf_range(9, 26), "t": randf() * 4.0,
	}


func _refresh_scores() -> void:
	if Save.scores.is_empty():
		scores_label.text = "排行榜\n暂无记录\n\n基地被毁或玩家阵亡\n都算失败，撑过 %d 波即胜利" % GameData.MAX_WAVE
		return
	var lines: Array[String] = ["排行榜"]
	for i in Save.scores.size():
		var s: Dictionary = Save.scores[i]
		lines.append("%d. %d 分  第%d波%s" % [i + 1, int(s["score"]), int(s["wave"]), " 胜" if bool(s.get("victory", false)) else ""])
	scores_label.text = "\n".join(lines)


func _on_start() -> void:
	Sfx.play("ui_click")
	map_panel.open()


func start_game(id: String) -> void:
	Save.map_id = id
	Save.save_all()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_help() -> void:
	Sfx.play("ui_click")
	help_panel.visible = true
	help_close.grab_focus()


func _on_bestiary() -> void:
	Sfx.play("ui_click")
	bestiary_panel.open()


func _on_clear() -> void:
	Sfx.play("ui_click")
	if not _confirm_clear:
		_confirm_clear = true
		clear_button.text = "再点一次确认清除"
		return
	Save.clear_scores()
	_confirm_clear = false
	clear_button.text = "清除记录"
	_refresh_scores()


func _process(dt: float) -> void:
	_time += dt
	click_label.visible = fmod(_time, 1.0) < 0.65
	for w: Dictionary in _walkers:
		w["x"] = float(w["x"]) + float(w["speed"]) * dt
		w["t"] = float(w["t"]) + float(w["speed"]) * dt * 0.2
		if float(w["x"]) > 500.0:
			w["x"] = -24.0
			w["y"] = randf_range(150, 262)
	_walkers.sort_custom(func(a, b): return float(a["y"]) < float(b["y"]))
	queue_redraw()


func _draw() -> void:
	for y in 18:
		for x in 31:
			draw_texture(_bg_tiles[_bg_map[y * 31 + x]], Vector2(x * 16, y * 16))
	# 一条路
	draw_rect(Rect2(0, 200, 480, 40), Color("#3c3e46"))
	draw_rect(Rect2(0, 199, 480, 2), Color("#8a887e"))
	draw_rect(Rect2(0, 239, 480, 2), Color("#8a887e"))
	for x in range(((int(_time * 8.0)) % 28) - 28, 480, 28):
		draw_rect(Rect2(x, 219, 14, 2), Color("#d8c860"))
	for w: Dictionary in _walkers:
		var kind: String = w["kind"]
		var size := Art.char_size(kind)
		var tex := Art.frame(kind, Art.DIR_SIDE, int(w["t"]) % Art.FRAMES)
		var pos := Vector2(roundf(float(w["x"])) - size.x / 2, roundf(float(w["y"])) - size.y)
		draw_texture(tex, pos)
	# 压暗，突出前景文字
	draw_rect(Rect2(0, 0, 480, 270), Color(0.05, 0.03, 0.06, 0.45))
	# 标题：12px 像素字放大 4 倍
	var pulse := sin(_time * 3.0) * 0.5 + 0.5
	var title := "僵尸围城"
	var size := 12
	var ci := get_canvas_item()
	var tf: Font = Art.font
	var width := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(roundf(60.0 - width * 0.5), 4.0 + tf.get_ascent(size))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(4, 4))
	tf.draw_string(ci, at + Vector2(0.75, 0.75), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.08, 0.02, 0.03))
	tf.draw_string(ci, at + Vector2(0.25, 0.25), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.3, 0.04, 0.05))
	tf.draw_string(ci, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.95, 0.22 + pulse * 0.12, 0.14))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	Art.draw_text(self, "ZOMBIE  SIEGE", Vector2(240, 80), 12, Color("#c8c4b8"), 1)
