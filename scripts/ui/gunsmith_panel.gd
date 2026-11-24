extends Control
## 波间改装面板。购买和拆卸在这里结算，玩家接口负责写入配件和刷新武器。

signal closed

const WeaponMods := preload("res://scripts/game/weapon_mods.gd")
const GOLD := Color("#e4b96f")
const MUTED := Color("#bfbac4")

var game: Node
var _weapon_id := ""
var _slot := "muzzle"
var _touch := false
var _shown_coins := -1
var _buy_buttons: Dictionary[String, Button] = {}

@onready var _coins: Label = %Coins
@onready var _back: Button = %Back
@onready var _weapons: HBoxContainer = %Weapons
@onready var _slots: HBoxContainer = %Slots
@onready var _remove: Button = %Remove
@onready var _scroll: ScrollContainer = %Scroll
@onready var _rows: VBoxContainer = %Rows


func _ready() -> void:
	_back.pressed.connect(close)
	_remove.pressed.connect(_sell)
	set_process(false)


func setup(g: Node) -> void:
	game = g


func open(initial_weapon_id := "") -> void:
	if not is_node_ready():
		await ready
	_touch = Mobile.is_touch()
	_weapon_id = initial_weapon_id
	_slot = WeaponMods.SLOT_ORDER[0]
	_back.focus_mode = Control.FOCUS_NONE if _touch else Control.FOCUS_ALL
	_remove.focus_mode = _back.focus_mode
	_scroll.scroll_vertical = 0
	show()
	_refresh()
	set_process(true)


func close() -> void:
	if not visible:
		return
	hide()
	set_process(false)
	Sfx.play("ui_click")
	closed.emit()


func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and not event.is_echo():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			close()


func _process(_delta: float) -> void:
	if _balance() != _shown_coins:
		_sync_prices(_read_mods(_player(), _weapon_id))
		_link_focus()


func _player() -> Node:
	return game.get("player") as Node if is_instance_valid(game) else null


func _balance() -> int:
	return int(game.get("coins")) if is_instance_valid(game) else 0


func _state(player: Node, id: String) -> Dictionary:
	var states: Variant = player.get("weapon_state") if is_instance_valid(player) else null
	if states is Dictionary and states.get(id) is Dictionary:
		return states[id]
	return {}


func _carried(player: Node) -> Array[String]:
	var ids: Array[String] = []
	if not is_instance_valid(player):
		return ids
	if player.has_method("owned_weapons"):
		ids.assign(player.call("owned_weapons"))
	else:
		var loadout: Variant = player.get("loadout")
		for id: String in GameData.WEAPON_ORDER:
			if int(_state(player, id).get("level", 0)) > 0 and (not loadout is Array or loadout.has(id)):
				ids.append(id)
	return ids


func _read_mods(player: Node, id: String) -> Dictionary:
	if not id.is_empty() and is_instance_valid(player) and player.has_method("get_weapon_mods"):
		return WeaponMods.sanitize_mods(player.call("get_weapon_mods", id))
	return WeaponMods.sanitize_mods(_state(player, id).get("mods"))


func _engineer_discount() -> bool:
	if not is_instance_valid(game):
		return false
	var player := _player()
	return game.get("hero_id") == "engineer" or (is_instance_valid(player) and player.get("hero_id") == "engineer")


func _write_mod(player: Node, id: String, slot: String, mod_id: String) -> bool:
	var method := "remove_weapon_mod" if mod_id.is_empty() else "equip_weapon_mod"
	if player.has_method(method):
		if mod_id.is_empty():
			player.call(method, id, slot)
		else:
			player.call(method, id, slot, mod_id)
		return _read_mods(player, id)[slot] == mod_id

	var state := _state(player, id)
	if state.is_empty():
		return false
	var old_mods := _read_mods(player, id)
	var new_mods := old_mods.duplicate()
	new_mods[slot] = mod_id
	state["mods"] = new_mods

	# 独立面板可直接使用现有玩家数据，接入玩家接口后由它负责重算。
	var base := GameData.weapon_stats(id, maxi(int(state.get("level", 1)), 1))
	var old_stats := WeaponMods.apply_to_stats(base, old_mods)
	var new_stats := WeaponMods.apply_to_stats(base, new_mods)
	var cached_stats: Variant = player.get("stats")
	if cached_stats is Dictionary:
		cached_stats[id] = new_stats
	if state.has("mag"):
		var capacity: int = new_stats["mag"]
		var ammo: int = state["mag"]
		if bool(new_stats.get("returns", false)):
			ammo += capacity - int(old_stats["mag"])
		elif ammo > capacity and int(state.get("reserve", -1)) >= 0:
			state["reserve"] = int(state["reserve"]) + ammo - capacity
		state["mag"] = clampi(ammo, 0, capacity)
	return true


func _refresh() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var focus_path: NodePath
	if not _touch and is_instance_valid(focused) and is_ancestor_of(focused):
		focus_path = get_path_to(focused)
	var player := _player()
	var carried := _carried(player)
	if not carried.has(_weapon_id):
		var current: Variant = player.get("weapon_id") if is_instance_valid(player) else null
		_weapon_id = ""
		if current is String and carried.has(current):
			_weapon_id = current
		elif not carried.is_empty():
			_weapon_id = carried[0]

	var equipped := _read_mods(player, _weapon_id)
	_clear_children(_weapons)
	_clear_children(_slots)
	_clear_children(_rows)
	_buy_buttons.clear()
	for id: String in carried:
		_add_weapon(player, id, equipped if id == _weapon_id else _read_mods(player, id))
	for slot: String in WeaponMods.SLOT_ORDER:
		_add_slot(slot, String(equipped[slot]))

	var installed: String = equipped[_slot]
	_remove.visible = not installed.is_empty()
	if _remove.visible:
		_remove.text = "卸下 (+%d)" % WeaponMods.mod_sell_refund(installed)
	if carried.is_empty():
		var empty := Label.new()
		empty.text = "没有可改装的随身武器"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows.add_child(empty)
	else:
		for mod_id: String in WeaponMods.compatible_mods(_weapon_id, _slot):
			_add_mod(mod_id, installed)
	_sync_prices(equipped)
	_link_focus()
	if not _touch:
		var restore := get_node_or_null(focus_path) as Button if not focus_path.is_empty() else null
		if not is_instance_valid(restore) or not restore.visible or restore.disabled:
			restore = _slots.get_node_or_null(_slot) as Button
		if not is_instance_valid(restore) or restore.disabled:
			restore = _back
		restore.grab_focus()


func _clear_children(container: Container) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _add_weapon(player: Node, id: String, equipped: Dictionary) -> void:
	var count := 0
	for mod_id: String in equipped.values():
		if not mod_id.is_empty():
			count += 1
	var title := String(GameData.WEAPONS[id]["name"])
	if player.has_method("weapon_name"):
		title = String(player.call("weapon_name", id))
	var button := _make_button("%s %d/3" % [title, count])
	button.name = id
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if id == _weapon_id:
		_tint_tab(button, GOLD, true)
	button.pressed.connect(_select_weapon.bind(id))
	_weapons.add_child(button)


func _add_slot(slot: String, mod_id: String) -> void:
	var spec: Dictionary = WeaponMods.MODS.get(mod_id, {})
	var label := "%s：%s" % [WeaponMods.SLOT_NAMES[slot], spec.get("name", "空")]
	var button := _make_button(label)
	button.name = slot
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = _weapon_id.is_empty()
	var tint := Color(String(spec.get("color", "#71687b")))
	if slot == _slot or not spec.is_empty():
		_tint_tab(button, GOLD if slot == _slot and spec.is_empty() else tint, slot == _slot)
	button.pressed.connect(_select_slot.bind(slot))
	_slots.add_child(button)


func _add_mod(mod_id: String, installed: String) -> void:
	var spec: Dictionary = WeaponMods.MODS[mod_id]
	var tint := Color(String(spec["color"]))
	var card := PanelContainer.new()
	card.name = mod_id
	card.custom_minimum_size.y = 30.0
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := _box(Color("#201e28") if mod_id == installed else Color("#15141c"), tint)
	style.border_width_left = 2
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 0
	style.content_margin_left = 8.0
	style.content_margin_right = 4.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	card.add_theme_stylebox_override("panel", style)
	_rows.add_child(card)

	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_theme_constant_override("separation", 6)
	card.add_child(content)
	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_PASS
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.add_theme_constant_override("separation", 0)
	content.add_child(copy)
	var title := Label.new()
	title.text = String(spec["name"])
	title.add_theme_color_override("font_color", tint)
	copy.add_child(title)
	var desc := Label.new()
	desc.text = String(spec["desc"])
	if _weapon_id == "boomerang":
		match mod_id:
			"ext_mag":
				desc.text = "随身回旋镖 +1"
			"quick_mag":
				desc.text = "回旋镖飞行速度 +15%"
	desc.add_theme_color_override("font_color", MUTED)
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(desc)

	var buy := _make_button("")
	buy.name = "Buy"
	buy.custom_minimum_size = Vector2(76, 26)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 让滚动容器收到从购买按钮开始的拖动并取消该次点击。
	buy.mouse_filter = Control.MOUSE_FILTER_PASS
	if not installed.is_empty() and mod_id != installed:
		buy.tooltip_text = "替换当前配件。可先卸下旧配件返还金币。"
	buy.pressed.connect(_buy.bind(mod_id))
	content.add_child(buy)
	_buy_buttons[mod_id] = buy


func _make_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_NONE if _touch else Control.FOCUS_ALL
	return button


func _box(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	style.anti_aliasing = false
	return style


func _tint_tab(button: Button, tint: Color, selected: bool) -> void:
	var fill := Color("#211e29")
	var normal := _box(fill.lerp(tint, 0.18) if selected else fill, tint)
	normal.border_width_bottom = 2 if selected else 1
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", _box(fill.lerp(tint, 0.25), tint))
	button.add_theme_stylebox_override("pressed", _box(fill.lerp(tint, 0.32), tint))
	button.add_theme_color_override("font_color", tint)


func _sync_prices(equipped: Dictionary) -> void:
	_shown_coins = _balance()
	_coins.text = "金币：%d" % _shown_coins
	var discount := _engineer_discount()
	for mod_id: String in _buy_buttons:
		var button: Button = _buy_buttons[mod_id]
		var cost := WeaponMods.mod_cost(mod_id, discount)
		var installed: bool = equipped[_slot] == mod_id
		button.text = "已装配" if installed else "%d 金币" % cost
		button.disabled = installed or _shown_coins < cost


func _link_focus() -> void:
	if _touch:
		return
	var chain: Array[Button] = [_back]
	for button: Button in _weapons.get_children():
		chain.append(button)
	for button: Button in _slots.get_children():
		if not button.disabled:
			chain.append(button)
	if _remove.visible:
		chain.append(_remove)
	for button: Button in _buy_buttons.values():
		if not button.disabled:
			chain.append(button)
	for i in chain.size():
		var button := chain[i]
		button.focus_next = button.get_path_to(chain[(i + 1) % chain.size()])
		button.focus_previous = button.get_path_to(chain[posmod(i - 1, chain.size())])


func _select_weapon(id: String) -> void:
	_weapon_id = id
	_scroll.scroll_vertical = 0
	Sfx.play("ui_click")
	_refresh()


func _select_slot(slot: String) -> void:
	_slot = slot
	_scroll.scroll_vertical = 0
	Sfx.play("ui_click")
	_refresh()


func _buy(mod_id: String) -> void:
	var player := _player()
	if not _carried(player).has(_weapon_id) or not WeaponMods.compatible_mods(_weapon_id, _slot).has(mod_id):
		return
	var cost := WeaponMods.mod_cost(mod_id, _engineer_discount())
	var installed: String = _read_mods(player, _weapon_id)[_slot]
	if installed == mod_id or _balance() < cost or not _write_mod(player, _weapon_id, _slot, mod_id):
		Sfx.play("deny")
		_refresh()
		return
	if game.has_method("spend_coins"):
		game.call("spend_coins", cost)
	else:
		game.set("coins", _balance() - cost)
	_finish_transaction()
	if not Harness.automated():
		Save.career["mods_bought"] = int(Save.career.get("mods_bought", 0)) + 1
		var equipped := _read_mods(player, _weapon_id)
		var all_slots_filled := WeaponMods.SLOT_ORDER.all(func(slot: String) -> bool:
			return not String(equipped[slot]).is_empty())
		# 首次解锁时会一并保存这次购买的计数。
		if not all_slots_filled or not Save.unlock_achievement("gunsmith"):
			Save.save_all()


func _sell() -> void:
	var player := _player()
	if not _carried(player).has(_weapon_id):
		return
	var installed: String = _read_mods(player, _weapon_id)[_slot]
	if installed.is_empty() or not _write_mod(player, _weapon_id, _slot, ""):
		return
	game.set("coins", _balance() + WeaponMods.mod_sell_refund(installed))
	_finish_transaction()


func _finish_transaction() -> void:
	if game.has_method("_save_resume_state"):
		game.call("_save_resume_state")
	Sfx.play("buy")
	_refresh()
