extends Control
## 双摇杆和战斗快捷键。每个触点在抬起前只控制按下时选中的控件。

enum Target {NONE, MOVE, AIM, DASH, RELOAD, ITEM, PAUSE, PLACE, CONFIRM, CANCEL}

const Shop := preload("res://scripts/game/shop_catalog.gd")
const MOUSE_FINGER := -2
const STICK_RADIUS := 26.0
const DASH_RADIUS := 14.0
const RELOAD_RADIUS := 12.0
const ITEM_RADIUS := 13.0
const AIM_DEADZONE := 0.14

const INK := Color(0.055, 0.06, 0.085, 0.82)
const EDGE := Color(0.69, 0.76, 0.8, 0.66)
const MOVE_COLOR := Color("#80dbe3")
const FIRE_COLOR := Color("#ffc36b")
const READY_COLOR := Color("#98e49d")
const DENY_COLOR := Color("#c0716c")
const OCTAGON := [
	Vector2(-0.4, -1), Vector2(0.4, -1), Vector2(1, -0.4), Vector2(1, 0.4),
	Vector2(0.4, 1), Vector2(-0.4, 1), Vector2(-1, 0.4), Vector2(-1, -0.4),
]

var game: Node
var _placing := false
var _move_finger := -1
var _aim_finger := -1
var _place_finger := -1
var _buttons: Dictionary[int, Target] = {}
var _emulated_mouse_claimed := false
var _move_origin := Vector2.ZERO
var _move_delta := Vector2.ZERO
var _aim_origin := Vector2.ZERO
var _aim_delta := Vector2.ZERO

var _safe_rect := Rect2()
var _move_home := Vector2.ZERO
var _aim_home := Vector2.ZERO
var _dash_center := Vector2.ZERO
var _reload_center := Vector2.ZERO
var _item_center := Vector2.ZERO
var _pause_rect := Rect2()
var _confirm_rect := Rect2()
var _cancel_rect := Rect2()


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)


func setup(g: Node) -> void:
	game = g
	_sync_visibility()


func reset_controls() -> void:
	Mobile.clear_controls()
	_move_finger = -1
	_aim_finger = -1
	_place_finger = -1
	_buttons.clear()
	_move_delta = Vector2.ZERO
	_aim_delta = Vector2.ZERO


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		reset_controls()


func _exit_tree() -> void:
	reset_controls()


func _sync_visibility() -> bool:
	var active: bool = Mobile.is_touch() and is_instance_valid(game) and not get_tree().paused and game.player_can_walk()
	var placing: bool = active and game.state == game.State.PLACING
	if placing != _placing:
		reset_controls()
		_placing = placing
	if active != visible:
		visible = active
		if active:
			_layout()
	return is_visible_in_tree()


func _layout() -> void:
	var safe := Mobile.safe_insets(get_viewport())
	var top_left := Vector2(safe["left"], safe["top"])
	var bottom_right := size - Vector2(safe["right"], safe["bottom"])
	_safe_rect = Rect2(top_left, bottom_right - top_left)
	_move_home = Vector2(top_left.x + 44.0, bottom_right.y - 44.0).round()
	_aim_home = (bottom_right - Vector2(46, 44)).round()
	_dash_center = _aim_home + Vector2(-46, 8)
	_reload_center = _aim_home + Vector2(-38, -28)
	_item_center = _aim_home + Vector2(2, -44)
	_pause_rect = Rect2(Vector2(bottom_right.x - 20.0, top_left.y + 4.0).round(), Vector2(16, 16))
	_confirm_rect = Rect2((bottom_right - Vector2(66, 64)).round(), Vector2(54, 24))
	_cancel_rect = Rect2((bottom_right - Vector2(66, 36)).round(), Vector2(54, 24))


func _process(_dt: float) -> void:
	if _sync_visibility():
		_layout()
		if _aim_finger != -1:
			_update_aim()
		queue_redraw()


func _input(event: InputEvent) -> void:
	var active := _sync_visibility()
	var claimed := false
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		# 原生触摸会先生成一条鼠标事件。保留界面点击，避免把触点当成射击键。
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not event.canceled:
				_emulated_mouse_claimed = active and _target_at(event.position) != Target.NONE
				if active:
					Input.action_release("fire")
			claimed = _emulated_mouse_claimed
			if not event.pressed or event.canceled:
				_emulated_mouse_claimed = false
		elif event is InputEventMouseMotion:
			claimed = _emulated_mouse_claimed
	elif active:
		if event is InputEventScreenTouch:
			claimed = _pointer_button(event.index, event.position, event.pressed, event.canceled)
		elif event is InputEventScreenDrag:
			claimed = _pointer_drag(event.index, event.position)
		elif OS.has_feature("macos"):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				claimed = _pointer_button(MOUSE_FINGER, event.position, event.pressed, event.canceled)
				if claimed and event.pressed:
					Input.action_release("fire")
			elif event is InputEventMouseMotion:
				claimed = _pointer_drag(MOUSE_FINGER, event.position)
	if claimed:
		get_viewport().set_input_as_handled()


func _target_at(pos: Vector2) -> Target:
	if _pause_rect.grow(4).has_point(pos):
		return Target.PAUSE
	if not _safe_rect.has_point(pos) or _on_hud_bar(pos):
		return Target.NONE
	if _placing:
		if _confirm_rect.has_point(pos):
			return Target.CONFIRM
		if _cancel_rect.has_point(pos):
			return Target.CANCEL
		# 放置时只保留摇杆附近作为移动区，其余地图可以选点。
		var move_center := _move_home if _move_finger == -1 else _move_origin
		if pos.distance_to(move_center) <= STICK_RADIUS + 10.0:
			return Target.MOVE if _move_finger == -1 else Target.NONE
		return Target.PLACE if _place_finger == -1 else Target.NONE
	if pos.distance_to(_dash_center) <= DASH_RADIUS + 3.0:
		return Target.DASH
	if pos.distance_to(_reload_center) <= RELOAD_RADIUS + 3.0:
		return Target.RELOAD
	if pos.distance_to(_item_center) <= ITEM_RADIUS + 3.0:
		return Target.ITEM
	if _aim_finger == -1 and (pos.distance_to(_aim_home) <= STICK_RADIUS + 14.0 or (pos.x >= size.x * 0.5 and pos.y >= _safe_rect.position.y + 92.0)):
		return Target.AIM
	if _move_finger == -1 and pos.x < size.x * 0.5 and pos.y >= _safe_rect.position.y + 50.0:
		return Target.MOVE
	return Target.NONE


func _on_hud_bar(pos: Vector2) -> bool:
	if game.hud.has_method("is_point_on_hud_bar"):
		return game.hud.is_point_on_hud_bar(pos)
	# 兼容未提供命中区接口的 480×270 HUD。
	return Rect2(120, 232, 240, 38).has_point(pos)


func _pointer_button(index: int, pos: Vector2, pressed: bool, canceled: bool) -> bool:
	if not pressed or canceled:
		return _release_pointer(index, pos, canceled)
	var target := _target_at(pos)
	match target:
		Target.NONE:
			return false
		Target.MOVE:
			_move_finger = index
			_move_origin = pos
			_move_delta = Vector2.ZERO
			Mobile.move_vec = Vector2.ZERO
		Target.AIM:
			_aim_finger = index
			var margin := 16.0
			var min_p := _safe_rect.position + Vector2(margin, margin)
			var max_p := _safe_rect.end - Vector2(margin, margin)
			_aim_origin = Vector2(clampf(pos.x, min_p.x, max_p.x), clampf(pos.y, min_p.y, max_p.y))
			_aim_delta = Vector2.ZERO
			_update_aim()
		Target.PLACE:
			_place_finger = index
			_set_place_target(pos)
		_:
			_buttons[index] = target
			match target:
				Target.DASH:
					Mobile.latch_dash = true
					Mobile.trigger_haptic(14, 0.4)
				Target.RELOAD:
					Mobile.latch_reload = true
				Target.ITEM:
					Mobile.latch_item_use = game.player.selected_item
					Mobile.trigger_haptic(16, 0.45)
				Target.CONFIRM:
					Mobile.place_confirm = true
				Target.CANCEL:
					Mobile.place_cancel = true
	return true


func _pointer_drag(index: int, pos: Vector2) -> bool:
	if index == _move_finger:
		_move_delta = (pos - _move_origin).limit_length(STICK_RADIUS)
		Mobile.move_vec = _move_delta.normalized() if _move_delta.length() > STICK_RADIUS * 0.12 else Vector2.ZERO
	elif index == _aim_finger:
		_aim_delta = (pos - _aim_origin).limit_length(STICK_RADIUS)
		_update_aim()
	elif index == _place_finger:
		_set_place_target(pos)
	else:
		return _buttons.has(index)
	return true


func _release_pointer(index: int, pos: Vector2, canceled: bool) -> bool:
	if index == _move_finger:
		_move_finger = -1
		_move_delta = Vector2.ZERO
		Mobile.move_vec = Vector2.ZERO
	elif index == _aim_finger:
		_aim_finger = -1
		_aim_delta = Vector2.ZERO
		Mobile.aim_vec = Vector2.ZERO
		Mobile.aiming = false
		Mobile.firing = false
	elif index == _place_finger:
		_place_finger = -1
	elif _buttons.has(index):
		var pause := _buttons[index] == Target.PAUSE and not canceled and _pause_rect.grow(4).has_point(pos)
		_buttons.erase(index)
		if pause and game.state != game.State.OVER:
			game.pause_ui.open()
	else:
		return false
	return true


func _update_aim() -> void:
	var pull := _aim_delta.length() / STICK_RADIUS
	Mobile.aiming = pull > AIM_DEADZONE
	Mobile.aim_vec = _aim_delta.normalized() if Mobile.aiming else Vector2.ZERO
	# 点按/按住立即自动索敌开火，拖动立即 360° 手动转向并连发。
	Mobile.firing = _aim_finger != -1


func _set_place_target(pos: Vector2) -> void:
	Mobile.place_world_pos = game.camera.position + game.camera.offset + (pos - size * 0.5) + Vector2(0, 4)
	Mobile.place_has_target = true


func _draw() -> void:
	if game == null or game.player == null:
		return
	_draw_pause()
	var moving := _move_finger != -1
	_draw_stick(_move_origin if moving else _move_home, _move_delta, MOVE_COLOR, moving, false)
	if _placing:
		var available: bool = Mobile.place_has_target and game.coins >= Shop.turret_cost(game) and game.map.can_place_turret(game.map.cell_of(Mobile.place_world_pos))
		_draw_placement_button(_confirm_rect, "确认", READY_COLOR if available else DENY_COLOR, Target.CONFIRM)
		_draw_placement_button(_cancel_rect, "取消", EDGE, Target.CANCEL)
		return
	var aiming := _aim_finger != -1
	var aim_center := _aim_origin if aiming else _aim_home
	_draw_stick(aim_center, _aim_delta, FIRE_COLOR, aiming, Mobile.firing)
	_draw_fire_reticle(aim_center + _aim_delta * 0.73, FIRE_COLOR if aiming else EDGE)
	_draw_actions()


func _plate(center: Vector2, radius: float, fill: Color, edge: Color) -> void:
	var points := PackedVector2Array()
	for corner: Vector2 in OCTAGON:
		points.append((center + corner * radius).round())
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, edge, 1.0)


func _draw_stick(center: Vector2, delta: Vector2, accent: Color, pressed: bool, firing: bool) -> void:
	center = center.round()
	if firing:
		_plate(center, STICK_RADIUS + 3.0, Color(accent, 0.22), accent)
	_plate(center, STICK_RADIUS, Color(INK, 0.65 if pressed else 0.37), accent if pressed else EDGE)
	var tick := Color(accent, 0.9 if pressed else 0.48)
	for axis in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var at: Vector2 = center + axis * (STICK_RADIUS - 4.0)
		var tick_size := Vector2(2, 4) if axis.x == 0.0 else Vector2(4, 2)
		draw_rect(Rect2(at - tick_size * 0.5, tick_size), tick)
	_plate(center + delta * 0.73, 8.0, Color(accent, 0.48 if pressed else 0.10), tick)


func _draw_fire_reticle(center: Vector2, color: Color) -> void:
	center = center.round()
	for s: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_rect(Rect2((center + s * 3.0).round() - Vector2(0.5, 0.5), Vector2(2, 2)), color)
	draw_rect(Rect2(center - Vector2(0.5, 0.5), Vector2(1, 1)), color)


func _draw_actions() -> void:
	var player: Variant = game.player
	var dash_ready := float(player.dash_cd) <= 0.0
	var dash_color := MOVE_COLOR if dash_ready else EDGE
	if dash_ready:
		_plate(_dash_center, DASH_RADIUS + 2.0, Color(MOVE_COLOR, 0.14), Color(MOVE_COLOR, 0.3))
	_draw_action_plate(_dash_center, DASH_RADIUS, dash_color, Target.DASH)
	if not dash_ready:
		_draw_progress(_dash_center, DASH_RADIUS + 1.0, 1.0 - player.dash_cd / player.dash_cd_base, MOVE_COLOR)
	for x in [-4, 2]:
		var at := _dash_center + Vector2(x, 0)
		draw_polyline(PackedVector2Array([at + Vector2(-2, -4), at + Vector2(2, 0), at + Vector2(-2, 4)]), dash_color, 2.0)

	var reloading := float(player.reload_t) > 0.0
	var reload_color := FIRE_COLOR if reloading else EDGE
	_draw_action_plate(_reload_center, RELOAD_RADIUS, reload_color, Target.RELOAD)
	if reloading:
		_draw_progress(_reload_center, RELOAD_RADIUS + 1.0, 1.0 - player.reload_t / player.reload_total, FIRE_COLOR)
	var at := _reload_center
	draw_polyline(PackedVector2Array([at + Vector2(5, 1), at + Vector2(3, 5), at + Vector2(-3, 5), at + Vector2(-5, 3), at + Vector2(-5, -2), at + Vector2(-3, -4), at + Vector2(4, -4)]), reload_color, 2.0)
	draw_polyline(PackedVector2Array([at + Vector2(2, -7), at + Vector2(5, -4), at + Vector2(2, -1)]), reload_color, 2.0)

	var id: String = player.selected_item
	var count := int(player.items.get(id, 0))
	_draw_action_plate(_item_center, ITEM_RADIUS, FIRE_COLOR if count > 0 else EDGE, Target.ITEM)
	var icon: Texture2D = Art.item_tex[id]
	draw_texture(icon, (_item_center - icon.get_size() * 0.5).round(), Color(1, 1, 1, 1.0 if count > 0 else 0.35))
	var badge := str(count)
	var badge_pos := _item_center + Vector2(5, 5)
	draw_rect(Rect2(badge_pos - Vector2(2, 2), Vector2(Art.tiny_width(badge) + 4, 9)), INK)
	Art.draw_tiny(self, badge, badge_pos, FIRE_COLOR if count > 0 else EDGE)


func _draw_action_plate(center: Vector2, radius: float, color: Color, target: Target) -> void:
	var pressed := _buttons.find_key(target) != null
	_plate(center, radius, INK.lerp(color, 0.39) if pressed else INK, color)


func _draw_progress(center: Vector2, radius: float, progress: float, color: Color) -> void:
	if progress > 0.0:
		var end := -PI * 0.5 + TAU * minf(progress, 1.0)
		draw_arc(center, radius, -PI * 0.5, end, 24, color, 2.0)


func _draw_pause() -> void:
	var pressed := _buttons.find_key(Target.PAUSE) != null
	draw_rect(_pause_rect, INK.lerp(EDGE, 0.39) if pressed else INK)
	draw_rect(_pause_rect, EDGE, false, 1.0)
	for x in [5, 9]:
		draw_rect(Rect2(_pause_rect.position + Vector2(x, 4), Vector2(2, 8)), Color("#e0e7e7"))


func _draw_placement_button(rect: Rect2, label: String, color: Color, target: Target) -> void:
	var pressed := _buttons.find_key(target) != null
	draw_rect(Rect2(rect.position + Vector2(0, 2), rect.size), INK)
	draw_rect(rect, INK.lerp(color, 0.38 if pressed else 0.16))
	draw_rect(rect, color, false, 1.0)
	draw_rect(Rect2(rect.position + Vector2(3, 2), Vector2(rect.size.x - 6, 1)), Color(color, 0.42))
	Art.draw_text(self, label, Vector2(rect.get_center().x, rect.position.y + 5.0), 12, color, 1)
