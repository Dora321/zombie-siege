extends Control
## 战斗 HUD：血条、弹药、波次、小地图、公告和准星，全部用 _draw 绘制成像素风。

const DEFAULT_SIZE := Vector2(480, 270)
const COL_HP := Color("#d83838")
const COL_BASE := Color("#5a90d0")
const COL_ARMOR := Color("#c8d4e8")
const COL_DIM := Color(0, 0, 0, 0.55)
const BOSS_BAR_W := 200.0
const BAR_TOUCH_PADDING := 3.0
const TOUCH_MINIMAP_TOP := 46.0
const THROWABLE_RADII := {"frag": 44.0, "sticky": 38.0, "flash": 84.0, "decoy": 72.0}

var game: Node
var _title := ""
var _sub := ""
var _announce_t := 0.0
var _announce_dur := 1.0
var _hurt := 0.0
var _alert_t := 0.0
var _shown_coins := 0
var _flash_a := 0.0
var _flash_color := Color.WHITE
var _warns: Array[Dictionary] = []
var _view_size := DEFAULT_SIZE
var _safe_rect := Rect2(Vector2.ZERO, DEFAULT_SIZE)
var _touch := false
var _weapon_rects: Array[Dictionary] = []
var _item_rects: Array[Dictionary] = []


func setup(g: Node) -> void:
	game = g
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _hud_size() -> Vector2:
	return Vector2(size.x if size.x > 0.0 else DEFAULT_SIZE.x, size.y if size.y > 0.0 else DEFAULT_SIZE.y)


func _safe_bounds(view_size: Vector2) -> Rect2:
	var inset := Mobile.safe_insets(get_viewport())
	var top_left := Vector2(inset["left"], inset["top"])
	var bottom_right := Vector2(inset["right"], inset["bottom"])
	return Rect2(top_left, view_size - top_left - bottom_right)


func _slot_at(slots: Array[Dictionary], pos: Vector2, padding: float) -> String:
	for slot in slots:
		var rect: Rect2 = slot["rect"]
		if rect.grow(padding).has_point(pos):
			return slot["id"]
	return ""


## 供触控摇杆判断触点是否落在道具栏或武器栏。
func is_point_on_hud_bar(pos: Vector2) -> bool:
	return _slot_at(_weapon_rects, pos, BAR_TOUCH_PADDING) != "" or _slot_at(_item_rects, pos, BAR_TOUCH_PADDING) != ""


func _input(event: InputEvent) -> void:
	if not Mobile.is_touch() or game == null or game.player == null or not game.player_can_act() or get_tree().paused:
		return
	if not (event is InputEventScreenTouch and event.pressed):
		return
	var pos: Vector2 = event.position
	if not _safe_bounds(_hud_size()).has_point(pos):
		return
	# 先找实际按到的格子，再用扩大的范围接住格子边缘。
	var weapon := _slot_at(_weapon_rects, pos, 0.0)
	var item := _slot_at(_item_rects, pos, 0.0)
	if weapon.is_empty() and item.is_empty():
		weapon = _slot_at(_weapon_rects, pos, BAR_TOUCH_PADDING)
		item = _slot_at(_item_rects, pos, BAR_TOUCH_PADDING)
	if not weapon.is_empty():
		Mobile.latch_weapon_id = weapon
		Sfx.play("ui_hover")
	elif not item.is_empty():
		if item == game.player.selected_item:
			Mobile.latch_item_use = item
		else:
			Mobile.latch_item_select = item
			Sfx.play("ui_hover")
	else:
		return
	get_viewport().set_input_as_handled()


func announce(title: String, sub: String, duration: float) -> void:
	_title = title
	_sub = sub
	_announce_t = duration
	_announce_dur = duration


func flash_hurt() -> void:
	_hurt = 0.35


## 踩在酸液里时持续泛红，提醒玩家赶紧离开。
func flash_dot() -> void:
	_hurt = maxf(_hurt, 0.14)


func alert_base() -> void:
	_alert_t = 2.0


## 随机事件的预警条，显示在波次公告下面，不抢 Boss 公告的位置。最多同时两条。
func event_warn(title: String, sub: String, duration: float, color: Color) -> void:
	_warns.append({"title": title, "sub": sub, "t": duration, "dur": duration, "color": color})
	if _warns.size() > 2:
		_warns.pop_front()


## 闪光弹和核弹的全屏白闪。
func screen_flash(strength: float, color: Color) -> void:
	_flash_a = maxf(_flash_a, strength)
	_flash_color = color


func _process(dt: float) -> void:
	_announce_t -= dt
	_hurt = maxf(_hurt - dt, 0.0)
	_alert_t = maxf(_alert_t - dt, 0.0)
	_flash_a = maxf(_flash_a - dt * 2.2, 0.0)
	if not get_tree().paused:
		for i in range(_warns.size() - 1, -1, -1):
			_warns[i]["t"] = float(_warns[i]["t"]) - dt
			if float(_warns[i]["t"]) <= 0.0:
				_warns.remove_at(i)
	if game != null:
		_shown_coins = int(move_toward(_shown_coins, game.coins, maxf(1.0, dt * 200.0)))
	queue_redraw()


func _draw() -> void:
	_weapon_rects.clear()
	_item_rects.clear()
	if game == null or game.player == null:
		return
	_view_size = _hud_size()
	_safe_rect = _safe_bounds(_view_size)
	_touch = Mobile.is_touch()
	var in_shop: bool = game.state == game.State.SHOP
	_draw_vignette()
	var throwable_aiming: bool = _touch and Mobile.item_aiming and game.player_can_act() and not get_tree().paused
	if throwable_aiming:
		_draw_throwable_aim()
	if not in_shop:
		_draw_status()
		_draw_wave_info()
		_draw_money()
		_draw_weapons()
		_draw_items()
		_draw_minimap()
		_draw_base_pointer()
		_draw_crate_pointers()
		_draw_event_chips()
	if _flash_a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, _view_size), Color(_flash_color.r, _flash_color.g, _flash_color.b, minf(_flash_a, 0.9)))
	if _announce_t > 0.0 and not get_tree().paused:
		_draw_announce()
	if not get_tree().paused and not in_shop:
		_draw_event_warns()
	if _alert_t > 0.0 and int(_alert_t * 5.0) % 2 == 0 and not in_shop:
		var alert_y := 44.0 if game.boss_list.is_empty() else 51.0
		Art.draw_text(self, "基地遭到攻击！", Vector2(_view_size.x * 0.5, _safe_rect.position.y + alert_y), 12, Color("#ff7050"), 1)
	if game.state == game.State.PLACING:
		_draw_placement()
	elif game.player_can_act() and not get_tree().paused and not throwable_aiming:
		_draw_crosshair()


func _bar(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(rect.grow(1), Color(0.05, 0.04, 0.06))
	draw_rect(rect, Color(0.2, 0.18, 0.22))
	var fill := rect
	fill.size.x = roundf(rect.size.x * clampf(ratio, 0.0, 1.0))
	draw_rect(fill, color)
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, 1)), color.lightened(0.3))


func _draw_status() -> void:
	var p: Variant = game.player
	var b: Variant = game.base
	draw_set_transform(_safe_rect.position)
	draw_texture(Art.heart_tex, Vector2(4, 3))
	_bar(Rect2(15, 5, 74, 6), p.hp / p.max_hp, COL_HP if p.hp > p.max_hp * 0.3 or int(game.time_alive * 6.0) % 2 == 0 else Color("#ff9070"))
	var hp_txt := "%d/%d" % [roundi(p.hp), roundi(p.max_hp)]
	Art.draw_tiny(self, hp_txt, Vector2(92, 5), Color("#ffb0a0"))
	# 护甲：盖在血条上半部分
	if p.armor > 0.0:
		draw_rect(Rect2(15, 5, roundf(74.0 * p.armor / GameData.ARMOR_MAX), 2), COL_ARMOR)
		Art.draw_tiny(self, "+%d" % ceili(p.armor), Vector2(94 + Art.tiny_width(hp_txt), 5), COL_ARMOR)
	draw_texture(Art.shield_tex, Vector2(4, 14))
	_bar(Rect2(15, 16, 74, 6), b.hp / b.max_hp, COL_BASE)
	Art.draw_tiny(self, "%d/%d" % [roundi(b.hp), roundi(b.max_hp)], Vector2(92, 16), Color("#a0c8ff"))
	# 冲刺冷却
	var dash_ratio: float = 1.0 - clampf(p.dash_cd / p.dash_cd_base, 0.0, 1.0)
	_bar(Rect2(15, 26, 36, 2), dash_ratio, Color("#60d0e0") if dash_ratio >= 1.0 else Color("#3a7a88"))
	if _touch and Save.auto_fire_on:
		var label := "自动开火"
		var width := Art.font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var pill := Color("#32433b")
		draw_rect(Rect2(61, 23, width, 14), pill)
		draw_circle(Vector2(61, 30), 7, pill)
		draw_circle(Vector2(61 + width, 30), 7, pill)
		Art.draw_text(self, label, Vector2(61, 23), 12, Color("#bce8a8"))
	_draw_buffs(p)
	draw_set_transform(Vector2.ZERO)


## 生效中的药水：图标加剩余时间条。
func _draw_buffs(p: Variant) -> void:
	var y := 32
	for buff: Array in [["speed", p.buff_speed_t], ["damage", p.buff_damage_t], ["inf_ammo", p.buff_ammo_t]]:
		var left: float = buff[1]
		if left <= 0.0:
			continue
		var id: String = buff[0]
		draw_texture(Art.item_tex[id], Vector2(3, y))
		_bar(Rect2(15, y + 4, 30, 2), left / float(GameData.ITEMS[id]["power"]), Color("#f0d050"))
		y += 11


func _draw_wave_info() -> void:
	var left: int = game.zombies.size() + game._queue.size()
	var top_center := Vector2(_view_size.x * 0.5, _safe_rect.position.y)
	var label := "无尽 第 %d 波" % game.wave if game.endless else "第 %d / %d 波" % [game.wave, GameData.MAX_WAVE]
	var color := Color("#ffe060") if game.endless else Color("#f0ece0")
	Art.draw_text(self, label, top_center + Vector2(0, 2), 12, color, 1)
	# 危险等级和契约倍率，跟在波数后面
	if game.score_mult > 1.0:
		var label_end := Art.font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x * 0.5 + 4.0
		Art.draw_text(self, "危%d %s" % [game.danger, GameData.mult_text(game.score_mult)], top_center + Vector2(label_end, 2), 12, Color("#ff9070"))
	draw_texture(Art.skull_tex, top_center + Vector2(-18, 18))
	Art.draw_tiny(self, str(left), top_center + Vector2(-7, 20), Color("#f0a090"))
	if not game.boss_list.is_empty():
		_draw_boss_bar(game.boss_list[0], top_center)


## Boss 血条：名字和阶段写在下面，竖线标出换阶段的血量，护盾是盖在上面的绿条。
func _draw_boss_bar(boss: Variant, top_center: Vector2) -> void:
	var info: Dictionary = boss.boss_info()
	var rect := Rect2(top_center + Vector2(-BOSS_BAR_W * 0.5, 29), Vector2(BOSS_BAR_W, 7))
	var flashing: bool = boss._brain.untouchable() and int(Time.get_ticks_msec() / 90) % 2 == 0
	_bar(rect, boss.hp / boss.max_hp, Color("#fff0c0") if flashing else Color("#c02828"))
	var phases: Array = GameData.BOSSES[boss.kind]["phases"]
	for i in range(1, phases.size()):
		var x: float = rect.position.x + roundf(rect.size.x * float(phases[i]["at"]))
		draw_rect(Rect2(x, rect.position.y - 1, 1, rect.size.y + 2), Color("#f0ece0"))
	var shield: float = info["shield"]
	if shield > 0.0:
		draw_rect(Rect2(rect.position, Vector2(roundf(rect.size.x * shield), 2)), Color("#b0ff70"))
	var label := "%s  第 %d/%d 阶段：%s" % [info["title"], int(info["phase"]) + 1, int(info["count"]), info["name"]]
	# 专属机制的状态：在地下、再生中、反弹光环
	if String(info.get("status", "")) != "":
		label += "  [%s]" % info["status"]
	var col := Color("#b0ff70") if shield > 0.0 else (Color("#d8c0ff") if boss._brain.guarded() else Color("#ff9070"))
	Art.draw_text(self, label, top_center + Vector2(0, 37), 12, col, 1)


func _draw_money() -> void:
	var coin: Texture2D = Art.coin_frames[0]
	var txt := str(_shown_coins)
	var tw := Art.tiny_width(txt, 2)
	var top_right := Vector2(_safe_rect.end.x - (24.0 if _touch else 0.0), _safe_rect.position.y)
	draw_texture(coin, top_right + Vector2(-tw - 16, 3))
	Art.draw_tiny(self, txt, top_right + Vector2(-tw - 3, 5), Color(0, 0, 0, 0.8), 2)
	Art.draw_tiny(self, txt, top_right + Vector2(-tw - 4, 4), Color("#ffe060"), 2)
	var score_txt := str(game.score)
	Art.draw_text(self, "分数", top_right + Vector2(-Art.tiny_width(score_txt) - 8, 14), 12, Color("#c8c4b8"), 2)
	Art.draw_tiny(self, score_txt, top_right + Vector2(-Art.tiny_width(score_txt) - 4, 19), Color("#f0ece0"))
	if game.combo >= 3:
		var ratio: float = clampf(game.combo_t / game.COMBO_WINDOW, 0.0, 1.0)
		var label := "连杀 %d" % game.combo
		Art.draw_text(self, label, top_right + Vector2(-24, 28), 12, Color("#ffb040"), 2)
		Art.draw_tiny(self, "x%.1f" % game.combo_multiplier(), top_right + Vector2(-21, 33), Color("#ffb040"))
		draw_rect(Rect2(top_right + Vector2(-62, 42), Vector2(58.0 * ratio, 1)), Color("#ffb040"))


func _draw_weapons() -> void:
	var p: Variant = game.player
	# 只显示随身的枪，枪袋的空格画成暗框；当前武器的格子宽一些，放得下完整弹药数
	var owned: Array[String] = p.owned_weapons()
	var slot_w := 62
	var mini_w := 32
	var empty := maxi(int(p.weapon_slots) - owned.size(), 0)
	var total := slot_w + (owned.size() - 1 + empty) * (mini_w + 2)
	var x := floorf((_view_size.x - total) * 0.5)
	var y0 := _safe_rect.end.y - 24.0
	var slot_h := 23.0 if _touch else 21.0
	for i in empty:
		var hole := Rect2(x + total - (i + 1) * (mini_w + 2) + 2, y0, mini_w, slot_h)
		draw_rect(hole, Color(0.09, 0.08, 0.11, 0.4))
		draw_rect(hole, Color("#3a3840"), false, 1.0)
	for id: String in owned:
		var st: Dictionary = p.weapon_state[id]
		var selected: bool = id == p.weapon_id
		var evolved: bool = p.evolution(id) != ""
		var w := slot_w if selected else mini_w
		var rect := Rect2(x, y0, w, slot_h)
		_weapon_rects.append({"id": id, "rect": rect})
		x += w + 2
		draw_rect(rect, Color(0.09, 0.08, 0.11, 0.86) if not selected else Color(0.28, 0.14, 0.11, 0.92))
		draw_rect(rect, Color("#ffc050") if selected else (p.EVO_COLOR if evolved else Color("#55525c")), false, 1.0)
		Art.draw_tiny(self, str(GameData.WEAPON_ORDER.find(id) + 1), rect.position + Vector2(3, 3), Color("#ffc050") if selected else Color("#a0a0a8"))
		var gun: Dictionary = Art.guns[id]
		var tex: Texture2D = gun["tex"]
		draw_texture(tex, rect.position + Vector2(8, 1))
		var mag: int = st["mag"]
		var reserve: int = st["reserve"]
		var ammo_txt := ""
		if selected:
			ammo_txt = "%d/%s" % [mag, "--" if reserve < 0 else str(reserve)]
		else:
			ammo_txt = str(mag + maxi(reserve, 0))
		var ammo_col := Color("#f0ece0")
		if mag == 0 and (selected or reserve <= 0):
			ammo_col = Color("#ff6050")
		Art.draw_tiny(self, ammo_txt, rect.position + Vector2(3, 14), ammo_col)
		# 进化过的枪等级后面多个「+」，青色
		if selected and evolved:
			Art.draw_tiny(self, "%d+" % int(st["level"]), rect.position + Vector2(slot_w - 10, 3), p.EVO_COLOR)
		elif selected:
			Art.draw_tiny(self, "%d" % int(st["level"]), rect.position + Vector2(slot_w - 6, 3), Color("#70d080"))
		if selected and p.reload_t > 0.0:
			var ratio: float = 1.0 - p.reload_t / p.reload_total
			draw_rect(Rect2(rect.position.x + 1, rect.end.y - 2, (slot_w - 2) * ratio, 1), Color("#f0d050"))


## 道具栏：有存货的道具排成一行，选中的高亮并显示名字。
func _draw_items() -> void:
	var p: Variant = game.player
	var shown: Array[String] = []
	for id: String in GameData.ITEM_ORDER:
		if int(p.items[id]) > 0 or id == p.selected_item:
			shown.append(id)
	var cell_w := 24 if _touch else 20
	var cell_h := 20 if _touch else 12
	var total := shown.size() * (cell_w + 1)
	var x := floorf((_view_size.x - total) * 0.5)
	var y := _safe_rect.end.y - (48.0 if _touch else 38.0)
	var item_name: String = GameData.ITEMS[p.selected_item]["name"]
	var label := item_name if _touch else "Q %s" % item_name
	var label_y := y + (3.0 if _touch else -1.0)
	Art.draw_text(self, label, Vector2(x - 3, label_y), 12, Color("#ffc050"), 2)
	for id: String in shown:
		var selected: bool = id == p.selected_item
		var count: int = p.items[id]
		var spent: bool = count <= 0 or (id == "nuke" and game.nuke_wave == game.wave)
		var rect := Rect2(x, y, cell_w, cell_h)
		_item_rects.append({"id": id, "rect": rect})
		x += cell_w + 1
		draw_rect(rect, Color(0.28, 0.14, 0.11, 0.92) if selected else Color(0.09, 0.08, 0.11, 0.8))
		draw_rect(rect, Color("#ffc050") if selected else Color("#55525c"), false, 1.0)
		var icon_offset := Vector2(2, 5) if _touch else Vector2(0, 1)
		var count_offset := Vector2(14, 8) if _touch else Vector2(12, 4)
		draw_texture(Art.item_tex[id], rect.position + icon_offset, Color(1, 1, 1, 0.35) if spent else Color.WHITE)
		Art.draw_tiny(self, str(count), rect.position + count_offset, Color("#ff6050") if count <= 0 else Color("#f0ece0"))


func _draw_minimap() -> void:
	var map: Variant = game.map
	var mw: int = map.W
	var mh: int = map.H
	var origin := _view_size - Vector2(mw + 3, mh + 3)
	if _touch:
		origin = Vector2(_safe_rect.end.x - mw - 4, _safe_rect.position.y + TOUCH_MINIMAP_TOP)
	draw_rect(Rect2(origin - Vector2(1, 1), Vector2(mw + 2, mh + 2)), Color(0.75, 0.72, 0.65, 0.7), false, 1.0)
	var mini_bg := Color(String(GameData.MAPS[map.map_id]["mini"]))
	mini_bg.a = 0.72
	draw_rect(Rect2(origin, Vector2(mw, mh)), mini_bg)
	if map.minimap_tex != null:
		draw_texture(map.minimap_tex, origin)
	var tile: int = map.TILE
	for piece: Variant in map.pieces:
		if piece.alive and piece.kind != "barrel":
			var cell: int = piece.cell
			var c := Color("#b0aca0") if piece.kind == "wall" else Color("#a07840")
			draw_rect(Rect2(origin + Vector2(cell % mw, cell / mw), Vector2(1, 1)), c)
	draw_rect(Rect2(origin + Vector2(map.base_x0, map.base_y0), Vector2(4, 3)), COL_BASE)
	for t: Variant in game.turrets:
		draw_rect(Rect2(origin + (t.position / tile).floor(), Vector2(1, 1)), Color("#70e090"))
	# 电磁干扰时雷达失灵，小地图上看不到僵尸
	var radar_ok: bool = not game.events.jammed()
	for z: Variant in game.zombies:
		if z.cloaked() or not radar_ok:
			continue
		var col := Color("#ff4030") if not z.is_boss else Color("#ffe040")
		draw_rect(Rect2(origin + (z.position / tile).floor(), Vector2(1, 1)), col)
	for c: Variant in game.events.crates:
		if int(Time.get_ticks_msec() / 200) % 2 == 0:
			draw_rect(Rect2(origin + (c.pos / tile).floor() - Vector2(1, 1), Vector2(3, 3)), Color("#ffe060"))
	var pp: Vector2 = game.player.position / tile
	draw_rect(Rect2(origin + pp.floor() - Vector2(1, 1), Vector2(3, 3)), Color.WHITE)


func _draw_base_pointer() -> void:
	# 玩家跑远时，屏幕边缘指向基地
	var cam: Vector2 = game.camera.position
	var point: Vector2 = _view_size * 0.5 + game.base.position - cam + Vector2(0, -24)
	var to := point - _safe_rect.get_center()
	if _pointer_on_screen(to):
		return
	var at := _pointer_on_edge(to, Vector2(24, 40))
	var dir := to.normalized()
	var side := dir.orthogonal()
	var tip := at + dir * 5.0
	draw_colored_polygon(PackedVector2Array([tip, at + side * 3.0, at - side * 3.0]), COL_BASE)
	draw_texture(Art.shield_tex, (at - dir * 9.0 - Vector2(4, 4)).round())


## 屏幕外的补给箱：屏幕边缘画一个黄色箭头。
func _draw_crate_pointers() -> void:
	var cam: Vector2 = game.camera.position
	var center_offset := _view_size * 0.5 - _safe_rect.get_center()
	for c: Variant in game.events.crates:
		var to: Vector2 = c.pos - cam + center_offset
		if _pointer_on_screen(to):
			continue
		var at := _pointer_on_edge(to, Vector2(20, 44))
		var dir := to.normalized()
		var side := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([at + dir * 6.0, at + side * 4.0, at - side * 4.0]), Color("#ffe060"))
		draw_texture(Art.item_tex["ammo_crate"], (at - dir * 10.0 - Vector2(6, 5)).round())


func _pointer_on_screen(to: Vector2) -> bool:
	var half := _safe_rect.size * 0.5
	return absf(to.x) < half.x - 8 and absf(to.y) < half.y - 8


func _pointer_on_edge(to: Vector2, margin: Vector2) -> Vector2:
	var half := _safe_rect.size * 0.5 - margin
	var scale_x := half.x / maxf(absf(to.x), 0.01)
	var scale_y := half.y / maxf(absf(to.y), 0.01)
	return _safe_rect.get_center() + to * minf(scale_x, scale_y)


## 进行中的事件：桌面版显示在分数下方，触控版显示在雷达下方。
func _draw_event_chips() -> void:
	var y := _safe_rect.position.y + 45.0
	if _touch:
		y = _safe_rect.position.y + TOUCH_MINIMAP_TOP + float(game.map.H) + 4.0
	for chip: Dictionary in game.events.chips():
		var color: Color = chip["color"]
		Art.draw_text(self, String(chip["text"]), Vector2(_safe_rect.end.x - 4, y), 12, color, 2)
		y += 13
		var ratio: float = chip["ratio"]
		if ratio >= 0.0:
			draw_rect(Rect2(_safe_rect.end.x - 62, y, 58.0 * clampf(ratio, 0.0, 1.0), 1), color)
			y += 3


## 事件预警条：比波次公告小一号，放在公告下面。
func _draw_event_warns() -> void:
	var y := _safe_rect.position.y + 108.0
	var width := _view_size.x
	for warn: Dictionary in _warns:
		var left: float = warn["t"]
		var alpha := clampf(left * 2.5, 0.0, 1.0)
		var color: Color = warn["color"]
		draw_rect(Rect2(0, y, width, 28), Color(0, 0, 0, 0.55 * alpha))
		draw_rect(Rect2(_safe_rect.position.x, y, 3, 28), Color(color.r, color.g, color.b, alpha))
		draw_rect(Rect2(_safe_rect.end.x - 3, y, 3, 28), Color(color.r, color.g, color.b, alpha))
		Art.draw_text(self, "注意：%s" % warn["title"], Vector2(width * 0.5, y + 1.0), 12, Color(color.r, color.g, color.b, alpha), 1)
		Art.draw_text(self, String(warn["sub"]), Vector2(width * 0.5, y + 14.0), 12, Color(0.92, 0.9, 0.84, alpha), 1)
		y += 30.0


## 测试用：当前预警条的标题。
func event_warn_titles() -> Array[String]:
	var out: Array[String] = []
	for warn: Dictionary in _warns:
		out.append(String(warn["title"]))
	return out


func _draw_announce() -> void:
	var alpha := clampf(_announce_t * 2.5, 0.0, 1.0)
	var elapsed := _announce_dur - _announce_t
	var pop := clampf(elapsed * 6.0, 0.0, 1.0)
	var y := _safe_rect.position.y + lerpf(58.0, 66.0, pop)
	var width := _view_size.x
	draw_rect(Rect2(0, y - 4, width, 42), Color(0, 0, 0, 0.5 * alpha))
	draw_rect(Rect2(0, y - 4, width, 1), Color(1.0, 0.75, 0.3, 0.6 * alpha))
	draw_rect(Rect2(0, y + 37, width, 1), Color(1.0, 0.75, 0.3, 0.6 * alpha))
	Art.draw_text(self, _title, Vector2(width * 0.5, y), 24, Color(1.0, 0.85, 0.5, alpha), 1)
	Art.draw_text(self, _sub, Vector2(width * 0.5, y + 24), 12, Color(0.92, 0.9, 0.84, alpha), 1)


func _draw_vignette() -> void:
	if _hurt <= 0.0:
		return
	var w := _view_size.x
	var h := _view_size.y
	var a := _hurt * 1.3
	var c := Color(0.8, 0.05, 0.05, a * 0.6)
	draw_rect(Rect2(0, 0, w, 10), c)
	draw_rect(Rect2(0, h - 10, w, 10), c)
	draw_rect(Rect2(0, 10, 10, h - 20), c)
	draw_rect(Rect2(w - 10, 10, 10, h - 20), c)
	c.a *= 0.5
	draw_rect(Rect2(10, 10, w - 20, 6), c)
	draw_rect(Rect2(10, h - 16, w - 20, 6), c)
	draw_rect(Rect2(10, 16, 6, h - 32), c)
	draw_rect(Rect2(w - 16, 16, 6, h - 32), c)


func _draw_throwable_aim() -> void:
	var camera: Camera2D = game.camera
	var canvas := camera.get_canvas_transform()
	var hand: Vector2 = canvas * (game.player.global_position + Vector2(0, -7))
	var target := (canvas * Mobile.item_aim_world).round()
	var radius := float(THROWABLE_RADII.get(Mobile.item_aim_id, 0.0)) * canvas.x.length()
	var color := Color(1.0, 0.25, 0.25, 0.6) if Mobile.item_aim_cancel else Color(1.0, 0.8, 0.3, 0.65)
	var steps := maxi(4, ceili(hand.distance_to(target) / 9.0))
	for i in range(1, steps):
		var t := float(i) / steps
		var dot := hand.lerp(target, t) - Vector2(0, 72.0 * t * (1.0 - t))
		draw_rect(Rect2(dot.round(), Vector2(2, 2)), color)
	if radius > 0.0:
		draw_arc(target, radius, 0, TAU, 48, color, 1.0)
	draw_circle(target, 2.0, color)
	if Mobile.item_aim_cancel:
		var label_pos := Vector2(
			clampf(target.x, _safe_rect.position.x + 26.0, _safe_rect.end.x - 26.0),
			maxf(target.y - 18.0, _safe_rect.position.y + 2.0)
		)
		Art.draw_text(self, "松手取消", label_pos, 12, Color("#ff8070"), 1)


func _draw_crosshair() -> void:
	var p: Variant = game.player
	if _touch:
		var camera: Camera2D = game.camera
		var canvas := camera.get_canvas_transform()
		var locked: Variant = p.touch_lock_target
		if is_instance_valid(locked) and not bool(locked.dead) and not locked.cloaked() and not bool(locked.burrowed):
			var lock_pos: Vector2 = locked.center()
			var center: Vector2 = (canvas * lock_pos).round()
			var r := float(locked.hit_r) + 4.0
			var active_lock := Mobile.firing
			var lock_col := Color("#ff6050") if (active_lock and game.hit_marker_active()) else (Color("#ffc050") if active_lock else Color(1.0, 0.82, 0.45, 0.45))
			var arm := 3.0
			for sx: float in [-1.0, 1.0]:
				for sy: float in [-1.0, 1.0]:
					var corner: Vector2 = center + Vector2(sx * r, sy * r)
					draw_line(corner, corner - Vector2(sx * arm, 0.0), lock_col, 1.0)
					draw_line(corner, corner - Vector2(0.0, sy * arm), lock_col, 1.0)
		if Mobile.aiming or Mobile.firing:
			var aim: Vector2 = p.aim.normalized()
			var col := Color("#ff6050") if game.hit_marker_active() else Color(0.96, 0.92, 0.84, 0.85 if Mobile.aiming else 0.5)
			for dist: float in [20.0, 32.0]:
				var world: Vector2 = p.global_position + Vector2(0, -p.HAND_H) + aim * dist
				var at := (canvas * world).round()
				if dist > 25.0:
					var side := aim.orthogonal() * 2.5
					draw_rect(Rect2(at, Vector2(2, 2)), col)
					draw_rect(Rect2((at - aim * 3.0 + side).round(), Vector2.ONE), col)
					draw_rect(Rect2((at - aim * 3.0 - side).round(), Vector2.ONE), col)
				else:
					draw_rect(Rect2(at, Vector2(1, 1)), Color(col.r, col.g, col.b, col.a * 0.7))
		return
	var m := get_viewport().get_mouse_position().round()
	var gap: float = 3.0 + float(p.fired_kick) * 3.0
	var col := Color("#ff6050") if game.hit_marker_active() else Color("#f0ece0")
	var shade := Color(0, 0, 0, 0.7)
	for s: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		for k in 3:
			var at: Vector2 = (m + s * (gap + k)).round()
			draw_rect(Rect2(at + Vector2(1, 1), Vector2(1, 1)), shade)
			draw_rect(Rect2(at, Vector2(1, 1)), col)
	draw_rect(Rect2(m, Vector2(1, 1)), col)


func _draw_placement() -> void:
	var map: Variant = game.map
	var world: Vector2 = Mobile.place_world_pos if _touch else game.get_global_mouse_position() + Vector2(0, 4)
	var cell: int = map.cell_of(world)
	var top_left: Vector2 = map.cell_top_left(cell)
	var screen: Vector2 = top_left - game.camera.position - game.camera.offset + _view_size * 0.5
	var ok: bool = map.can_place_turret(cell)
	var c := Color(0.3, 1.0, 0.5, 0.5) if ok else Color(1.0, 0.25, 0.2, 0.5)
	draw_rect(Rect2(screen, Vector2(16, 16)), c)
	draw_rect(Rect2(screen, Vector2(16, 16)), Color(c.r, c.g, c.b, 1.0), false, 1.0)
	draw_texture(Art.turret_base_tex, screen + Vector2(0, 2), Color(1, 1, 1, 0.75))
	var range_center := screen + Vector2(8, 8)
	var r := 118.0 + 16.0 * (int(game.turret_level) - 1)
	draw_arc(range_center, r, 0, TAU, 48, Color(c.r, c.g, c.b, 0.4), 1.0)
	var top_center := Vector2(_view_size.x * 0.5, _safe_rect.position.y)
	var hint := "点击或拖动选格  左摇移动  确认或取消" if _touch else "左键放置炮塔  右键或 Esc 取消  WASD 可走动"
	draw_rect(Rect2(0, 0, _view_size.x, top_center.y + 34.0), COL_DIM)
	Art.draw_text(self, hint, top_center + Vector2(0, 3), 12, Color("#f0ece0"), 1)
	Art.draw_text(self, "可放在任意空地，炮塔会挡路也会吸引僵尸", top_center + Vector2(0, 18), 12, Color("#c8c4b8"), 1)
