extends Control
## 战斗 HUD：血条、弹药、波次、小地图、公告和准星，全部用 _draw 绘制成像素风。

const W := 480
const H := 270
const COL_HP := Color("#d83838")
const COL_BASE := Color("#5a90d0")
const COL_ARMOR := Color("#c8d4e8")
const COL_DIM := Color(0, 0, 0, 0.55)
const BOSS_BAR_W := 200.0

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


func setup(g: Node) -> void:
	game = g
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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
	if game == null or game.player == null:
		return
	var in_shop: bool = game.state == game.State.SHOP
	_draw_vignette()
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
		draw_rect(Rect2(0, 0, W, H), Color(_flash_color.r, _flash_color.g, _flash_color.b, minf(_flash_a, 0.9)))
	if _announce_t > 0.0 and not get_tree().paused:
		_draw_announce()
	if not get_tree().paused and not in_shop:
		_draw_event_warns()
	if _alert_t > 0.0 and int(_alert_t * 5.0) % 2 == 0 and not in_shop:
		Art.draw_text(self, "基地遭到攻击！", Vector2(W * 0.5, 44 if game.boss_list.is_empty() else 51), 12, Color("#ff7050"), 1)
	if game.state == game.State.PLACING:
		_draw_placement()
	elif game.player_can_act() and not get_tree().paused:
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
	_draw_buffs(p)


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
	Art.draw_text(self, "第 %d / %d 波" % [game.wave, GameData.MAX_WAVE], Vector2(W * 0.5, 2), 12, Color("#f0ece0"), 1)
	draw_texture(Art.skull_tex, Vector2(W * 0.5 - 18, 18))
	Art.draw_tiny(self, str(left), Vector2(W * 0.5 - 7, 20), Color("#f0a090"))
	if not game.boss_list.is_empty():
		_draw_boss_bar(game.boss_list[0])


## Boss 血条：名字和阶段写在下面，竖线标出换阶段的血量，护盾是盖在上面的绿条。
func _draw_boss_bar(boss: Variant) -> void:
	var info: Dictionary = boss.boss_info()
	var rect := Rect2(W * 0.5 - BOSS_BAR_W * 0.5, 29, BOSS_BAR_W, 7)
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
	Art.draw_text(self, label, Vector2(W * 0.5, 37), 12, col, 1)


func _draw_money() -> void:
	var coin: Texture2D = Art.coin_frames[0]
	var txt := str(_shown_coins)
	var tw := Art.tiny_width(txt, 2)
	draw_texture(coin, Vector2(W - tw - 16, 3))
	Art.draw_tiny(self, txt, Vector2(W - tw - 3, 5), Color(0, 0, 0, 0.8), 2)
	Art.draw_tiny(self, txt, Vector2(W - tw - 4, 4), Color("#ffe060"), 2)
	var score_txt := str(game.score)
	Art.draw_text(self, "分数", Vector2(W - Art.tiny_width(score_txt) - 8, 14), 12, Color("#c8c4b8"), 2)
	Art.draw_tiny(self, score_txt, Vector2(W - Art.tiny_width(score_txt) - 4, 19), Color("#f0ece0"))
	if game.combo >= 3:
		var ratio: float = clampf(game.combo_t / game.COMBO_WINDOW, 0.0, 1.0)
		var label := "连杀 %d" % game.combo
		Art.draw_text(self, label, Vector2(W - 24, 28), 12, Color("#ffb040"), 2)
		Art.draw_tiny(self, "x%.1f" % game.combo_multiplier(), Vector2(W - 21, 33), Color("#ffb040"))
		draw_rect(Rect2(W - 62, 42, 58.0 * ratio, 1), Color("#ffb040"))


func _draw_weapons() -> void:
	var p: Variant = game.player
	# 只显示随身的枪，枪袋的空格画成暗框；当前武器的格子宽一些，放得下完整弹药数
	var owned: Array[String] = p.owned_weapons()
	var slot_w := 62
	var mini_w := 32
	var empty := maxi(int(p.weapon_slots) - owned.size(), 0)
	var total := slot_w + (owned.size() - 1 + empty) * (mini_w + 2)
	var x := (W - total) / 2
	var y0 := H - 24
	for i in empty:
		var hole := Rect2(x + total - (i + 1) * (mini_w + 2) + 2, y0, mini_w, 21)
		draw_rect(hole, Color(0.09, 0.08, 0.11, 0.4))
		draw_rect(hole, Color("#3a3840"), false, 1.0)
	for id: String in owned:
		var st: Dictionary = p.weapon_state[id]
		var selected: bool = id == p.weapon_id
		var w := slot_w if selected else mini_w
		var rect := Rect2(x, y0, w, 21)
		x += w + 2
		draw_rect(rect, Color(0.09, 0.08, 0.11, 0.86) if not selected else Color(0.28, 0.14, 0.11, 0.92))
		draw_rect(rect, Color("#ffc050") if selected else Color("#55525c"), false, 1.0)
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
		if selected:
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
	var cell_w := 20
	var total := shown.size() * (cell_w + 1)
	var x := (W - total) / 2
	var y := H - 38
	Art.draw_text(self, "Q %s" % GameData.ITEMS[p.selected_item]["name"], Vector2(x - 3, y - 1), 12, Color("#ffc050"), 2)
	for id: String in shown:
		var selected: bool = id == p.selected_item
		var count: int = p.items[id]
		var spent: bool = count <= 0 or (id == "nuke" and game.nuke_wave == game.wave)
		var rect := Rect2(x, y, cell_w, 12)
		x += cell_w + 1
		draw_rect(rect, Color(0.28, 0.14, 0.11, 0.92) if selected else Color(0.09, 0.08, 0.11, 0.8))
		draw_rect(rect, Color("#ffc050") if selected else Color("#55525c"), false, 1.0)
		draw_texture(Art.item_tex[id], rect.position + Vector2(0, 1), Color(1, 1, 1, 0.35) if spent else Color.WHITE)
		Art.draw_tiny(self, str(count), rect.position + Vector2(12, 4), Color("#ff6050") if count <= 0 else Color("#f0ece0"))


func _draw_minimap() -> void:
	var map: Variant = game.map
	var mw: int = map.W
	var mh: int = map.H
	var origin := Vector2(W - mw - 3, H - mh - 3)
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
	var to: Vector2 = game.base.position - cam + Vector2(0, -24)
	if absf(to.x) < W * 0.5 - 8 and absf(to.y) < H * 0.5 - 8:
		return
	var center := Vector2(W, H) * 0.5
	var scale_x := (W * 0.5 - 24) / maxf(absf(to.x), 0.01)
	var scale_y := (H * 0.5 - 40) / maxf(absf(to.y), 0.01)
	var at := center + to * minf(scale_x, scale_y)
	var dir := to.normalized()
	var side := dir.orthogonal()
	var tip := at + dir * 5.0
	draw_colored_polygon(PackedVector2Array([tip, at + side * 3.0, at - side * 3.0]), COL_BASE)
	draw_texture(Art.shield_tex, (at - dir * 9.0 - Vector2(4, 4)).round())


## 屏幕外的补给箱：屏幕边缘画一个黄色箭头。
func _draw_crate_pointers() -> void:
	var cam: Vector2 = game.camera.position
	var center := Vector2(W, H) * 0.5
	for c: Variant in game.events.crates:
		var to: Vector2 = c.pos - cam
		if absf(to.x) < W * 0.5 - 8 and absf(to.y) < H * 0.5 - 8:
			continue
		var at := center + to * minf((W * 0.5 - 20) / maxf(absf(to.x), 0.01), (H * 0.5 - 44) / maxf(absf(to.y), 0.01))
		var dir := to.normalized()
		var side := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([at + dir * 6.0, at + side * 4.0, at - side * 4.0]), Color("#ffe060"))
		draw_texture(Art.item_tex["ammo_crate"], (at - dir * 10.0 - Vector2(6, 5)).round())


## 进行中的事件：右上角分数和连杀下面，一行一个。
func _draw_event_chips() -> void:
	var y := 45
	for chip: Dictionary in game.events.chips():
		var color: Color = chip["color"]
		Art.draw_text(self, String(chip["text"]), Vector2(W - 4, y), 12, color, 2)
		y += 13
		var ratio: float = chip["ratio"]
		if ratio >= 0.0:
			draw_rect(Rect2(W - 62, y, 58.0 * clampf(ratio, 0.0, 1.0), 1), color)
			y += 3


## 事件预警条：比波次公告小一号，放在公告下面。
func _draw_event_warns() -> void:
	var y := 108.0
	for warn: Dictionary in _warns:
		var left: float = warn["t"]
		var alpha := clampf(left * 2.5, 0.0, 1.0)
		var color: Color = warn["color"]
		draw_rect(Rect2(0, y, W, 28), Color(0, 0, 0, 0.55 * alpha))
		draw_rect(Rect2(0, y, 3, 28), Color(color.r, color.g, color.b, alpha))
		draw_rect(Rect2(W - 3, y, 3, 28), Color(color.r, color.g, color.b, alpha))
		Art.draw_text(self, "注意：%s" % warn["title"], Vector2(W * 0.5, y + 1.0), 12, Color(color.r, color.g, color.b, alpha), 1)
		Art.draw_text(self, String(warn["sub"]), Vector2(W * 0.5, y + 14.0), 12, Color(0.92, 0.9, 0.84, alpha), 1)
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
	var y := lerpf(58.0, 66.0, pop)
	draw_rect(Rect2(0, y - 4, W, 42), Color(0, 0, 0, 0.5 * alpha))
	draw_rect(Rect2(0, y - 4, W, 1), Color(1.0, 0.75, 0.3, 0.6 * alpha))
	draw_rect(Rect2(0, y + 37, W, 1), Color(1.0, 0.75, 0.3, 0.6 * alpha))
	Art.draw_text(self, _title, Vector2(W * 0.5, y), 24, Color(1.0, 0.85, 0.5, alpha), 1)
	Art.draw_text(self, _sub, Vector2(W * 0.5, y + 24), 12, Color(0.92, 0.9, 0.84, alpha), 1)


func _draw_vignette() -> void:
	if _hurt <= 0.0:
		return
	var a := _hurt * 1.3
	var c := Color(0.8, 0.05, 0.05, a * 0.6)
	draw_rect(Rect2(0, 0, W, 10), c)
	draw_rect(Rect2(0, H - 10, W, 10), c)
	draw_rect(Rect2(0, 10, 10, H - 20), c)
	draw_rect(Rect2(W - 10, 10, 10, H - 20), c)
	c.a *= 0.5
	draw_rect(Rect2(10, 10, W - 20, 6), c)
	draw_rect(Rect2(10, H - 16, W - 20, 6), c)
	draw_rect(Rect2(10, 16, 6, H - 32), c)
	draw_rect(Rect2(W - 16, 16, 6, H - 32), c)


func _draw_crosshair() -> void:
	var m := get_viewport().get_mouse_position().round()
	var p: Variant = game.player
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
	var world: Vector2 = game.get_global_mouse_position() + Vector2(0, 4)
	var cell: int = map.cell_of(world)
	var top_left: Vector2 = map.cell_top_left(cell)
	var screen: Vector2 = top_left - game.camera.position - game.camera.offset + Vector2(W, H) * 0.5
	var ok: bool = map.can_place_turret(cell)
	var c := Color(0.3, 1.0, 0.5, 0.5) if ok else Color(1.0, 0.25, 0.2, 0.5)
	draw_rect(Rect2(screen, Vector2(16, 16)), c)
	draw_rect(Rect2(screen, Vector2(16, 16)), Color(c.r, c.g, c.b, 1.0), false, 1.0)
	draw_texture(Art.turret_base_tex, screen + Vector2(0, 2), Color(1, 1, 1, 0.75))
	var range_center := screen + Vector2(8, 8)
	var r := 118.0 + 16.0 * (int(game.turret_level) - 1)
	draw_arc(range_center, r, 0, TAU, 48, Color(c.r, c.g, c.b, 0.4), 1.0)
	draw_rect(Rect2(0, 0, W, 34), COL_DIM)
	Art.draw_text(self, "左键放置炮塔  右键或 Esc 取消  WASD 可走动", Vector2(W * 0.5, 3), 12, Color("#f0ece0"), 1)
	Art.draw_text(self, "可放在任意空地，炮塔会挡路也会吸引僵尸", Vector2(W * 0.5, 18), 12, Color("#c8c4b8"), 1)
