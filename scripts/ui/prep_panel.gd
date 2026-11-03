extends Control
## 行动准备：选完地图后选危险等级（0~5，通关上一级才解锁）和可叠加的契约，显示结算分数的倍率。
## 鼠标或方向键加回车操作，Esc 返回选图。

signal confirmed
signal closed

const DANGER_TOP := 24.0
const DANGER_X := 76.0
const CONTRACT_TOP := 78.0
const ROW_H := 22.0
const DESC_X := 104.0

var danger := 0
var picked: Array[String] = []
var danger_buttons: Array[Button] = []
var contract_buttons := {}
var _map_id := "ruins"

@onready var back_button: Button = %PrepBack
@onready var go_button: Button = %PrepGo


func _ready() -> void:
	visible = false
	for d in GameData.MAX_DANGER + 1:
		var b := _make_button(str(d), Vector2(DANGER_X + d * 30, DANGER_TOP), Vector2(26, 18))
		b.pressed.connect(set_danger.bind(d))
		danger_buttons.append(b)
	for i in GameData.CONTRACT_ORDER.size():
		var id: String = GameData.CONTRACT_ORDER[i]
		var b := _make_button(String(GameData.CONTRACTS[id]["name"]), Vector2(14, CONTRACT_TOP + i * ROW_H), Vector2(84, 18))
		b.pressed.connect(toggle_contract.bind(id))
		contract_buttons[id] = b
	back_button.pressed.connect(close)
	go_button.pressed.connect(confirm)
	for b: Button in [back_button, go_button]:
		b.mouse_entered.connect(func(): Sfx.play("ui_hover"))
	_link_focus()


func _make_button(text: String, at: Vector2, button_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.position = at
	b.size = button_size
	b.custom_minimum_size = button_size
	b.mouse_entered.connect(func():
		Sfx.play("ui_hover")
		if not b.disabled:
			b.grab_focus())
	add_child(b)
	return b


## 面板盖在标题菜单上面，焦点按「危险等级 → 契约 → 返回/开始」串起来，方向键不会跳到底下的按钮。
func _link_focus() -> void:
	var order: Array[Control] = []
	order.append_array(danger_buttons)
	for id: String in GameData.CONTRACT_ORDER:
		order.append(contract_buttons[id])
	order.append(back_button)
	order.append(go_button)
	var n := order.size()
	for i in n:
		var c: Control = order[i]
		var nxt := c.get_path_to(order[(i + 1) % n])
		var prev := c.get_path_to(order[(i + n - 1) % n])
		c.focus_next = nxt
		c.focus_previous = prev
		c.focus_neighbor_right = nxt
		c.focus_neighbor_left = prev
		c.focus_neighbor_bottom = nxt
		c.focus_neighbor_top = prev


func open(map_id: String) -> void:
	_map_id = map_id
	visible = true
	danger = mini(Save.danger, Save.max_danger)
	picked = Save.contracts.duplicate()
	_sync()
	go_button.grab_focus()


func close() -> void:
	Sfx.play("ui_click")
	visible = false
	closed.emit()


## 记下这次的选择，下次开局和「再来一局」沿用。
func confirm() -> void:
	Sfx.play("ui_click")
	Save.danger = danger
	Save.contracts = picked.duplicate()
	Save.save_all()
	confirmed.emit()


func set_danger(d: int) -> void:
	if d > Save.max_danger:
		Sfx.play("deny")
		_sync()
		return
	Sfx.play("ui_click")
	danger = d
	_sync()


func toggle_contract(id: String) -> void:
	Sfx.play("ui_click")
	if picked.has(id):
		picked.erase(id)
	else:
		picked.append(id)
	# 按表里的顺序存，排行榜和结算里显示得一致
	picked.sort_custom(func(a, b): return GameData.CONTRACT_ORDER.find(a) < GameData.CONTRACT_ORDER.find(b))
	_sync()


func multiplier() -> float:
	return GameData.run_mult(danger, picked)


func mult_line() -> String:
	return "危险 %s × 契约 %s = 分数 %s" % [
		GameData.mult_text(GameData.danger_score_mult(danger)), GameData.mult_text(GameData.contract_mult(picked)), GameData.mult_text(multiplier()),
	]


func _sync() -> void:
	for d in danger_buttons.size():
		danger_buttons[d].set_pressed_no_signal(d == danger)
		danger_buttons[d].disabled = d > Save.max_danger
	for id: String in contract_buttons.keys():
		contract_buttons[id].set_pressed_no_signal(picked.has(id))
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		close()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.05, 0.08, 0.97))
	draw_rect(Rect2(Vector2.ZERO, size), Color("#8a6a3a"), false, 1.0)
	Art.draw_text(self, "行动准备 · %s" % GameData.MAPS[_map_id]["name"], Vector2(size.x * 0.5, 6), 12, Color(1, 0.82, 0.45), 1)
	Art.draw_text(self, "危险等级", Vector2(14, DANGER_TOP + 3), 12, Color("#f0d080"))
	if Save.max_danger < GameData.MAX_DANGER:
		Art.draw_text(self, "通关危 %d 解锁危 %d" % [Save.max_danger, Save.max_danger + 1], Vector2(size.x - 14, DANGER_TOP + 3), 12, Color("#8a8890"), 2)
	Art.draw_text(self, GameData.danger_desc(danger), Vector2(14, DANGER_TOP + 23), 12, Color("#ff9070") if danger > 0 else Color("#a8d8a0"))
	Art.draw_text(self, "契约（可叠加，越难分越高）", Vector2(14, CONTRACT_TOP - 16), 12, Color("#f0d080"))
	for i in GameData.CONTRACT_ORDER.size():
		var id: String = GameData.CONTRACT_ORDER[i]
		var spec: Dictionary = GameData.CONTRACTS[id]
		var on := picked.has(id)
		var line := "+%d%%  %s" % [roundi(float(spec["mult"]) * 100.0), spec["desc"]]
		Art.draw_text(self, line, Vector2(DESC_X, CONTRACT_TOP + i * ROW_H + 3), 12, Color("#ffe080") if on else Color("#a8a4a0"))
	var mult_y := CONTRACT_TOP + GameData.CONTRACT_ORDER.size() * ROW_H + 8
	Art.draw_text(self, mult_line(), Vector2(size.x * 0.5, mult_y), 12, Color("#ffe080") if multiplier() > 1.0 else Color("#e8e4d8"), 1)
