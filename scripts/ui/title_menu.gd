extends Control
## 标题菜单：动态背景（僵尸列队走向围墙）、开始游戏、操作说明、排行榜。

const KINDS: Array[String] = ["walker", "walker", "runner", "walker", "spitter", "exploder", "tank", "walker", "runner", "shielder", "splitter", "screamer", "summoner", "balloon"]
const TOUCH_HELP := """左摇移动，右摇瞄准并开火
右侧按钮：冲刺、换弹、使用道具
点击武器栏换枪，点击道具栏选择或使用
点击右上角暂停
炮塔放置：点击或拖动选格，左摇移动，确认或取消

目标：守住基地，撑过 15 波即胜利
波次之间可在商店买武器、道具和炮塔
精英的克制办法见「僵尸图鉴」"""

@onready var content: Control = %Content
@onready var resume_button: Button = %ResumeButton
@onready var start_button: Button = %StartButton
@onready var boss_rush_button: Button = %BossRushButton
@onready var help_button: Button = %HelpButton
@onready var bestiary_button: Button = %BestiaryButton
@onready var bestiary_panel: Control = %BestiaryPanel
@onready var map_panel: Control = %MapPanel
@onready var prep_panel: Control = %PrepPanel
@onready var clear_button: Button = %ClearButton
@onready var quit_button: Button = %QuitButton
@onready var help_panel: Control = %HelpPanel
@onready var help_text: Label = %HelpText
@onready var help_close: Button = %HelpClose
@onready var hint: Label = %Hint
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
		_walkers.append(_new_walker(randf_range(-20.0, size.x + 20.0)))
	resume_button.pressed.connect(_on_resume)
	start_button.pressed.connect(_on_start)
	boss_rush_button.pressed.connect(_open_map.bind("boss_rush"))
	boss_rush_button.visible = not Harness.automated()
	help_button.pressed.connect(_on_help)
	bestiary_button.pressed.connect(_on_bestiary)
	bestiary_panel.closed.connect(_focus_start)
	map_panel.closed.connect(_focus_start)
	map_panel.chosen.connect(_on_map_chosen)
	prep_panel.closed.connect(func(): map_panel.open())
	prep_panel.confirmed.connect(func(): start_game(Save.map_id))
	clear_button.pressed.connect(_on_clear)
	quit_button.pressed.connect(func(): Sfx.quit_game())
	help_close.pressed.connect(func():
		help_panel.visible = false
		Sfx.play("ui_click")
		_focus_start())
	var touch := Mobile.is_touch()
	for b: Button in [resume_button, start_button, boss_rush_button, help_button, bestiary_button, clear_button, quit_button, help_close]:
		if touch:
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size.y = 22.0
		else:
			b.mouse_entered.connect(func(): Sfx.play("ui_hover"))
	if touch:
		help_text.text = TOUCH_HELP
		hint.position.y -= 4.0
	help_panel.visible = false
	if OS.has_feature("web") or Mobile.is_ios():
		quit_button.visible = false
	resized.connect(_fit_content)
	_fit_content()
	_refresh_scores()
	_refresh_resume()
	_focus_start()
	if Sfx.audio_unlocked:
		Sfx.play_music("menu")
	else:
		click_gate.visible = true
	Harness.on_title_ready(self)


func _fit_content() -> void:
	var inset := Mobile.safe_insets(get_viewport())
	var top: float = inset["top"]
	var bottom: float = inset["bottom"]
	var available_height := size.y - top - bottom
	var available_width := size.x - 2.0 * maxf(inset["left"], inset["right"])
	# 面板四周的留白可延伸到安全区外，内容仍保持在屏幕中央。
	var fit := minf(available_width / (content.size.x - 28.0), available_height / (content.size.y - 12.0))
	var half_height := content.size.y * 0.5
	content.pivot_offset = content.size * 0.5
	content.scale = Vector2.ONE * clampf(fit, 0.1, 1.0)
	var shift := (top - bottom) * 0.5
	content.offset_top = -half_height + shift
	content.offset_bottom = half_height + shift


func _focus_start() -> void:
	if not Mobile.is_touch():
		var first := resume_button if resume_button.visible else start_button
		first.grab_focus()


## 网页版的第一次点击或按键只用来解锁音频，不触发下面的菜单。
func _input(event: InputEvent) -> void:
	if not click_gate.visible:
		return
	var unlock := false
	if event is InputEventScreenTouch:
		# 等手指抬起，拦住同一次点按生成的鼠标事件。
		unlock = not event.pressed and not event.canceled
	elif (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		unlock = event.device != InputEvent.DEVICE_ID_EMULATION
	else:
		return
	get_viewport().set_input_as_handled()
	if unlock:
		click_gate.visible = false
		Sfx.audio_unlocked = true
		Sfx.play_music("menu")


func _new_walker(x: float) -> Dictionary:
	return {
		"kind": KINDS[randi() % KINDS.size()], "x": x, "y": randf_range(150, 262),
		"speed": randf_range(9, 26), "t": randf() * 4.0,
	}


func _refresh_scores() -> void:
	var lines: Array[String] = ["排行榜"]
	if Save.scores.is_empty():
		lines.append("暂无记录\n\n基地被毁或玩家阵亡\n都算失败，撑过 %d 波即胜利" % GameData.MAX_WAVE)
	for i in Save.scores.size():
		var s: Dictionary = Save.scores[i]
		var line := "%d. %d 分  第%d波%s" % [i + 1, int(s["score"]), int(s["wave"]), " 胜" if bool(s.get("victory", false)) else ""]
		# 旧存档没有危险和倍率，当危 0 ×1
		var mult := float(s.get("mult", 1.0))
		if int(s.get("danger", 0)) > 0 or mult > 1.0:
			line += "  危%d %s" % [int(s.get("danger", 0)), GameData.mult_text(mult)]
		lines.append(line)
	if Save.best_endless_wave > 0:
		lines.append("无尽最高：第 %d 波" % Save.best_endless_wave)
	if Save.best_boss_rush_time > 0.0:
		var seconds := int(Save.best_boss_rush_time)
		lines.append("连战最快：%d:%02d" % [floori(Save.best_boss_rush_time / 60.0), seconds % 60])
	scores_label.text = "\n".join(lines)


func _refresh_resume() -> void:
	var summary: Dictionary = {} if Harness.automated() else Save.load_resume_summary()
	resume_button.visible = not summary.is_empty()
	var menu: VBoxContainer = resume_button.get_parent()
	var separation := 2 if resume_button.visible else 5
	if Mobile.is_touch() and resume_button.visible:
		separation = 0
	menu.add_theme_constant_override("separation", separation)
	if resume_button.visible:
		var next_wave := int(summary["wave"]) + 1
		resume_button.text = ("继续无尽第 %d 波" if bool(summary["endless"]) else "继续第 %d 波") % next_wave


func _on_resume() -> void:
	Save.pending_resume = Save.load_resume_run()
	if Save.pending_resume.is_empty():
		_refresh_resume()
		_focus_start()
		return
	Sfx.play("ui_click")
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_start() -> void:
	_open_map("normal")


func _open_map(mode: String) -> void:
	Save.game_mode = mode
	Sfx.play("ui_click")
	map_panel.open()


## 选完地图先进行动准备，确认后才开局。
func _on_map_chosen(id: String) -> void:
	Save.map_id = id
	map_panel.visible = false
	prep_panel.open(id)


func start_game(id: String) -> void:
	Save.clear_resume_run()
	Save.map_id = id
	Save.save_all()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_help() -> void:
	Sfx.play("ui_click")
	help_panel.visible = true
	if not Mobile.is_touch():
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
		if float(w["x"]) > size.x + 20.0:
			w["x"] = -24.0
			w["y"] = randf_range(150, 262)
	_walkers.sort_custom(func(a, b): return float(a["y"]) < float(b["y"]))
	queue_redraw()


func _draw() -> void:
	var width := size.x
	var road_y := size.y - 70.0
	var horizon := road_y - 50.0
	var expanded := Mobile.use_expanded_viewport()
	var first_row := maxi(0, floori(horizon / 16.0)) if expanded else 0
	for y in range(first_row, ceili(size.y / 16.0)):
		for x in ceili(width / 16.0):
			draw_texture(_bg_tiles[_bg_map[(y % 18) * 31 + x % 31]], Vector2(x * 16, y * 16))
	if expanded:
		_draw_skyline(width, horizon)
	draw_rect(Rect2(0, road_y, width, 40), Color("#3c3e46"))
	draw_rect(Rect2(0, road_y - 1, width, 2), Color("#8a887e"))
	draw_rect(Rect2(0, road_y + 39, width, 2), Color("#8a887e"))
	for x in range(((int(_time * 8.0)) % 28) - 28, ceili(width), 28):
		draw_rect(Rect2(x, road_y + 19, 14, 2), Color("#d8c860"))
	for w: Dictionary in _walkers:
		var kind: String = w["kind"]
		var char_size := Art.char_size(kind)
		var tex := Art.frame(kind, Art.DIR_SIDE, int(w["t"]) % Art.FRAMES)
		var pos := Vector2(roundf(float(w["x"])) - char_size.x / 2, roundf(float(w["y"]) + road_y - 200.0) - char_size.y)
		draw_texture(tex, pos)
	# 压暗，突出前景文字
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.03, 0.06, 0.45))
	_draw_heading()


func _draw_skyline(width: float, horizon: float) -> void:
	draw_rect(Rect2(0, 0, width, horizon), Color("#343044"))
	draw_rect(Rect2(0, horizon - 42, width, 42), Color("#504052"))
	for x in range(0, ceili(width), 48):
		var height := 28 + (x / 48 * 13) % 33
		draw_rect(Rect2(x, horizon - height, 41, height), Color("#2d2b37"))
		draw_rect(Rect2(x + 4, horizon - height - 5, 30, 5), Color("#2d2b37"))
		draw_rect(Rect2(x + 8, horizon - height + 7, 3, 5), Color("#6f5447"))
		draw_rect(Rect2(x + 24, horizon - height + 7, 3, 5), Color("#494052"))
	draw_rect(Rect2(0, horizon - 2, width, 2), Color("#242631"))


func _draw_heading() -> void:
	# 标题：12px 像素字放大 4 倍
	var pulse := sin(_time * 3.0) * 0.5 + 0.5
	var title := "僵尸围城"
	var font_size := 12
	var ci := get_canvas_item()
	var tf: Font = Art.font
	var width := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2(roundf(60.0 - width * 0.5), 4.0 + tf.get_ascent(font_size))
	var layout := content.get_transform()
	draw_set_transform(layout.origin, 0.0, 4.0 * content.scale)
	tf.draw_string(ci, at + Vector2(0.75, 0.75), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.08, 0.02, 0.03))
	tf.draw_string(ci, at + Vector2(0.25, 0.25), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.3, 0.04, 0.05))
	tf.draw_string(ci, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.95, 0.22 + pulse * 0.12, 0.14))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	Art.draw_text(self, "ZOMBIE  SIEGE", layout * Vector2(240, 80), 12, Color("#c8c4b8"), 1)
