extends Control
## 波间天赋选择。整张卡片都是按钮，鼠标、触控和键盘走同一条选择路径。

signal picked(perk_id: String)

@onready var cards: HBoxContainer = %Cards


func setup(game: Node) -> void:
	hide()
	picked.connect(game.on_perk_picked)


func open(choices: Array[String]) -> void:
	for card: Node in cards.get_children():
		cards.remove_child(card)
		card.queue_free()
	for id: String in choices:
		cards.add_child(_make_card(id))
	Mobile.clear_controls()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	_focus_first()


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED and is_node_ready() and is_visible_in_tree():
		_focus_first()


func _focus_first() -> void:
	if not Mobile.is_touch() and cards.get_child_count() > 0:
		cards.get_child(0).grab_focus()


func _make_card(id: String) -> Button:
	var spec: Dictionary = GameData.PERKS[id]
	var accent := Color(String(spec["color"]))
	var card := Button.new()
	card.custom_minimum_size = Vector2(134, 122)
	card.focus_mode = Control.FOCUS_NONE if Mobile.is_touch() else Control.FOCUS_ALL
	card.accessibility_name = "%s，%s，%s" % [spec["tag"], spec["name"], spec["desc"]]
	card.pressed.connect(_pick.bind(id))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#201e29")
	normal.border_color = accent.darkened(0.54)
	normal.set_border_width_all(1)
	normal.border_width_top = 3
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#2c2835")
	hover.border_color = accent
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#3b3444")
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", pressed)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 10
	content.offset_right = -10
	content.offset_top = 10
	content.offset_bottom = -8
	content.add_theme_constant_override("separation", 5)

	var badge := Label.new()
	badge.text = String(spec["tag"])
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.add_theme_color_override("font_color", accent)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = accent.darkened(0.78)
	badge_style.content_margin_left = 4
	badge_style.content_margin_right = 4
	badge.add_theme_stylebox_override("normal", badge_style)
	content.add_child(badge)

	var perk_name := Label.new()
	perk_name.text = String(spec["name"])
	perk_name.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(perk_name)

	var description := Label.new()
	description.text = String(spec["desc"])
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(description)

	var choose := Label.new()
	choose.text = "选择"
	choose.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choose.add_theme_color_override("font_color", accent)
	content.add_child(choose)
	return card


func _pick(id: String) -> void:
	if not is_visible_in_tree():
		return
	Sfx.play("buy")
	hide()
	picked.emit(id)
