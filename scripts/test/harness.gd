extends Node
## 开发自测入口。普通启动时什么都不做；带用户参数时驱动整局流程：
##   godot --headless --path . --fixed-fps 60 -- --bot --seed=3     机器人打一局并打印成绩
##   godot --headless --path . --fixed-fps 60 -- --flowtest         走完所有界面流程并校验
##   godot --headless --path . -- --sheet=DIR                       导出精灵预览 PNG
##   godot --path . -- --shots=DIR                                  窗口模式下自动截图
##   godot --path . --fixed-fps 60 -- --flowtest --flowshots=DIR    流程测试并给新武器道具截图

const BotScript := preload("res://scripts/test/bot.gd")
const Shop := preload("res://scripts/game/shop_catalog.gd")
const NEW_WEAPONS: Array[String] = ["sniper", "flamer", "grenade", "arc", "cryo", "boomerang"]

var bot: Variant = null
var fixed_seed := -1
var start_wave := 1

var _args := {}
var _game: Node
var _mode := ""
var _frames := 0
var _log_wave := 0
var _flow_step := 0
var _flow_wait := 0.0
var _input_pos := Vector2.ZERO
var _input_shots := 0
var _checks := 0
var _failures: Array[String] = []
var _shots_dir := ""
var _frame_ms := PackedFloat32Array()
var _last_frame_us := 0
var _peak_zombies := 0
var _shop_done := false
var _coroutine_wait := 0.0
var _arena_done := false
var _test_bot: Variant = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	if _args.is_empty():
		set_process(false)
		return
	fixed_seed = int(_args.get("seed", "-1"))
	if fixed_seed >= 0:
		seed(fixed_seed)
	start_wave = int(_args.get("wave", "1"))
	if _args.has("sheet"):
		_dump_sheets.call_deferred(String(_args["sheet"]))
	elif _args.has("fontcheck"):
		_font_check.call_deferred(String(_args["fontcheck"]))
	elif _args.has("flowtest"):
		_mode = "flow"
		if _args.has("flowshots"):
			_shots_dir = String(_args["flowshots"])
			DirAccess.make_dir_recursive_absolute(_shots_dir)
	elif _args.has("shots"):
		_mode = "shots"
		_shots_dir = String(_args["shots"])
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	elif _args.has("bot"):
		_mode = "bot"


## 自测在跑时窗口可能在后台，不能因失去焦点而自动暂停。
func automated() -> bool:
	return _mode != ""


func on_title_ready(title: Node) -> void:
	if (_mode == "bot" or _mode == "flow") and _flow_step == 0 and _game == null:
		_start_from_title.call_deferred(title)
	elif _mode == "shots":
		_run_shots_title()


func _start_from_title(title: Node) -> void:
	if not is_instance_valid(title):
		return
	if _mode == "flow":
		_check(title.get_node("%StartButton") != null, "标题有开始按钮")
		title._on_help()
		_check(title.help_panel.visible, "操作说明可打开")
		if _shots_dir != "":
			await _sec(0.1)
			await _save_shot("39_help")
		title.help_close.pressed.emit()
		_check(not title.help_panel.visible, "操作说明可关闭")
	title._on_start()


func on_game_ready(game: Node) -> void:
	_game = game
	if _mode == "shots":
		_run_shots_game()
	if _mode == "bot" or _mode == "shots":
		bot = BotScript.new(game)
		bot.skill = float(_args.get("skill", "1.0"))
		game.player.bot = bot
		game.god_mode = _args.has("god")
		if _args.has("godbase"):
			game.base_damage_scale = 0.0
		if _args.has("money"):
			game.coins = int(_args["money"])
	elif _mode == "flow":
		_flow_wait = 0.1


func on_shop_open(game: Node) -> void:
	if _mode == "bot" or _mode == "shots":
		print("[bot] 波 %d 结束 | 玩家 %d/%d 基地 %d/%d 金币 %d 分数 %d 击杀 %d 炮塔 %d" % [
			game.wave, roundi(game.player.hp), roundi(game.player.max_hp), roundi(game.base.hp), roundi(game.base.max_hp),
			game.coins, game.score, game.kills, game.turrets.size(),
		])
		if _mode == "shots":
			_shots_shop()
			return
		bot.shop()
		game.start_next_wave.call_deferred()


func _shots_shop() -> void:
	await get_tree().create_timer(0.4, true, false, true).timeout
	if not is_instance_valid(_game):
		return
	await _save_shot("15_shop_%d" % _game.wave)
	_game.shop_ui._select_tab(Shop.TAB_DEFENSE)
	await get_tree().create_timer(0.1, true, false, true).timeout
	await _save_shot("16_shop_defense")
	_game.begin_turret_placement()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _save_shot("17_placing")
	_game.cancel_turret_placement()
	bot.shop()
	_game.start_next_wave()


func on_game_over(game: Node) -> void:
	if _mode == "bot":
		print("[bot] 结束 | 胜利=%s 波次=%d 分数=%d 击杀=%d 命中=%d/%d 时长=%ds 原因=%s" % [
			game.victory, game.wave, game.score, game.kills, game.bullets.shots_hit, game.bullets.shots_fired,
			int(game.time_alive), game.end_reason,
		])
		_print_perf()
		get_tree().quit.call_deferred()


func _print_perf() -> void:
	if _frame_ms.is_empty():
		return
	_frame_ms.sort()
	var total := 0.0
	for v in _frame_ms:
		total += v
	print("[bot] 性能 | 同屏僵尸峰值 %d，单帧逻辑耗时 平均 %.2f ms，P99 %.2f ms，最大 %.2f ms（60fps 预算 16.67 ms）" % [
		_peak_zombies, total / _frame_ms.size(), _frame_ms[int(_frame_ms.size() * 0.99)], _frame_ms[_frame_ms.size() - 1],
	])


func _process(dt: float) -> void:
	_frames += 1
	if _mode == "bot" or _mode == "shots":
		if bot != null and is_instance_valid(_game):
			bot.tick(dt)
			# 无渲染的 headless 下，相邻两帧的真实间隔就是全部游戏逻辑的耗时
			var now := Time.get_ticks_usec()
			if _game.state == _game.State.COMBAT and _game.time_alive > 2.0 and _last_frame_us > 0:
				_frame_ms.append((now - _last_frame_us) / 1000.0)
				_peak_zombies = maxi(_peak_zombies, _game.zombies.size())
			_last_frame_us = now
	if _mode == "flow":
		_tick_flow(dt)
	if _frames > int(_args.get("maxframes", "2000000")):
		print("[harness] 超出最大帧数，退出")
		if is_instance_valid(_game):
			var g: Variant = _game
			print("state=%d wave=%d queue=%d zombies=%d player=%s hp=%d base=%d" % [g.state, g.wave, g._queue.size(), g.zombies.size(), g.player.position, g.player.hp, g.base.hp])
			for z: Variant in g.zombies:
				var c: int = g.map.cell_of(z.position)
				print("  %s pos=%s cell=(%d,%d) flag=%d next=%d dist=%d hp=%d" % [z.kind, z.position, c % g.map.W, c / g.map.W, g.map.flags[c], g.map.next_cell[c], g.map.dist[c], z.hp])
		get_tree().quit(2)


# ---------------------------------------------------------------------------
# 截图模式
# ---------------------------------------------------------------------------

func _save_shot(shot_name: String) -> void:
	# 窗口被遮挡时引擎不再绘制，frame_post_draw 永远等不到，要有超时
	var drawn := [false]
	RenderingServer.frame_post_draw.connect(func(): drawn[0] = true, CONNECT_ONE_SHOT)
	for i in 30:
		if drawn[0]:
			break
		await get_tree().process_frame
	if not drawn[0]:
		print("[shots] 窗口没有绘制，跳过 ", shot_name)
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots_dir.path_join(shot_name + ".png"))
	print("[shots] ", shot_name, " ", img.get_size())


func _shoot_later(shot_name: String, delay: float) -> void:
	await get_tree().create_timer(delay, true, false, true).timeout
	await _save_shot(shot_name)


## 按真实时间拍摄：标题 → 战斗若干张 → 商店 → 放炮塔 → 暂停 → 结算。
func _run_shots_title() -> void:
	await get_tree().create_timer(1.2, true, false, true).timeout
	await _save_shot("01_title")
	get_tree().current_scene._on_help()
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _save_shot("02_help")
	get_tree().current_scene.help_panel.visible = false
	get_tree().current_scene._on_start()


func _run_shots_game() -> void:
	var seconds: Array = _args.get("times", "25,40,55,70,85").split(",")
	var waited := 0.0
	for t: String in seconds:
		await get_tree().create_timer(float(t) - waited, true, false, true).timeout
		waited = float(t)
		await _save_shot("10_combat_%s" % t)
	_game.pause_ui.open()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _save_shot("20_pause")
	_game.pause_ui.close()
	_game.god_mode = false
	_game.player.hp = 1.0
	_game.player.invuln = 0.0
	_game.player.take_damage(50.0)
	await get_tree().create_timer(2.6, true, false, true).timeout
	await _save_shot("30_over")
	Sfx.quit_game()


# ---------------------------------------------------------------------------
# 字体校验：逐字确认游戏用到的汉字都能显示
# ---------------------------------------------------------------------------

func _font_check(chars_file: String) -> void:
	var text := FileAccess.get_file_as_string(chars_file)
	var theme_font: Font = Art.font
	var missing_theme := ""
	for i in text.length():
		if not theme_font.has_char(text.unicode_at(i)):
			missing_theme += text[i]
	print("[font] 主题字体 %s 校验 %d 字，缺字 %d: %s" % [theme_font.get_font_name(), text.length(), missing_theme.length(), missing_theme])
	get_tree().quit(0 if missing_theme.is_empty() else 1)


# ---------------------------------------------------------------------------
# 精灵导出
# ---------------------------------------------------------------------------

func _dump_sheets(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var sheet := Art.debug_sheet()
	sheet.resize(sheet.get_width() * 3, sheet.get_height() * 3, Image.INTERPOLATE_NEAREST)
	sheet.save_png(dir.path_join("sheet.png"))
	print("[sheet] saved to ", dir)
	get_tree().quit()


# ---------------------------------------------------------------------------
# 流程测试：不依赖键鼠，直接触发 UI 回调并校验结果
# ---------------------------------------------------------------------------

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("[flow] OK   ", label)
	else:
		print("[flow] FAIL ", label)
		_failures.append(label)


func _finish_flow() -> void:
	print("[flow] 校验 %d 项，失败 %d 项" % [_checks, _failures.size()])
	for f in _failures:
		print("[flow] 失败：", f)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _tick_flow(dt: float) -> void:
	if _game == null or not is_instance_valid(_game) or not _game.is_inside_tree():
		if _flow_step < 90:
			return
	_flow_wait -= dt
	if _flow_wait > 0.0:
		return
	_flow_wait = 0.05
	var g: Variant = _game
	match _flow_step:
		0:
			_check(g.state == g.State.COUNTDOWN and g.wave == 1, "开局进入第 1 波倒计时")
			_check(g.map.spawn_cells["top"].size() > 0, "地图有可达的出怪点")
			var reachable := 0
			for side: String in ["top", "bottom", "left", "right"]:
				reachable += g.map.spawn_cells[side].size()
			_check(reachable > 40, "四边出怪点足够多")
			_check(g.map.dist[g.map.idx(32, 18)] < g.map.FLOW_INF, "院内格子流场可达")
			var flow_t0 := Time.get_ticks_usec()
			for bench in 20:
				g.map.rebuild_flow()
			print("[flow] 流场重建平均耗时 %.2f ms" % ((Time.get_ticks_usec() - flow_t0) / 20000.0))
			_flow_step = 1
		1:
			g.pause_ui.open()
			_check(get_tree().paused, "暂停生效")
			g.pause_ui.close()
			_check(not get_tree().paused, "继续生效")
			g.player.switch_weapon("shotgun")
			_check(g.player.weapon_id == "shotgun", "切霰弹")
			g.player.switch_weapon("smg")
			_check(g.player.weapon_id == "smg", "切冲锋枪")
			g.player.weapon_state["smg"]["mag"] = 3
			g.player.start_reload()
			_check(g.player.reload_t > 0.0, "换弹开始")
			_flow_step = 2
			_flow_wait = 1.5
		2:
			_check(int(g.player.weapon_state["smg"]["mag"]) == g.player.mag_size(), "换弹完成且弹匣满")
			var reserve_ok: bool = int(g.player.weapon_state["smg"]["reserve"]) < 96
			_check(reserve_ok, "换弹消耗备弹")
			_input_pos = g.player.position
			_send_key(KEY_D, true)
			_flow_step = 20
			_flow_wait = 0.3
		20:
			_send_key(KEY_D, false)
			_check(g.player.position.x > _input_pos.x + 5.0, "真实按键 D 使玩家右移")
			_input_pos = g.player.position
			_send_key(KEY_W, true)
			_flow_step = 21
			_flow_wait = 0.3
		21:
			_send_key(KEY_W, false)
			_check(g.player.position.y < _input_pos.y - 5.0, "真实按键 W 使玩家上移")
			_send_key(KEY_1, true)
			_send_key(KEY_1, false)
			_flow_step = 22
			_flow_wait = 0.1
		22:
			_check(g.player.weapon_id == "pistol", "按键 1 切手枪")
			_send_key(KEY_2, true)
			_send_key(KEY_2, false)
			_flow_step = 23
			_flow_wait = 0.1
		23:
			_check(g.player.weapon_id == "shotgun", "按键 2 切霰弹枪")
			_send_key(KEY_3, true)
			_send_key(KEY_3, false)
			_flow_step = 24
			_flow_wait = 0.1
		24:
			_check(g.player.weapon_id == "smg", "按键 3 切冲锋枪")
			_send_key(KEY_4, true)
			_send_key(KEY_4, false)
			_flow_step = 241
			_flow_wait = 0.1
		241:
			_check(g.player.weapon_id == "smg", "未解锁的武器按键切不过去")
			_send_mouse(MOUSE_BUTTON_WHEEL_DOWN)
			_flow_step = 242
			_flow_wait = 0.1
		242:
			_check(g.player.weapon_id == "pistol", "滚轮跳过未解锁的武器")
			g.player.switch_weapon("smg")
			_input_shots = g.bullets.shots_fired
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			Input.parse_input_event(press)
			Input.flush_buffered_events()
			_flow_step = 25
			_flow_wait = 0.3
		25:
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.pressed = false
			Input.parse_input_event(release)
			Input.flush_buffered_events()
			_check(g.bullets.shots_fired > _input_shots, "按住鼠标左键能连发（%d 发）" % (g.bullets.shots_fired - _input_shots))
			g.player.weapon_state["smg"]["mag"] = 1
			_send_key(KEY_R, true)
			_send_key(KEY_R, false)
			_flow_step = 26
			_flow_wait = 0.05
		26:
			_check(g.player.reload_t > 0.0, "按键 R 开始换弹")
			g.player.dash_cd = 0.0
			_send_key(KEY_SHIFT, true)
			_send_key(KEY_SHIFT, false)
			_flow_step = 27
			_flow_wait = 0.05
		27:
			_check(g.player.dash_cd > 0.0, "按键 Shift 触发冲刺")
			_send_key(KEY_ESCAPE, true)
			_send_key(KEY_ESCAPE, false)
			_flow_step = 28
			_flow_wait = 0.05
		28:
			_check(get_tree().paused and g.pause_ui.visible, "按键 Esc 打开暂停")
			_send_key(KEY_ESCAPE, true)
			_send_key(KEY_ESCAPE, false)
			_flow_step = 29
			_flow_wait = 0.05
		29:
			_check(not get_tree().paused and not g.pause_ui.visible, "再按 Esc 继续游戏")
			_flow_step = 3
			_flow_wait = 2.0
		3:
			_check(g.state == g.State.COMBAT, "倒计时后进入战斗")
			# 每种僵尸都放一只，全部击杀，覆盖死亡逻辑
			g._queue.clear()
			for kind: String in GameData.ZOMBIES.keys():
				g._spawn_zombie(kind)
			_check(g.zombies.size() >= 6, "六种僵尸全部生成")
			_flow_step = 4
			_flow_wait = 4.0
		4:
			g.player.position = Vector2(32 * 16, 25 * 16)
			_check(g.zombies.size() >= 1, "僵尸存活并在移动")
			var moved := 0
			for z: Variant in g.zombies:
				if z._walk > 1.0:
					moved += 1
			_check(moved >= 3, "僵尸确实在走路（%d 只）" % moved)
			for z: Variant in g.zombies.duplicate():
				if not z.dead:
					z.take_damage(99999.0, Vector2.RIGHT, 10.0)
			_flow_step = 5
			_flow_wait = 0.6
		5:
			_check(g.kills >= 6, "击杀计数正确（%d）" % g.kills)
			_check(g.fx.particles.size() > 0 or g.decals._images.size() > 0, "死亡产生碎块或贴花")
			_flow_step = 6
			_flow_wait = 0.1
		6:
			_check(g.state == g.State.CLEARED, "全部清除后波次结束")
			_flow_step = 7
			_flow_wait = 2.6
		7:
			_check(g.state == g.State.SHOP and g.shop_ui.visible, "商店自动打开")
			_flow_shop_run(g)
			_flow_step = 70
		70:
			if not _shop_done:
				_flow_guard(g, "商店用例")
				return
			_flow_step = 8
			_flow_wait = 0.2
		8:
			var next: int = g.wave + 1
			g.shop_ui.start_button.pressed.emit()
			_check(g.state == g.State.COUNTDOWN and g.wave == next, "开始下一波")
			_check(not g.shop_ui.visible, "商店关闭")
			_flow_step = 9
			_flow_wait = 3.5
		9:
			_flow_wall_test(g)
			_flow_step = 10
			_flow_wait = 0.4
		10:
			_flow_explosion_test(g)
			_flow_arena(g)
			_flow_step = 40
		40:
			if not _arena_done:
				_flow_guard(g, "新武器用例")
				return
			_flow_step = 11
			_flow_wait = 0.1
		11:
			# 玩家死亡结算
			g.player.invuln = 0.0
			g.player.hp = 1.0
			var before: int = Save.scores.size()
			g.player.take_damage(50.0)
			_check(not g.player.alive and g.state == g.State.OVER, "玩家死亡进入结算")
			_check(Save.scores.size() >= mini(before + 1, Save.MAX_SCORES), "分数写入存档")
			var cfg := ConfigFile.new()
			_check(cfg.load(Save.path) == OK, "存档文件可读")
			_flow_step = 12
			_flow_wait = 2.5
		12:
			_check(g.over_ui.visible, "结算界面显示")
			_check(g.over_ui.stats_label.text.contains("最终分数"), "结算有分数文本")
			g.over_ui.retry_button.pressed.emit()
			_game = null
			_flow_step = 90
			_flow_wait = 0.4
		90:
			if _game == null:
				return
			_check(_game.state == _game.State.COUNTDOWN, "再来一局重新开始")
			_flow_step = 91
			_flow_wait = 0.2
		91:
			# 基地被毁
			_game.base.take_damage(99999.0)
			_check(_game.state == _game.State.OVER and _game.end_reason.contains("基地"), "基地被毁进入结算")
			_flow_step = 92
			_flow_wait = 2.5
		92:
			_check(_game.over_ui.visible, "基地被毁后结算界面显示")
			_game = null
			get_tree().change_scene_to_file("res://scenes/game.tscn")
			_flow_step = 93
			_flow_wait = 0.4
		93:
			if _game == null:
				return
			# 通关：跳到最后一波并清空
			_game.wave = GameData.MAX_WAVE
			_game._queue.clear()
			_game.state = _game.State.COMBAT
			_flow_step = 94
			_flow_wait = 0.3
		94:
			_check(_game.victory and _game.state == _game.State.OVER, "最后一波清空判定胜利")
			_flow_step = 95
			_flow_wait = 2.2
		95:
			_check(_game.over_ui.visible and _game.over_ui.title_label.text.contains("胜利"), "胜利结算")
			_game.over_ui.title_button.pressed.emit()
			_game = null
			_flow_step = 96
			_flow_wait = 0.4
		96:
			_check(get_tree().current_scene != null and get_tree().current_scene.name == "Title", "返回标题")
			_finish_flow()


## 用例是协程，中途报错就不会再往下走。等太久直接判失败退出，不要卡死。
func _flow_guard(_g: Variant, what: String) -> void:
	_coroutine_wait += 0.05
	if _coroutine_wait > 240.0:
		_check(false, "%s超时，协程可能中途报错" % what)
		_finish_flow()


func _send_key(key: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.keycode = key
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _send_mouse(button: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _flow_shop_run(g: Variant) -> void:
	await _flow_shop_test(g)
	_shop_done = true


func _flow_shop_test(g: Variant) -> void:
	# 钱够时每一个商品都买一遍
	g.coins = 200000
	g.base.hp = 100.0
	g.player.hp = 10.0
	var walls_before: float = g.map.missing_wall_hp()
	g.map.pieces[0].take_damage(9999.0)
	_check(not g.map.pieces[0].alive, "墙可被摧毁")
	_check(g.map.missing_wall_hp() > walls_before, "缺失耐久增加")
	for tab in Shop.TABS.size():
		g.shop_ui._select_tab(tab)
		_check(g.shop_ui.rows.get_child_count() >= 2, "商店第 %d 页有商品" % (tab + 1))
	g.shop_ui._select_tab(Shop.TAB_WEAPON)
	_check(g.shop_ui.rows.get_child_count() == GameData.WEAPON_ORDER.size(), "武器页列出全部 9 把枪")
	_check(not g.shop_buy("ammo_sniper"), "未解锁的武器买不了弹药")
	await _sec(0.1)
	var bar: VScrollBar = g.shop_ui.rows.get_parent().get_v_scroll_bar()
	_check(bar.visible and bar.size.x >= 3.0 and bar.max_value > bar.page, "商品放不下时滚动条可见（宽 %d）" % bar.size.x)
	if _shots_dir != "":
		await _sec(0.1)
		await _save_shot("40_shop_weapons")
		g.shop_ui._select_tab(Shop.TAB_ITEM)
		await _sec(0.1)
		await _save_shot("41_shop_items")
		g.shop_ui._select_tab(Shop.TAB_WEAPON)
	var ids: Array[String] = []
	for item: Dictionary in g.shop_items():
		ids.append(String(item["id"]))
	for id: String in ids:
		if id == "turret":
			continue
		var coins_before: int = g.coins
		var ok: bool = g.shop_buy(id)
		_check(ok and g.coins < coins_before, "购买 %s 成功且扣钱" % id)
	for id: String in NEW_WEAPONS:
		_check(g.player.owns_weapon(id), "%s 解锁成功" % id)
		var st: Dictionary = g.player.weapon_state[id]
		_check(int(st["mag"]) == int(g.player.stats[id]["mag"]), "%s 解锁后弹匣是满的" % id)
		if GameData.WEAPONS[id].has("ammo_pack"):
			var reserve_before: int = st["reserve"]
			_check(g.shop_buy("ammo_" + id) and int(st["reserve"]) > reserve_before, "解锁后可买 %s 弹药" % id)
		var level_before: int = st["level"]
		_check(g.shop_buy("up_" + id) and int(st["level"]) == level_before + 1, "%s 可升级" % id)
	_check(g.map.pieces[0].alive, "修墙后摧毁的墙重建")
	_check(g.map.missing_wall_hp() < 1.0, "修墙后满耐久")
	var lvl: int = g.player.weapon_state["pistol"]["level"]
	_check(lvl == 2, "武器升级生效")
	# 放炮塔
	g.shop_buy("turret")
	_check(g.state == g.State.PLACING and not g.shop_ui.visible, "进入炮塔放置模式")
	g.cancel_turret_placement()
	_check(g.state == g.State.SHOP and g.shop_ui.visible, "取消放置回到商店")
	g.shop_buy("turret")
	var wall_cell: int = g.map.pieces[0].cell
	_check(not g.try_place_turret(wall_cell), "墙上不能放炮塔")
	var ok_cell: int = g.map.idx(26, 17)
	_check(g.try_place_turret(ok_cell), "空地可放炮塔")
	_check(g.turrets.size() == 1 and g.state == g.State.SHOP, "炮塔放好回到商店")
	_check(g.map.blocks(ok_cell, g.map.BLOCK_ZOMBIE), "炮塔占格子")
	# 钱不够时不能买
	g.coins = 0
	_check(not g.shop_buy("up_smg"), "没钱不能升级")
	g.coins = 500


## 把僵尸放到墙外，确认它走到墙边后真的会啃墙；墙破后流场更新走缺口。
func _flow_wall_test(g: Variant) -> void:
	g._queue.clear()
	for z: Variant in g.zombies.duplicate():
		z.take_damage(99999.0, Vector2.RIGHT, 0.0)
	# 隔开一面墙和基地
	var wall_piece: Variant = null
	for piece: Variant in g.map.pieces:
		if piece.kind == "barricade":
			wall_piece = piece
			break
	var before_hp: float = wall_piece.hp
	wall_piece.take_damage(10.0)
	_check(wall_piece.hp < before_hp, "路障能受伤")
	var path_len_before: int = g.map.dist[g.map.idx(32, 2)]
	wall_piece.take_damage(99999.0)
	g.map.rebuild_flow()
	_check(g.map.dist[g.map.idx(32, 2)] <= path_len_before, "路障被毁后流场变短或不变")
	_check(g.map.next_cell[g.map.idx(32, 2)] >= 0, "流场有下一步")


# ---------------------------------------------------------------------------
# 新武器和道具：摆好僵尸，走真实的开火和使用路径，逐项校验
# ---------------------------------------------------------------------------

func _sec(t: float) -> void:
	await get_tree().create_timer(t, true, false, false).timeout


func _shot(shot_name: String) -> void:
	if _shots_dir != "":
		await _save_shot(shot_name)


## 把场地清干净，玩家站到院内下方那条空走廊的左端，面朝右。
func _arena_reset(g: Variant) -> void:
	for z: Variant in g.zombies.duplicate():
		z.no_blast = true
		z.take_damage(99999.0, Vector2.RIGHT, 0.0, false)
	g.ordnance.clear_field()
	g.bullets.clear_hazards()
	g.player.position = Vector2(25 * 16 + 8, 26 * 16 + 8)
	g.player.velocity = Vector2.ZERO
	g.player.hp = g.player.max_hp
	g.player.cooldown = 0.0
	g.player.reload_t = 0.0
	g.player.buff_ammo_t = 0.0
	g.player.buff_damage_t = 0.0
	g.player.buff_speed_t = 0.0
	g.player.armor = 0.0
	_test_bot.firing = false
	_test_bot.move = Vector2.ZERO
	_test_bot.aim_dir = Vector2.RIGHT
	_test_bot.aim_point = g.player.position + Vector2(100, -7)
	await _sec(0.05)


func _arena_spawn(g: Variant, kind: String, offset: Vector2) -> Node2D:
	g._spawn_zombie(kind)
	var z: Node2D = g.zombies[g.zombies.size() - 1]
	z.position = g.player.position + offset
	return z


func _hurt(z: Variant) -> bool:
	return not is_instance_valid(z) or z.dead or z.hp < z.max_hp


func _gone(z: Variant) -> bool:
	return not is_instance_valid(z) or z.dead


func _hold_fire(g: Variant, id: String, seconds: float) -> void:
	g.player.switch_weapon(id)
	await _sec(0.15)
	_test_bot.firing = true
	await _sec(seconds)
	_test_bot.firing = false


func _flow_arena(g: Variant) -> void:
	_test_bot = BotScript.new(g)
	g.player.bot = _test_bot
	g.god_mode = true
	g.pickups.enabled = false
	g.pickups.items.clear()
	# 院内的炮塔会打测试僵尸，干扰伤害断言
	for t: Variant in g.turrets:
		t.set_physics_process(false)
	# 占住出怪队列和倒计时，测试期间不会判定波次结束，也不会真的出怪
	g.state = g.State.COMBAT
	g.shop_ui.close()
	g._queue = ["walker"] as Array[String]
	g._spawn_t = 99999.0
	_check(g.map.line_clear(Vector2(25 * 16, 26 * 16 + 8), Vector2(38 * 16, 26 * 16 + 8), g.map.BLOCK_BULLET), "测试走廊没有障碍")
	await _arena_sniper(g)
	await _arena_flamer(g)
	await _arena_grenade(g)
	await _arena_arc(g)
	await _arena_cryo(g)
	await _arena_boomerang(g)
	await _arena_heal_items(g)
	await _arena_throwables(g)
	await _arena_buffs(g)
	await _arena_nuke(g)
	await _arena_drops(g)
	await _arena_keys(g)
	await _arena_reset(g)
	g.player.switch_weapon("pistol")
	g.player.bot = null
	g.god_mode = false
	g.pickups.enabled = true
	for t: Variant in g.turrets:
		t.set_physics_process(true)
	g._queue.clear()
	_arena_done = true


func _arena_sniper(g: Variant) -> void:
	await _arena_reset(g)
	var line := [_arena_spawn(g, "walker", Vector2(60, 0)), _arena_spawn(g, "walker", Vector2(100, 0)), _arena_spawn(g, "walker", Vector2(140, 0))]
	# 站定，免得截图等待时走出弹道
	for z: Variant in line:
		z.stun(2.0)
	await _sec(0.05)
	var st: Dictionary = g.player.weapon_state["sniper"]
	var mag: int = st["mag"]
	g.player.switch_weapon("sniper")
	await _sec(0.15)
	await _shot("50_sniper_laser")
	_test_bot.firing = true
	await _sec(0.03)
	_test_bot.firing = false
	await _shot("51_sniper_fire")
	_check(_gone(line[0]) and _gone(line[1]) and _gone(line[2]), "狙击枪一枪穿透 3 只僵尸")
	_check(int(st["mag"]) == mag - 1, "狙击枪开一枪耗一发")
	_check(g.player.cooldown > 0.5, "狙击枪开火慢")
	_check(not g.ordnance.traces.is_empty(), "狙击枪留下弹道")
	# 穿透上限：比上限多一只，最后一只不受伤
	await _arena_reset(g)
	var pierce: int = g.player.stats["sniper"]["pierce"]
	var row: Array = []
	for i in pierce + 2:
		row.append(_arena_spawn(g, "tank", Vector2(40 + i * 24, 0)))
	await _sec(0.05)
	st["mag"] = 5
	await _hold_fire(g, "sniper", 0.03)
	var hit := 0
	for z: Variant in row:
		if _hurt(z):
			hit += 1
	_check(hit == pierce + 1, "狙击枪穿透数符合等级（%d/%d）" % [hit, pierce + 1])
	# 穿过障碍：炸药桶在弹道上会被引爆
	var barrel: Variant = null
	for piece: Variant in g.map.pieces:
		if piece.kind == "barrel" and piece.alive:
			barrel = piece
			break
	if barrel == null:
		_check(false, "地图上有炸药桶可供测试")
	else:
		var hand: Vector2 = barrel.position + Vector2(-60, -14)
		g.ordnance.beam(hand, Vector2.RIGHT, 120.0, 10.0, 0.0, 0)
		await _sec(0.05)
		_check(not barrel.alive, "狙击枪引爆弹道上的炸药桶")


func _arena_flamer(g: Variant) -> void:
	await _arena_reset(g)
	var cluster := [_arena_spawn(g, "tank", Vector2(45, 0)), _arena_spawn(g, "tank", Vector2(45, 14)), _arena_spawn(g, "tank", Vector2(50, -14)), _arena_spawn(g, "tank", Vector2(30, 6))]
	var behind: Node2D = _arena_spawn(g, "tank", Vector2(-20, 0))
	var far: Node2D = _arena_spawn(g, "tank", Vector2(130, 0))
	await _sec(0.05)
	var st: Dictionary = g.player.weapon_state["flamer"]
	var fuel: int = st["mag"]
	await _hold_fire(g, "flamer", 0.6)
	await _shot("52_flamer")
	var burned := 0
	for z: Variant in cluster:
		if _hurt(z):
			burned += 1
	_check(burned == cluster.size(), "火焰同时烧到锥形内所有僵尸（%d/%d）" % [burned, cluster.size()])
	_check(not _hurt(behind), "火焰烧不到身后")
	_check(not _hurt(far), "火焰是短距武器")
	_check(int(st["mag"]) < fuel - 3, "火焰持续消耗燃料")
	_check(g.ordnance.fires.size() > 0, "地面留下火焰")
	# 踩进地面火的僵尸会持续掉血
	await _arena_reset(g)
	var patch_pos: Vector2 = g.player.position + Vector2(120, 0)
	g.ordnance.add_fire(patch_pos)
	var victim: Node2D = _arena_spawn(g, "tank", Vector2(120, 0))
	await _sec(0.6)
	_check(_hurt(victim), "地面火伤害站在上面的僵尸")
	await _sec(1.0)
	var hp_after: float = victim.hp if is_instance_valid(victim) else 0.0
	_check(hp_after < victim.max_hp, "僵尸燃烧持续掉血")


func _arena_grenade(g: Variant) -> void:
	await _arena_reset(g)
	var z: Node2D = _arena_spawn(g, "tank", Vector2(110, 0))
	var side: Node2D = _arena_spawn(g, "tank", Vector2(110, 20))
	await _sec(0.05)
	_test_bot.aim_point = z.center()
	g.player.switch_weapon("grenade")
	var base_hp: float = g.base.hp
	var blasts: int = g.fx.blasts.size()
	await _sec(0.15)
	_test_bot.firing = true
	await _sec(0.03)
	_test_bot.firing = false
	_check(g.ordnance.lobs.size() == 1, "榴弹发射后在空中飞")
	_check(not _hurt(z), "榴弹落地前不造成伤害")
	await _shot("53_grenade_air")
	await _sec(0.75)
	await _shot("54_grenade_blast")
	_check(g.ordnance.lobs.is_empty() and g.fx.blasts.size() >= blasts, "榴弹落地")
	_check(_hurt(z), "榴弹炸到落点的僵尸")
	_check(_hurt(side), "榴弹有范围伤害")
	_check(g.base.hp == base_hp, "榴弹不伤基地")
	# 落点限制在射程内
	_test_bot.aim_point = g.player.position + Vector2(5000, 0)
	await _sec(0.03)
	var land: Vector2 = g.player.lob_target(float(g.player.stats["grenade"]["range"]))
	_check(land.distance_to(g.player.position) < float(g.player.stats["grenade"]["range"]) + 10.0, "榴弹落点不超出射程")
	# 炸药桶连锁
	var barrel: Variant = null
	for piece: Variant in g.map.pieces:
		if piece.kind == "barrel" and piece.alive:
			barrel = piece
			break
	if barrel != null:
		g.ordnance.lob("grenade", barrel.position + Vector2(-30, -10), barrel.position + Vector2(0, -10), 20.0, 30.0)
		await _sec(0.4)
		_check(not barrel.alive, "榴弹能炸到炸药桶")


func _arena_arc(g: Variant) -> void:
	await _arena_reset(g)
	var chain := [_arena_spawn(g, "tank", Vector2(50, 0)), _arena_spawn(g, "tank", Vector2(90, 16)), _arena_spawn(g, "tank", Vector2(130, -10)), _arena_spawn(g, "tank", Vector2(170, 6))]
	var away: Node2D = _arena_spawn(g, "tank", Vector2(-90, 0))
	await _sec(0.05)
	var st: Dictionary = g.player.weapon_state["arc"]
	var mag: int = st["mag"]
	await _hold_fire(g, "arc", 0.03)
	await _shot("55_arc")
	var hit := 0
	for z: Variant in chain:
		if _hurt(z):
			hit += 1
	_check(hit == chain.size(), "电弧连跳到附近僵尸（%d/%d）" % [hit, chain.size()])
	_check(not _hurt(away), "电弧跳不到跳跃距离外")
	_check(int(st["mag"]) == mag - 1, "电弧开一枪耗一发")
	_check(chain[0].max_hp - chain[0].hp > chain[3].max_hp - chain[3].hp, "电弧每跳伤害递减")
	# 空放不算命中，也不报错
	await _arena_reset(g)
	await _hold_fire(g, "arc", 0.03)
	_check(not g.ordnance.traces.is_empty(), "电弧空放也有闪电")


func _arena_cryo(g: Variant) -> void:
	await _arena_reset(g)
	var z: Node2D = _arena_spawn(g, "tank", Vector2(70, 0))
	await _sec(0.05)
	await _hold_fire(g, "cryo", 0.25)
	await _sec(0.1)
	_check(z.vulnerability() > 1.0, "冰冻枪命中后减速且更吃伤害")
	_check(z._frozen_t <= 0.0 or z.vulnerability() == GameData.FREEZE_VULN, "减速和冻住的加成不同")
	await _hold_fire(g, "cryo", 1.0)
	await _sec(0.1)
	_check(z._frozen_t > 0.0, "持续命中后冻住")
	_check(z.vulnerability() == GameData.FREEZE_VULN, "冻住后受伤加成")
	await _shot("56_cryo_frozen")
	var pos: Vector2 = z.position
	await _sec(0.3)
	if z._frozen_t > 0.0:
		_check(z.position.distance_to(pos) < 1.0, "冻住时站着不动")
	# 炮塔打冻住的僵尸有额外加成
	await _arena_reset(g)
	var plain: Node2D = _arena_spawn(g, "tank", Vector2(40, -30))
	var frozen: Node2D = _arena_spawn(g, "tank", Vector2(40, 30))
	await _sec(0.05)
	frozen.apply_chill(1.0)
	var color := Color.WHITE
	for target: Node2D in [plain, frozen]:
		var from: Vector2 = target.center() + Vector2(-16, 0)
		g.bullets.fire(from, Vector2(300, 0), 10.0, 0.0, 0.2, 0, color, false)
	await _sec(0.15)
	var plain_loss: float = plain.max_hp - plain.hp
	var frozen_loss: float = frozen.max_hp - frozen.hp
	_check(plain_loss > 0.0 and frozen_loss > plain_loss * 2.0, "炮塔打冻住的僵尸伤害翻倍以上（%.0f / %.0f）" % [frozen_loss, plain_loss])
	# Boss 只减速不冻住
	await _arena_reset(g)
	var boss: Node2D = _arena_spawn(g, "boss", Vector2(60, 0))
	await _sec(0.05)
	boss.apply_chill(5.0)
	_check(boss._frozen_t <= 0.0 and boss.vulnerability() > 1.0, "Boss 不会被冻住，只减速")


func _arena_boomerang(g: Variant) -> void:
	await _arena_reset(g)
	var line := [_arena_spawn(g, "tank", Vector2(50, 0)), _arena_spawn(g, "tank", Vector2(100, 0))]
	await _sec(0.05)
	var st: Dictionary = g.player.weapon_state["boomerang"]
	var mag: int = st["mag"]
	await _hold_fire(g, "boomerang", 0.03)
	_check(int(st["mag"]) == mag - 1 and g.ordnance.rangs.size() == 1, "回旋镖扔出去")
	var hp_out: float = line[0].hp
	await _sec(0.3)
	await _shot("57_boomerang")
	_check(_hurt(line[0]) and _hurt(line[1]), "回旋镖穿透路上的僵尸")
	await _sec(1.6)
	_check(g.ordnance.rangs.is_empty(), "回旋镖飞回手里")
	_check(int(st["mag"]) == mag, "接住回旋镖后可以再扔")
	_check(line[0].hp < hp_out, "回旋镖回程也造成伤害")
	g.player.start_reload()
	_check(g.player.reload_t <= 0.0, "回旋镖不需要换弹")
	# 手里没镖时扔不出去，也不进换弹
	st["mag"] = 0
	var fired: int = g.bullets.shots_fired
	await _hold_fire(g, "boomerang", 0.05)
	_check(g.bullets.shots_fired == fired and g.player.reload_t <= 0.0, "没镖时不能再扔")
	st["mag"] = mag


func _arena_heal_items(g: Variant) -> void:
	await _arena_reset(g)
	var p: Variant = g.player
	p.items["medkit"] = 2
	p.hp = p.max_hp
	_test_bot.want_item = "medkit"
	await _sec(0.05)
	_check(int(p.items["medkit"]) == 2, "满血时医疗包不消耗")
	p.hp = 20.0
	_test_bot.want_item = "medkit"
	await _sec(0.05)
	_check(p.hp == 70.0 and int(p.items["medkit"]) == 1, "医疗包恢复 50 生命并扣数量")
	p.items["armor"] = 1
	_test_bot.want_item = "armor"
	await _sec(0.05)
	_check(p.armor == 50.0 and int(p.items["armor"]) == 0, "护甲板加 50 护甲")
	g.god_mode = false
	p.invuln = 0.0
	var hp_before: float = p.hp
	p.take_damage(30.0)
	_check(p.armor == 20.0 and p.hp == hp_before, "护甲先于生命承受伤害")
	p.invuln = 0.0
	p.take_damage(30.0)
	_check(p.armor == 0.0 and p.hp == hp_before - 10.0, "护甲打穿后余伤扣生命")
	g.god_mode = true
	p.items["ammo_crate"] = 1
	var smg: Dictionary = p.weapon_state["smg"]
	smg["mag"] = 0
	var reserve: int = smg["reserve"]
	_test_bot.want_item = "ammo_crate"
	await _sec(0.05)
	_check(int(smg["mag"]) == int(p.stats["smg"]["mag"]) and int(smg["reserve"]) > reserve, "弹药箱补满弹匣和备弹")
	_test_bot.want_item = "ammo_crate"
	await _sec(0.05)
	_check(int(p.items["ammo_crate"]) == 0, "没有道具时使用不会变成负数")


func _arena_throwables(g: Variant) -> void:
	await _arena_reset(g)
	var p: Variant = g.player
	# 手雷
	p.items["frag"] = 3
	var target: Node2D = _arena_spawn(g, "tank", Vector2(100, 0))
	await _sec(0.05)
	_test_bot.aim_point = target.center()
	_test_bot.want_item = "frag"
	await _sec(0.05)
	_check(int(p.items["frag"]) == 2, "手雷扣数量")
	_check(not _hurt(target), "手雷落地后才爆")
	await _sec(1.2)
	_check(_hurt(target), "手雷炸到僵尸")
	# 粘性炸弹跟着僵尸走
	await _arena_reset(g)
	p.items["sticky"] = 1
	var stuck: Node2D = _arena_spawn(g, "tank", Vector2(90, 0))
	await _sec(0.05)
	_test_bot.aim_point = stuck.center()
	_test_bot.want_item = "sticky"
	await _sec(0.6)
	_check(g.ordnance.bombs.size() == 1 and g.ordnance.bombs[0].target == stuck, "粘性炸弹粘到僵尸身上")
	await _shot("58_sticky")
	stuck.position += Vector2(30, 0)
	await _sec(0.1)
	_check(g.ordnance.bombs[0].pos.distance_to(stuck.center()) < 1.0, "粘性炸弹跟着僵尸移动")
	await _sec(1.5)
	_check(g.ordnance.bombs.is_empty() and _hurt(stuck), "粘性炸弹延时爆炸")
	var sticky_loss: float = stuck.max_hp - stuck.hp if is_instance_valid(stuck) else stuck.max_hp
	_check(sticky_loss > 80.0, "粘性炸弹是重伤（%.0f）" % sticky_loss)
	# 闪光弹眩晕
	await _arena_reset(g)
	p.items["flash"] = 1
	var walker: Node2D = _arena_spawn(g, "walker", Vector2(90, 0))
	var boss: Node2D = _arena_spawn(g, "boss", Vector2(90, 30))
	await _sec(0.05)
	_test_bot.aim_point = walker.center()
	_test_bot.want_item = "flash"
	await _sec(0.9)
	_check(walker._stun_t > 0.5, "闪光弹眩晕范围内的僵尸")
	_check(boss._stun_t < walker._stun_t, "Boss 眩晕时间打折")
	await _shot("59_flash")
	var at: Vector2 = walker.position
	await _sec(0.3)
	_check(walker.position.distance_to(at) < 1.0, "眩晕时站着不动")
	# 诱饵吸引僵尸
	await _arena_reset(g)
	p.items["decoy"] = 1
	_test_bot.aim_point = p.position + Vector2(100, -7)
	_test_bot.want_item = "decoy"
	await _sec(0.7)
	_check(g.ordnance.decoys.size() == 1, "诱饵落地")
	# 僵尸站在玩家和诱饵的另一侧，离玩家更近也要走向诱饵
	var drawn: Node2D = _arena_spawn(g, "walker", Vector2(170, 0))
	var before: float = drawn.position.distance_to(g.ordnance.decoys[0].pos)
	await _sec(1.0)
	await _shot("60_decoy")
	_check(drawn.position.distance_to(g.ordnance.decoys[0].pos) < before - 5.0, "僵尸走向诱饵")
	await _sec(3.0)
	_check(drawn.position.distance_to(g.ordnance.decoys[0].pos) < 20.0, "僵尸贴到诱饵上啃")
	var decoy_hp: float = g.ordnance.decoys[0].hp
	_check(decoy_hp < g.ordnance.DECOY_HP, "僵尸会啃诱饵")
	g.ordnance.decoys[0].t = 0.01
	await _sec(0.1)
	_check(g.ordnance.decoys.is_empty(), "诱饵到时消失")
	_check(drawn._lure == null or not drawn._lure.alive, "诱饵没了僵尸不再被吸引")


func _arena_buffs(g: Variant) -> void:
	await _arena_reset(g)
	var p: Variant = g.player
	# 速度药水
	var base_speed: float = p.move_speed()
	p.items["speed"] = 1
	_test_bot.want_item = "speed"
	await _sec(0.05)
	_check(p.buff_speed_t > 0.0 and p.move_speed() > base_speed * 1.3, "速度药水提升移速")
	var from_x: float = p.position.x
	_test_bot.move = Vector2.RIGHT
	await _sec(0.5)
	_test_bot.move = Vector2.ZERO
	_check(p.position.x - from_x > base_speed * 0.5, "加速后实际走得更快（%.0f）" % (p.position.x - from_x))
	p.buff_speed_t = 0.01
	await _sec(0.05)
	_check(p.move_speed() == base_speed, "速度药水到时失效")
	# 伤害药水：同一把手枪对比伤害
	await _arena_reset(g)
	var plain: Node2D = _arena_spawn(g, "tank", Vector2(50, 0))
	await _sec(0.05)
	p.weapon_state["pistol"]["mag"] = 12
	await _hold_fire(g, "pistol", 0.03)
	await _sec(0.15)
	var plain_loss: float = plain.max_hp - plain.hp
	await _arena_reset(g)
	var boosted: Node2D = _arena_spawn(g, "tank", Vector2(50, 0))
	await _sec(0.05)
	p.items["damage"] = 1
	_test_bot.want_item = "damage"
	await _sec(0.05)
	await _hold_fire(g, "pistol", 0.03)
	await _sec(0.15)
	var boosted_loss: float = boosted.max_hp - boosted.hp
	_check(boosted_loss > plain_loss * 1.4, "伤害药水提升武器伤害（%.0f -> %.0f）" % [plain_loss, boosted_loss])
	# 无限弹药
	await _arena_reset(g)
	p.items["inf_ammo"] = 1
	var smg: Dictionary = p.weapon_state["smg"]
	smg["mag"] = 0
	var reserve: int = smg["reserve"]
	_test_bot.want_item = "inf_ammo"
	await _sec(0.05)
	var fired: int = g.bullets.shots_fired
	await _hold_fire(g, "smg", 0.4)
	_check(g.bullets.shots_fired > fired + 2, "无限弹药时空弹匣也能开火")
	_check(int(smg["mag"]) == 0 and int(smg["reserve"]) == reserve, "无限弹药不耗弹")
	_check(p.reload_t <= 0.0, "无限弹药时不换弹")
	await _shot("61_buffs")
	p.buff_ammo_t = 0.0
	smg["mag"] = int(p.stats["smg"]["mag"])


func _arena_nuke(g: Variant) -> void:
	await _arena_reset(g)
	var p: Variant = g.player
	p.items["nuke"] = 2
	g.nuke_wave = 0
	_test_bot.want_item = "nuke"
	await _sec(0.05)
	_check(int(p.items["nuke"]) == 2, "场上没僵尸时核弹不消耗")
	var small := [_arena_spawn(g, "walker", Vector2(60, 0)), _arena_spawn(g, "runner", Vector2(120, 0)), _arena_spawn(g, "exploder", Vector2(30, 0)), _arena_spawn(g, "spitter", Vector2(170, 0))]
	var tank: Node2D = _arena_spawn(g, "tank", Vector2(100, 40))
	var boss: Node2D = _arena_spawn(g, "boss", Vector2(160, -30))
	var far: Node2D = _arena_spawn(g, "walker", Vector2(0, 0))
	far.position = Vector2(4, 4) * 16.0
	await _sec(0.05)
	var hp_before: float = p.hp
	_test_bot.want_item = "nuke"
	await _sec(0.05)
	_check(int(p.items["nuke"]) == 1 and g.nuke_wave == g.wave, "核弹使用后扣数量并记录波次")
	await _shot("62_nuke")
	await _sec(2.0)
	var all_dead := true
	for z: Variant in small:
		all_dead = all_dead and _gone(z)
	_check(all_dead, "核弹清掉普通僵尸")
	_check(_gone(far), "核弹清屏不限距离")
	_check(not _gone(boss) and _hurt(boss), "核弹不秒 Boss 但重创")
	_check(not _gone(tank) and _hurt(tank), "核弹不秒坦克但重创")
	_check(p.hp == hp_before, "核弹不伤玩家（含自爆僵尸）")
	_check(not g.ordnance.nuke_active(), "冲击波结束")
	_check(int(p.items["nuke"]) == 1, "冲击波结束后数量不变")
	_test_bot.want_item = "nuke"
	await _sec(0.05)
	_check(int(p.items["nuke"]) == 1, "同一波不能再用核弹")
	g.nuke_wave = 0


func _arena_drops(g: Variant) -> void:
	await _arena_reset(g)
	var p: Variant = g.player
	g.pickups.enabled = true
	p.items["flash"] = 0
	g.pickups.drop(p.position, "item", 1, "flash")
	await _sec(1.2)
	_check(int(p.items["flash"]) == 1, "捡到掉落的道具")
	p.items["flash"] = int(GameData.ITEMS["flash"]["max"])
	var coins: int = g.coins
	g.pickups.drop(p.position, "item", 1, "flash")
	await _sec(1.2)
	_check(int(p.items["flash"]) == int(GameData.ITEMS["flash"]["max"]) and g.coins == coins + GameData.ITEM_OVERFLOW_COINS, "道具带满时折算金币")
	var seen := {}
	for i in 20000:
		var entry := GameData.roll_drop("walker")
		if entry.has("item"):
			seen[entry["item"]] = true
	_check(seen.size() == GameData.DROPS.size() - 2, "掉落表覆盖全部道具（%d 种）" % seen.size())
	_check(GameData.roll_drop("boss").has("item"), "Boss 必掉道具")
	g.pickups.enabled = false
	# 商店买道具遵守上限
	p.items["medkit"] = int(GameData.ITEMS["medkit"]["max"])
	g.coins = 5000
	_check(not g.shop_buy("item_medkit"), "道具带满后买不了")
	p.items["medkit"] = 0
	_check(g.shop_buy("item_medkit") and int(p.items["medkit"]) == 1, "商店能买道具")
	p.items["frag"] = int(GameData.ITEMS["frag"]["max"]) - 1
	_check(g.shop_buy("item_frag") and int(p.items["frag"]) == int(GameData.ITEMS["frag"]["max"]), "成包购买不超过上限")


## 真实按键：不经过机器人，走 _unhandled_input 和 InputMap。
func _arena_keys(g: Variant) -> void:
	await _arena_reset(g)
	var p: Variant = g.player
	p.bot = null
	await _sec(0.05)
	var keys: Array[Key] = [KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
	for i in keys.size():
		_send_key(keys[i], true)
		_send_key(keys[i], false)
		await _sec(0.05)
		_check(p.weapon_id == NEW_WEAPONS[i], "按键 %d 切到 %s" % [i + 4, NEW_WEAPONS[i]])
	_send_mouse(MOUSE_BUTTON_WHEEL_UP)
	await _sec(0.05)
	_check(p.weapon_id == "cryo", "滚轮能切回新武器")
	for id: String in GameData.ITEM_ORDER:
		p.items[id] = 0
	p.items["armor"] = 2
	p.items["speed"] = 2
	p.selected_item = "armor"
	_send_key(KEY_E, true)
	_send_key(KEY_E, false)
	await _sec(0.05)
	_check(p.selected_item == "speed", "E 切到下一个有存货的道具")
	_send_key(KEY_E, true)
	_send_key(KEY_E, false)
	await _sec(0.05)
	_check(p.selected_item == "armor", "E 跳过没有存货的道具")
	_send_key(KEY_Q, true)
	_send_key(KEY_Q, false)
	await _sec(0.05)
	_check(int(p.items["armor"]) == 1 and p.armor > 0.0, "Q 使用当前道具")
	_send_mouse(MOUSE_BUTTON_MIDDLE)
	await _sec(0.05)
	_check(int(p.items["armor"]) == 0, "鼠标中键使用当前道具")
	_check(p.selected_item == "speed", "用完自动切到下一种")
	p.items["medkit"] = 1
	p.hp = 10.0
	_send_key(KEY_0, true)
	_send_key(KEY_0, false)
	await _sec(0.05)
	_check(int(p.items["medkit"]) == 0 and p.hp > 10.0, "按键 0 用医疗包")
	p.items["frag"] = 1
	_send_key(KEY_MINUS, true)
	_send_key(KEY_MINUS, false)
	await _sec(0.05)
	_check(int(p.items["frag"]) == 0, "按键 - 扔手雷")
	p.items["nuke"] = 1
	_arena_spawn(g, "walker", Vector2(60, 0))
	await _sec(0.05)
	_send_key(KEY_EQUAL, true)
	_send_key(KEY_EQUAL, false)
	await _sec(0.05)
	_check(int(p.items["nuke"]) == 0 and g.ordnance.nuke_active(), "按键 = 放核弹")
	await _sec(2.0)
	g.nuke_wave = 0
	for id: String in GameData.ITEM_ORDER:
		p.items[id] = 2
	p.selected_item = "frag"
	await _sec(0.05)
	await _shot("63_hud_items")
	p.bot = _test_bot


func _flow_explosion_test(g: Variant) -> void:
	var count_before: int = g.fx.blasts.size()
	g.explode(g.player.position + Vector2(200, 0), 30.0, 40.0, false)
	_check(g.fx.blasts.size() == count_before + 1, "爆炸特效生成")
