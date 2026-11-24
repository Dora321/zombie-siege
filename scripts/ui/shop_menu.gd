extends Control
## 波间商店界面。商品和规则来自 shop_catalog，这里只负责显示和转发点击。

var game: Node
var _tab := 0
var _buttons := {}
var _touch := false

@onready var title_label: Label = %TitleLabel
@onready var status_label: Label = %StatusLabel
@onready var intel_label: Label = %IntelLabel
@onready var weak_label: Label = %WeakLabel
@onready var rows: VBoxContainer = %Rows
@onready var scroll: ScrollContainer = $Panel/VBox/Scroll
@onready var tab_bar: HBoxContainer = %TabBar
@onready var start_button: Button = %StartButton


func setup(g: Node) -> void:
	game = g
	visible = false
	_touch = Mobile.is_touch()
	start_button.pressed.connect(_on_start)
	if _touch:
		# 让 ScrollContainer 收到从商品按钮开始的滑动，并在拖动后取消该次购买点击。
		scroll.scroll_deadzone = 6
		rows.mouse_filter = Control.MOUSE_FILTER_PASS
		rows.add_theme_constant_override("separation", 2)
		start_button.custom_minimum_size.y = 22.0
	else:
		start_button.mouse_entered.connect(func(): Sfx.play("ui_hover"))
	var tabs: Array[String] = game.Shop.TABS
	for i in tabs.size():
		var b := Button.new()
		b.text = tabs[i]
		b.custom_minimum_size = Vector2(58, 20 if _touch else 16)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_select_tab.bind(i))
		tab_bar.add_child(b)


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false


func _select_tab(i: int) -> void:
	_tab = i
	Sfx.play("ui_click")
	refresh()


func _on_start() -> void:
	Sfx.play("ui_click")
	game.start_next_wave()


func refresh() -> void:
	var p: Variant = game.player
	title_label.text = "补给站  下一波：第 %d 波 %s%s" % [game.wave + 1, GameData.wave_name(game.wave + 1), game.events.forecast_text()]
	status_label.text = "金币 %d   生命 %d/%d   基地 %d/%d   分数 %d   枪袋 %d/%d" % [
		game.coins, roundi(p.hp), roundi(p.max_hp), roundi(game.base.hp), roundi(game.base.max_hp), game.score,
		p.owned_weapons().size(), p.weapon_slots,
	]
	_show_intel(GameData.wave_preview(game.wave + 1))
	start_button.text = "开始第 %d 波" % (game.wave + 1)
	for i in tab_bar.get_child_count():
		var b: Button = tab_bar.get_child(i)
		b.button_pressed = i == _tab
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	_buttons.clear()
	for item: Dictionary in game.shop_items():
		if int(item["tab"]) != _tab:
			continue
		rows.add_child(_make_row(item))


## 下一波情报：怪种和数量一行，Boss 或精英的弱点一行（太长就截断成「…」）。
## 出怪方向每批随机，所以只写四边来袭。
func _show_intel(preview: Dictionary) -> void:
	var parts: Array[String] = []
	for k: Dictionary in preview["kinds"]:
		parts.append("%s×%d" % [k["name"], k["count"]])
	intel_label.text = "情报：%s · 四边来袭" % " ".join(parts)
	var boss: String = preview["boss_kind"]
	var line := ""
	if boss != "":
		line = "Boss：%s  怕：%s" % [GameData.short_name(boss), GameData.weakness(boss)]
		if String(preview["hint"]) != "":
			line += " · " + String(preview["hint"])
	else:
		var weak: Array[String] = []
		for k: Dictionary in preview["kinds"]:
			if String(k["weak"]) != "":
				weak.append("%s怕%s" % [k["name"], k["weak"]])
		if not weak.is_empty():
			line = "注意：" + "  ".join(weak)
		elif String(preview["hint"]) != "":
			line = String(preview["hint"])
	weak_label.text = line
	weak_label.visible = line != ""


func _make_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 22 if _touch else 20)
	if _touch:
		row.mouse_filter = Control.MOUSE_FILTER_PASS
	var name_label := Label.new()
	name_label.text = String(item["name"])
	name_label.custom_minimum_size = Vector2(130, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	var desc := Label.new()
	desc.text = String(item["desc"])
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc.modulate = Color(0.75, 0.73, 0.68)
	desc.clip_text = true
	row.add_child(desc)
	if item.has("swap"):
		var swap: Dictionary = item["swap"]
		var toggle := Button.new()
		toggle.text = String(swap["text"])
		_fit_product_button(toggle, 36.0)
		toggle.disabled = not bool(swap["ok"])
		toggle.pressed.connect(_on_buy.bind(String(swap["id"])))
		if not _touch:
			toggle.mouse_entered.connect(func(): Sfx.play("ui_hover"))
		_buttons[String(swap["id"])] = toggle
		row.add_child(toggle)
	var buy := Button.new()
	_fit_product_button(buy, 66.0)
	var id := String(item["id"])
	buy.disabled = not game.shop_can_buy(item)
	if bool(item["locked"]):
		buy.text = String(item.get("locked_text", "--"))
	else:
		buy.text = String(item.get("button", "%d 金币" % int(item["cost"])))
		buy.pressed.connect(_on_buy.bind(id))
		if not _touch:
			buy.mouse_entered.connect(func(): Sfx.play("ui_hover"))
	_buttons[id] = buy
	row.add_child(buy)
	return row


func _fit_product_button(button: Button, width: float) -> void:
	button.custom_minimum_size = Vector2(width, 20 if _touch else 18)
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _touch:
		button.mouse_filter = Control.MOUSE_FILTER_PASS


func _on_buy(id: String) -> void:
	if game.shop_buy(id):
		Sfx.play("buy")
	else:
		Sfx.play("deny")
	if visible:
		refresh()
