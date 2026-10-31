extends Control
## 波间商店界面。商品和规则来自 shop_catalog，这里只负责显示和转发点击。

var game: Node
var _tab := 0
var _buttons := {}

@onready var title_label: Label = %TitleLabel
@onready var status_label: Label = %StatusLabel
@onready var rows: VBoxContainer = %Rows
@onready var tab_bar: HBoxContainer = %TabBar
@onready var start_button: Button = %StartButton


func setup(g: Node) -> void:
	game = g
	visible = false
	start_button.pressed.connect(_on_start)
	start_button.mouse_entered.connect(func(): Sfx.play("ui_hover"))
	var tabs: Array[String] = game.Shop.TABS
	for i in tabs.size():
		var b := Button.new()
		b.text = tabs[i]
		b.custom_minimum_size = Vector2(58, 16)
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
	title_label.text = "补给站  下一波：第 %d 波 %s" % [game.wave + 1, GameData.wave_name(game.wave + 1)]
	status_label.text = "金币 %d    生命 %d/%d    基地 %d/%d    分数 %d" % [
		game.coins, roundi(p.hp), roundi(p.max_hp), roundi(game.base.hp), roundi(game.base.max_hp), game.score,
	]
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


func _make_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 20)
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
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(66, 18)
	buy.focus_mode = Control.FOCUS_NONE
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var id := String(item["id"])
	if bool(item["locked"]):
		buy.text = "--"
		buy.disabled = true
	else:
		buy.text = "%d 金币" % int(item["cost"])
		buy.disabled = not game.shop_can_buy(item)
		buy.pressed.connect(_on_buy.bind(id))
		buy.mouse_entered.connect(func(): Sfx.play("ui_hover"))
	_buttons[id] = buy
	row.add_child(buy)
	return row


func _on_buy(id: String) -> void:
	if game.shop_buy(id):
		Sfx.play("buy")
	else:
		Sfx.play("deny")
	if visible:
		refresh()
