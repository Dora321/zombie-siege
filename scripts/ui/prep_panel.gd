extends Control
## 行动准备：选择角色、危险等级和可叠加的契约，显示结算分数倍率。
## 鼠标或方向键加回车操作，Esc 返回选图。

signal confirmed
signal closed

const HERO_TOP := 20.0
const HERO_X := 46.0
const HERO_SPACING := 79.0
const HERO_DESC_TOP := 41.0
const DANGER_TOP := 59.0
const DANGER_X := 76.0
const DANGER_DESC_TOP := 80.0
const CONTRACT_TOP := 116.0
const ROW_H := 20.0
const DESC_X := 104.0
const MULT_TOP := 216.0

var hero_id := "captain"
var danger := 0
var picked: Array[String] = []
var hero_buttons: Array[Button] = []
var danger_buttons: Array[Button] = []
var contract_buttons := {}
var _map_id := "ruins"
var _touch := false

@onready var back_button: Button = %PrepBack
@onready var go_button: Button = %PrepGo


func _ready() -> void:
	visible = false
	_touch = Mobile.is_touch()
	var hero_size := Vector2(76, 20 if _touch else 18)
	var danger_spacing := 32.0 if _touch else 30.0
	var danger_size := Vector2(28, 20) if _touch else Vector2(26, 18)
	var contract_size := Vector2(84, 19 if _touch else 18)
	for i in GameData.HERO_ORDER.size():
		var id: String = GameData.HERO_ORDER[i]
		var b := _make_button(String(GameData.HEROES[id]["name"]), Vector2(HERO_X + i * HERO_SPACING, HERO_TOP), hero_size)
		b.pressed.connect(set_hero.bind(id))
		hero_buttons.append(b)
	for d in GameData.MAX_DANGER + 1:
		var b := _make_button(str(d), Vector2(DANGER_X + d * danger_spacing, DANGER_TOP), danger_size)
		b.pressed.connect(set_danger.bind(d))
		danger_buttons.append(b)
	for i in GameData.CONTRACT_ORDER.size():
		var id: String = GameData.CONTRACT_ORDER[i]
		var b := _make_button(String(GameData.CONTRACTS[id]["name"]), Vector2(14, CONTRACT_TOP + i * ROW_H), contract_size)
		b.pressed.connect(toggle_contract.bind(id))
		contract_buttons[id] = b
	back_button.pressed.connect(close)
	go_button.pressed.connect(confirm)
	for b: Button in [back_button, go_button]:
		if _touch:
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size.y = 22.0
		else:
			b.mouse_entered.connect(func(): Sfx.play("ui_hover"))
	if not _touch:
		_link_focus()


func _make_button(text: String, at: Vector2, button_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.position = at
	b.size = button_size
	b.custom_minimum_size = button_size
	if _touch:
		b.focus_mode = Control.FOCUS_NONE
	else:
		b.mouse_entered.connect(func():
			Sfx.play("ui_hover")
			if not b.disabled:
				b.grab_focus())
	add_child(b)
	return b


## 角色、危险等级、契约和底部按钮组成一个焦点环。
func _link_focus() -> void:
	var order: Array[Control] = []
	order.append_array(hero_buttons)
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
	hero_id = Save.hero_id
	danger = mini(Save.danger, Save.max_danger)
	picked = Save.contracts.duplicate()
	_sync()
	if not _touch:
		go_button.grab_focus()


func close() -> void:
	Sfx.play("ui_click")
	visible = false
	closed.emit()


## 记下这次的选择，下次开局和「再来一局」沿用。
func confirm() -> void:
	Sfx.play("ui_click")
	Save.hero_id = hero_id
	Save.danger = danger
	Save.contracts = picked.duplicate()
	Save.save_all()
	confirmed.emit()


func set_hero(id: String) -> void:
	Sfx.play("ui_click")
	hero_id = id
	_sync()


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
	for i in hero_buttons.size():
		hero_buttons[i].set_pressed_no_signal(GameData.HERO_ORDER[i] == hero_id)
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
	var heading := "Boss 连战" if Save.game_mode == "boss_rush" else "行动准备"
	Art.draw_text(self, "%s · %s" % [heading, GameData.MAPS[_map_id]["name"]], Vector2(size.x * 0.5, 2), 12, Color(1, 0.82, 0.45), 1)
	Art.draw_text(self, "角色", Vector2(14, HERO_TOP + 3), 12, Color("#f0d080"))
	var hero: Dictionary = GameData.HEROES[hero_id]
	Art.draw_text(self, String(hero["desc"]), Vector2(14, HERO_DESC_TOP), 12, Color(String(hero["tint"])))
	Art.draw_text(self, "危险等级", Vector2(14, DANGER_TOP + 3), 12, Color("#f0d080"))
	if Save.max_danger < GameData.MAX_DANGER:
		Art.draw_text(self, "通关危 %d 解锁危 %d" % [Save.max_danger, Save.max_danger + 1], Vector2(size.x - 14, DANGER_TOP + 3), 12, Color("#8a8890"), 2)
	Art.draw_text(self, GameData.danger_desc(danger), Vector2(14, DANGER_DESC_TOP), 12, Color("#ff9070") if danger > 0 else Color("#a8d8a0"))
	Art.draw_text(self, "契约（可叠加，越难分越高）", Vector2(14, CONTRACT_TOP - 18), 12, Color("#f0d080"))
	for i in GameData.CONTRACT_ORDER.size():
		var id: String = GameData.CONTRACT_ORDER[i]
		var spec: Dictionary = GameData.CONTRACTS[id]
		var on := picked.has(id)
		var line := "+%d%%  %s" % [roundi(float(spec["mult"]) * 100.0), spec["desc"]]
		Art.draw_text(self, line, Vector2(DESC_X, CONTRACT_TOP + i * ROW_H + 2), 12, Color("#ffe080") if on else Color("#a8a4a0"))
	Art.draw_text(self, mult_line(), Vector2(size.x * 0.5, MULT_TOP), 12, Color("#ffe080") if multiplier() > 1.0 else Color("#e8e4d8"), 1)
