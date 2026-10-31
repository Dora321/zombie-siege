extends Control
## 开局选图：三张缩略图卡片，可用鼠标或方向键加回车选择，Esc 返回。

const Layouts := preload("res://scripts/game/map_layouts.gd")
const CARD_SIZE := Vector2(144, 112)
const CARD_TOP := 24.0
const DESC_TOP := 148.0

signal chosen(id: String)
signal closed

var cards := {}
var _shown := "ruins"

@onready var back_button: Button = %MapBack


func _ready() -> void:
	visible = false
	var gap := (size.x - CARD_SIZE.x * GameData.MAP_ORDER.size()) / (GameData.MAP_ORDER.size() + 1)
	for i in GameData.MAP_ORDER.size():
		var id: String = GameData.MAP_ORDER[i]
		var card := Button.new()
		card.text = String(GameData.MAPS[id]["name"])
		card.icon = ImageTexture.create_from_image(Layouts.preview(id))
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.position = Vector2(gap + (CARD_SIZE.x + gap) * i, CARD_TOP)
		card.size = CARD_SIZE
		card.custom_minimum_size = CARD_SIZE
		card.pressed.connect(choose.bind(id))
		card.focus_entered.connect(_show_map.bind(id))
		card.mouse_entered.connect(func():
			Sfx.play("ui_hover")
			card.grab_focus())
		add_child(card)
		cards[id] = card
	_link_focus()
	back_button.pressed.connect(close)
	back_button.mouse_entered.connect(func(): Sfx.play("ui_hover"))


## 面板盖在标题菜单上面，不指定邻居的话方向键会跳到底下的按钮。
func _link_focus() -> void:
	var order: Array[Control] = []
	for id: String in GameData.MAP_ORDER:
		order.append(cards[id])
	var n := order.size()
	for i in n:
		var card: Control = order[i]
		var right := card.get_path_to(order[(i + 1) % n])
		var left := card.get_path_to(order[(i + n - 1) % n])
		var back := card.get_path_to(back_button)
		card.focus_neighbor_right = right
		card.focus_neighbor_left = left
		card.focus_next = right
		card.focus_previous = left
		card.focus_neighbor_bottom = back
		card.focus_neighbor_top = back
	var first := back_button.get_path_to(order[0])
	back_button.focus_neighbor_top = first
	back_button.focus_neighbor_bottom = first
	back_button.focus_neighbor_left = first
	back_button.focus_neighbor_right = first
	back_button.focus_next = first
	back_button.focus_previous = first


func open() -> void:
	visible = true
	_show_map(Save.map_id)
	cards[Save.map_id].grab_focus()


func close() -> void:
	Sfx.play("ui_click")
	visible = false
	closed.emit()


func choose(id: String) -> void:
	Sfx.play("ui_click")
	chosen.emit(id)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		close()


func _show_map(id: String) -> void:
	_shown = id
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.05, 0.08, 0.97))
	draw_rect(Rect2(Vector2.ZERO, size), Color("#8a6a3a"), false, 1.0)
	Art.draw_text(self, "选择地图", Vector2(size.x * 0.5, 6), 12, Color(1, 0.82, 0.45), 1)
	var spec: Dictionary = GameData.MAPS[_shown]
	Art.draw_text(self, "%s · %s" % [spec["name"], spec["tag"]], Vector2(14, DESC_TOP), 12, Color("#f0d080"))
	var y := DESC_TOP + 15.0
	for line: String in spec["desc"]:
		Art.draw_text(self, line, Vector2(14, y), 12, Color("#e8e4d8"))
		y += 14.0
	Art.draw_text(self, "局内随机事件：夜战、暴雨、大雾、空投、先遣尸群、电磁干扰", Vector2(14, y + 2.0), 12, Color("#a8d8a0"))
