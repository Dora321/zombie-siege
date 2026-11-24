extends PanelContainer

signal closed

const SCROLL_STEP := 44

@onready var _heading: Label = %Heading
@onready var _career_stats: Label = %CareerStats
@onready var _scroll: ScrollContainer = %Scroll
@onready var _grid: GridContainer = %Badges
@onready var _close_button: Button = %Close


func _ready() -> void:
	_close_button.pressed.connect(close)
	if Mobile.is_touch():
		_scroll.scroll_deadzone = 6
		_scroll.focus_mode = Control.FOCUS_NONE
		_close_button.focus_mode = Control.FOCUS_NONE
	else:
		_close_button.mouse_entered.connect(func(): Sfx.play("ui_hover"))


func open() -> void:
	_heading.text = "成就与战绩  (%d / %d)" % [Save.unlocked_achievement_count(), GameData.ACHIEVEMENT_ORDER.size()]
	var totals := "总击杀 %d   总场次 %d   通关 %d   击杀Boss %d" % [
		int(Save.career.get("kills", 0)), int(Save.career.get("runs", 0)),
		int(Save.career.get("victories", 0)), int(Save.career.get("bosses", 0)),
	]
	var endless := "第%d波" % Save.best_endless_wave if Save.best_endless_wave > 0 else "--"
	var rush_seconds := int(Save.best_boss_rush_time)
	var rush := "%d:%02d" % [floori(Save.best_boss_rush_time / 60.0), rush_seconds % 60] if Save.best_boss_rush_time > 0.0 else "--"
	var best := Save.today_daily_best()
	var daily := "%d分" % best if best > 0 else "--"
	_career_stats.text = totals + "\n" + "无尽最高 %s   连战最快 %s   今日挑战 %s" % [endless, rush, daily]
	for badge: Node in _grid.get_children():
		_grid.remove_child(badge)
		badge.queue_free()
	for id: String in GameData.ACHIEVEMENT_ORDER:
		_add_badge(GameData.ACHIEVEMENTS[id], Save.has_achievement(id))
	show()
	_scroll.scroll_vertical = 0
	if not Mobile.is_touch():
		_close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	Sfx.play("ui_click")
	closed.emit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	var step := 0
	if event.is_action_pressed("ui_up", true):
		step = -SCROLL_STEP
	elif event.is_action_pressed("ui_down", true):
		step = SCROLL_STEP
	elif event.is_action_pressed("ui_page_up", true):
		step = -int(_scroll.size.y)
	elif event.is_action_pressed("ui_page_down", true):
		step = int(_scroll.size.y)
	if step != 0:
		_scroll.scroll_vertical += step
		get_viewport().set_input_as_handled()


func _add_badge(spec: Dictionary, unlocked: bool) -> void:
	var accent := Color(String(spec["color"])) if unlocked else Color("#4b4e5c")
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#30271d") if unlocked else Color("#222431")
	style.border_color = accent
	style.border_width_left = 3
	style.content_margin_left = 9.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	style.anti_aliasing = false

	var card := PanelContainer.new()
	card.custom_minimum_size.y = 39.0
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", style)
	_grid.add_child(card)

	var copy := VBoxContainer.new()
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_theme_constant_override("separation", 2)
	card.add_child(copy)

	var title := Label.new()
	title.text = ("★ " if unlocked else "☆ ") + String(spec["name"])
	title.add_theme_color_override("font_color", accent if unlocked else Color("#b5b8c6"))
	copy.add_child(title)

	var description := Label.new()
	description.text = String(spec["desc"])
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("#eee5d3") if unlocked else Color("#979aaa"))
	copy.add_child(description)
