extends Control
## 僵尸图鉴：标题界面打开，分页展示所有敌人的造型（播放走路动画）、特点和对策。

const PAGES: Array = [
	{"title": "普通僵尸", "kinds": ["walker", "runner", "tank", "exploder", "spitter"]},
	{"title": "精英僵尸（一）", "kinds": ["stalker", "shielder", "splitter", "splitling"]},
	{"title": "精英僵尸（二）", "kinds": ["summoner", "imp", "screamer", "balloon"]},
	{"title": "Boss（一）", "kinds": ["vanguard", "boss"]},
	{"title": "Boss（二）", "kinds": ["colossus", "plague"]},
	{"title": "Boss（三）", "kinds": ["graveborn", "burrowlord"]},
	{"title": "Boss（四）", "kinds": ["mirror", "overlord"]},
]
const ROW_H := 50
const TOP := 26
const TEXT_X := 66

@onready var prev_button: Button = %BestiaryPrev
@onready var next_button: Button = %BestiaryNext
@onready var close_button: Button = %BestiaryClose

var page := 0
var _time := 0.0


func _ready() -> void:
	visible = false
	prev_button.pressed.connect(func(): turn(-1))
	next_button.pressed.connect(func(): turn(1))
	close_button.pressed.connect(close)
	for b: Button in [prev_button, next_button, close_button]:
		b.mouse_entered.connect(func(): Sfx.play("ui_hover"))


func open() -> void:
	visible = true
	page = 0
	close_button.grab_focus()
	queue_redraw()


func close() -> void:
	Sfx.play("ui_click")
	visible = false
	closed.emit()


signal closed


func turn(step: int) -> void:
	Sfx.play("ui_click")
	page = posmod(page + step, PAGES.size())
	queue_redraw()


func _process(dt: float) -> void:
	if visible:
		_time += dt
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.05, 0.08, 0.97))
	draw_rect(Rect2(Vector2.ZERO, size), Color("#8a6a3a"), false, 1.0)
	var spec: Dictionary = PAGES[page]
	Art.draw_text(self, "僵尸图鉴 · %s（%d/%d）" % [spec["title"], page + 1, PAGES.size()], Vector2(size.x * 0.5, 6), 12, Color(1, 0.82, 0.45), 1)
	var y := TOP
	var kinds: Array = spec["kinds"]
	var row: int = (int(size.y) - TOP - 26) / kinds.size()
	for kind: String in kinds:
		_draw_row(kind, y, row)
		y += row


func _draw_row(kind: String, y: int, row: int) -> void:
	var stat: Dictionary = GameData.ZOMBIES[kind]
	var char_size := Art.char_size(kind)
	var frame_i := int(_time * 5.0) % Art.FRAMES
	var at := Vector2(34 - char_size.x / 2, y + row - char_size.y - 2)
	draw_texture(Art.frame(kind, Art.DIR_DOWN, frame_i), at.round())
	var name_col := Color("#ff9070") if GameData.is_boss(kind) else Color("#f0d080")
	Art.draw_text(self, String(stat["name"]), Vector2(TEXT_X, y), 12, name_col)
	if GameData.BOSSES.has(kind):
		var boss: Dictionary = GameData.BOSSES[kind]
		var lines := ""
		var phases: Array = boss["phases"]
		for i in phases.size():
			lines += ("  " if i > 0 else "") + "%d.%s" % [i + 1, phases[i]["name"]]
		Art.draw_text(self, "第 %d 波 · %d 阶段：%s" % [_boss_wave(kind), phases.size(), lines], Vector2(TEXT_X, y + 13), 12, Color("#e8e4d8"))
		Art.draw_text(self, String(boss["warn"]), Vector2(TEXT_X, y + 26), 12, Color("#a8d8a0"))
		if boss.has("trophy"):
			Art.draw_text(self, "战利品：%s（%s）" % [GameData.TROPHIES[boss["trophy"]]["name"], GameData.TROPHIES[boss["trophy"]]["desc"]], Vector2(TEXT_X, y + 39), 12, Color("#ffe080"))
		else:
			Art.draw_text(self, "对策：" + String(stat["tip"]), Vector2(TEXT_X, y + 39), 12, Color("#ffe080"))
		return
	Art.draw_text(self, String(stat["desc"]), Vector2(TEXT_X, y + 13), 12, Color("#e8e4d8"))
	Art.draw_text(self, "对策：" + String(stat["tip"]), Vector2(TEXT_X, y + 26), 12, Color("#a8d8a0"))


func _boss_wave(kind: String) -> int:
	for i in GameData.WAVES.size():
		if GameData.WAVES[i].has(kind):
			return i + 1
	return 0
