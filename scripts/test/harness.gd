extends Node
## 开发自测入口。普通启动时什么都不做；带用户参数时驱动整局流程：
##   godot --headless --path . --fixed-fps 60 -- --bot --seed=3     机器人打一局并打印成绩
##   godot --headless --path . --fixed-fps 60 -- --flowtest         走完所有界面流程并校验
##   godot --headless --path . -- --sheet=DIR                       导出精灵预览 PNG
##   godot --path . -- --shots=DIR                                  窗口模式下自动截图
##   godot --path . --fixed-fps 60 -- --flowtest --flowshots=DIR    流程测试并给新武器道具截图
##   godot --headless --path . --fixed-fps 60 -- --maptest --seed=1 三张地图和全部随机事件的校验
## 机器人和截图模式可加 --map=parking|alley 选图，--event=night 等每波固定事件，--noevents 关事件

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
var _kind_kills := {}


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
	if GameData.MAPS.has(String(_args.get("map", ""))):
		Save.map_id = String(_args["map"])
	if _args.has("sheet"):
		_dump_sheets.call_deferred(String(_args["sheet"]))
	elif _args.has("fontcheck"):
		_font_check.call_deferred(String(_args["fontcheck"]))
	elif _args.has("maptest"):
		_mode = "map"
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


## 机器人模式下打印 Boss 战的关键事件，用来确认阶段和招式都真的走到了。
func note(text: String) -> void:
	if _mode == "bot":
		print("[bot] ", text)


func on_kill(kind: String) -> void:
	if _mode == "bot":
		_kind_kills[kind] = int(_kind_kills.get(kind, 0)) + 1


func on_title_ready(title: Node) -> void:
	if (_mode == "bot" or _mode == "flow") and _flow_step == 0 and _game == null:
		_start_from_title.call_deferred(title)
	elif _mode == "shots":
		_run_shots_title()
	elif _mode == "map" and _game == null and _checks == 0:
		_run_map_test.call_deferred(title)


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
		title._on_bestiary()
		_check(title.bestiary_panel.visible, "僵尸图鉴可打开")
		var shown := {}
		for page: Dictionary in title.bestiary_panel.PAGES:
			for kind: String in page["kinds"]:
				shown[kind] = true
		_check(shown.size() == GameData.ZOMBIES.size(), "图鉴收录全部敌人（%d/%d）" % [shown.size(), GameData.ZOMBIES.size()])
		for i in title.bestiary_panel.PAGES.size():
			if _shots_dir != "":
				await _sec(0.1)
				await _save_shot("38_bestiary_%d" % i)
			title.bestiary_panel.turn(1)
		_check(title.bestiary_panel.page == 0, "图鉴翻页能循环")
		title.bestiary_panel.close_button.pressed.emit()
		_check(not title.bestiary_panel.visible, "僵尸图鉴可关闭")
		title._on_start()
		_check(title.map_panel.visible, "开始游戏先打开选图")
		title.map_panel.choose(Save.map_id)
		return
	title.start_game(Save.map_id)


func on_game_ready(game: Node) -> void:
	_game = game
	# 流程测试的数量断言不能被随机事件干扰；事件有 --maptest 专门校验
	game.events.enabled = not (_mode == "flow" or _mode == "map" or _args.has("noevents"))
	game.events.forced = String(_args.get("event", ""))
	if _mode == "bot":
		print("[bot] 地图 %s，种子 %d" % [game.map.map_id, fixed_seed])
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
		print("[bot] 波 %d 结束 | 玩家 %d/%d 基地 %d/%d 金币 %d 分数 %d 击杀 %d 炮塔 %d 累计时长 %ds" % [
			game.wave, roundi(game.player.hp), roundi(game.player.max_hp), roundi(game.base.hp), roundi(game.base.max_hp),
			game.coins, game.score, game.kills, game.turrets.size(), int(game.time_alive),
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
		print("[bot] 各种僵尸击杀 ", _kind_kills)
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
	get_tree().current_scene.start_game(Save.map_id)


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
	g.hazards.clear()
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
	_arena_wave_table(g)
	await _arena_stalker(g)
	await _arena_shielder(g)
	await _arena_splitter(g)
	await _arena_summoner(g)
	await _arena_screamer(g)
	await _arena_balloon(g)
	await _arena_boss_phases(g)
	await _arena_boss_moves(g)
	await _arena_boss_warnings(g)
	await _arena_boss_break(g)
	await _arena_boss_loot(g)
	await _arena_specials(g)
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


# ---------------------------------------------------------------------------
# 新敌人和 Boss：摆好场景，走真实的开火和结算路径
# ---------------------------------------------------------------------------

func _arena_wave_table(_g: Variant) -> void:
	var seen := {}
	for i in GameData.WAVES.size():
		var q: Array[String] = GameData.build_spawn_queue(i + 1)
		for kind: String in q:
			seen[kind] = mini(int(seen.get(kind, i + 1)), i + 1)
	_check(GameData.WAVES.size() == GameData.MAX_WAVE, "波次表还是 15 波")
	_check(GameData.build_spawn_queue(2).has("vanguard"), "第 2 波是裂颚先锋")
	_check(GameData.build_spawn_queue(4).has("boss"), "第 4 波是屠夫")
	_check(GameData.build_spawn_queue(8).has("plague"), "第 8 波是瘟疫母体")
	_check(GameData.build_spawn_queue(15).has("overlord"), "第 15 波是尸王")
	var odd_boss := []
	for wave in range(1, GameData.MAX_WAVE, 2):
		if GameData.boss_wave(wave):
			odd_boss.append(wave)
	_check(odd_boss.is_empty(), "第 15 波之前的奇数波都没有 Boss %s" % [odd_boss])
	var bosses := 0
	for kind: String in GameData.build_spawn_queue(8):
		if GameData.is_boss(kind):
			bosses += 1
	_check(bosses == 1, "第 8 波只有一只 Boss（%d）" % bosses)
	for kind: String in ["stalker", "shielder", "splitter", "summoner", "screamer", "balloon"]:
		_check(seen.has(kind), "波次表里会出现 %s" % kind)
	for kind: String in GameData.BOSSES.keys():
		_check(GameData.BOSSES[kind]["phases"].size() >= 2, "%s 至少两个阶段" % kind)
	var final_phases: int = GameData.BOSSES["overlord"]["phases"].size()
	_check(final_phases > GameData.BOSSES["boss"]["phases"].size() and final_phases > GameData.BOSSES["plague"]["phases"].size(), "最终 Boss 阶段最多（%d）" % final_phases)
	for kind: String in GameData.BOSSES["overlord"]["elites"]:
		_check(int(seen.get(kind, 99)) < 15, "尸王召唤的 %s 在前面的波次出现过" % kind)
	_check(GameData.wave_special(8) == "acid_rain" and GameData.wave_special(12) == "blackout", "第 8、12 波是特殊波")


func _arena_stalker(g: Variant) -> void:
	await _arena_reset(g)
	var p: Variant = g.player
	var z: Node2D = _arena_spawn(g, "stalker", Vector2(110, 0))
	await _sec(0.05)
	_check(z.cloaked() and z.modulate.a < 0.4, "潜伏者远处隐身（透明度 %.2f）" % z.modulate.a)
	await _shot("70_stalker_hidden")
	z.position = p.position + Vector2(40, 0)
	g.god_mode = false
	p.invuln = 0.0
	var hp_before: float = p.hp
	await _sec(0.1)
	_check(not z.cloaked() and z.modulate.a == 1.0, "潜伏者贴近后现身")
	_check(z._warn_t > 0.0 and p.hp == hp_before, "现身时先蓄力闪光，还没咬人")
	await _shot("71_stalker_reveal")
	await _sec(0.75)
	_check(p.hp <= hp_before - float(GameData.ZOMBIES["stalker"]["damage"]) * 0.9, "蓄力后猛扑造成高伤（%.0f）" % (hp_before - p.hp))
	g.god_mode = true
	p.hp = p.max_hp
	var other: Node2D = _arena_spawn(g, "stalker", Vector2(150, 0))
	await _sec(0.05)
	other.take_damage(1.0, Vector2.RIGHT, 0.0)
	_check(not other.cloaked() and other.modulate.a == 1.0, "潜伏者被打中会暴露")


func _arena_shielder(g: Variant) -> void:
	await _arena_reset(g)
	var p: Variant = g.player
	var z: Node2D = _arena_spawn(g, "shielder", Vector2(60, 0))
	await _sec(0.05)
	var brain: Variant = z._brain
	brain.face = Vector2.LEFT
	await _sec(0.05)
	await _shot("72_shielder")
	var shield_before: float = brain.shield_hp
	p.weapon_state["pistol"]["mag"] = 12
	brain.face = Vector2.LEFT
	await _hold_fire(g, "pistol", 0.03)
	await _sec(0.15)
	_check(z.hp == z.max_hp and brain.shield_hp < shield_before, "正面子弹被盾挡下，只磨耐久（%.0f -> %.0f）" % [shield_before, brain.shield_hp])
	# 绕后：盾朝反方向，同一把枪就能打到
	brain.face = Vector2.RIGHT
	p.cooldown = 0.0
	await _hold_fire(g, "pistol", 0.03)
	await _sec(0.15)
	_check(z.hp < z.max_hp, "绕到背后能打穿")
	brain.face = Vector2.RIGHT
	_check(not brain.blocks(z, Vector2.RIGHT) and brain.blocks(z, Vector2.LEFT), "盾只挡正面")
	# 克制手段：爆炸、火焰、电弧、眩晕，都在盾朝向玩家时生效
	await _arena_reset(g)
	var blast: Node2D = _arena_spawn(g, "shielder", Vector2(100, 0))
	await _sec(0.05)
	blast._brain.face = Vector2.LEFT
	var blast_shield: float = blast._brain.shield_hp
	g.explode(blast.center() + Vector2(-20, 0), 10.0, 30.0, true, true)
	_check(blast.hp < blast.max_hp and blast._brain.shield_hp < blast_shield, "爆炸无视盾牌还削盾")
	await _arena_reset(g)
	var fire: Node2D = _arena_spawn(g, "shielder", Vector2(40, 0))
	await _sec(0.05)
	fire._brain.face = Vector2.LEFT
	await _hold_fire(g, "flamer", 0.3)
	_check(fire.hp < fire.max_hp, "火焰无视盾牌")
	await _arena_reset(g)
	var shock: Node2D = _arena_spawn(g, "shielder", Vector2(70, 0))
	await _sec(0.05)
	shock._brain.face = Vector2.LEFT
	await _hold_fire(g, "arc", 0.03)
	_check(shock.hp < shock.max_hp, "电弧无视盾牌")
	await _arena_reset(g)
	var stunned: Node2D = _arena_spawn(g, "shielder", Vector2(70, 0))
	await _sec(0.05)
	stunned._brain.face = Vector2.LEFT
	stunned.stun(1.0)
	_check(not stunned.blocks_shot(Vector2.RIGHT), "被眩晕时盾放下了")
	# 冻住同样打断精英的蓄力
	await _arena_reset(g)
	var chanter: Node2D = _arena_spawn(g, "screamer", Vector2(90, 0))
	await _sec(0.02)
	chanter._brain._cd = 0.0
	await _sec(0.1)
	var warned: bool = chanter._brain._warn >= 0.0
	chanter.apply_chill(5.0)
	_check(warned and chanter._brain._warn < 0.0 and chanter._frozen_t > 0.0, "冻住打断尖叫蓄力")
	await _arena_reset(g)
	var ghoul: Node2D = _arena_spawn(g, "stalker", Vector2(40, 0))
	await _sec(0.1)
	var pose_set: bool = ghoul._pose >= 0
	ghoul.stun(0.5)
	_check(pose_set and ghoul._pose == -1, "眩晕打断潜伏者的蓄力动作")
	# 盾有耐久，打碎后不再挡，不会卡住波次
	await _arena_reset(g)
	var worn: Node2D = _arena_spawn(g, "shielder", Vector2(70, 0))
	await _sec(0.05)
	worn._brain.face = Vector2.LEFT
	worn.shield_hit(99999.0)
	_check(not worn._brain.up and not worn.blocks_shot(Vector2.RIGHT), "盾耐久打完会碎")


func _count_kind(g: Variant, kind: String) -> int:
	var n := 0
	for z: Variant in g.zombies:
		if z.kind == kind:
			n += 1
	return n


func _arena_splitter(g: Variant) -> void:
	await _arena_reset(g)
	var z: Node2D = _arena_spawn(g, "splitter", Vector2(100, 0))
	await _sec(0.05)
	await _shot("73_splitter")
	z.take_damage(z.max_hp + 1.0, Vector2.RIGHT, 0.0)
	var kids: int = _count_kind(g, "splitling")
	_check(kids >= 2 and kids <= 3, "分裂体死后裂成 2~3 只小怪（%d）" % kids)
	await _sec(0.1)
	await _shot("74_splitlings")
	var moved := true
	for k: Variant in g.zombies:
		if k.kind == "splitling" and g.map.blocks(g.map.cell_of(k.position), g.map.BLOCK_ZOMBIE):
			moved = false
	_check(moved, "分裂小怪不会卡进障碍")
	await _arena_reset(g)
	_check(_count_kind(g, "splitling") == 0, "脚本清场不分裂")
	var nuked: Node2D = _arena_spawn(g, "splitter", Vector2(100, 0))
	nuked.no_blast = true
	nuked.take_damage(nuked.max_hp + 1.0, Vector2.RIGHT, 0.0)
	_check(_count_kind(g, "splitling") == 0, "核弹清掉的分裂体不分裂")


func _arena_summoner(g: Variant) -> void:
	await _arena_reset(g)
	var p: Variant = g.player
	var z: Node2D = _arena_spawn(g, "summoner", Vector2(170, 0))
	await _sec(0.05)
	z._brain._cd = 0.0
	await _sec(0.1)
	_check(z._brain._cast_t > 0.0 and z._warn_t > 0.0, "召唤者吟唱时有闪光提示")
	await _shot("75_summoner_cast")
	await _sec(1.2)
	var circles := 0
	for zone: Variant in g.hazards.zones:
		if zone.kind == "spawn":
			circles += 1
	_check(circles == 2, "吟唱结束先亮紫圈（%d）" % circles)
	await _shot("76_summon_circle")
	await _sec(0.8)
	var imps := 0
	var close_to_player := true
	for k: Variant in g.zombies:
		if k.kind == "imp":
			imps += 1
			if k.master != z:
				close_to_player = false
			elif k.position.distance_to(p.position) > 90.0:
				close_to_player = false
	_check(imps == 2, "紫圈里钻出小鬼（%d）" % imps)
	_check(close_to_player, "小鬼出现在玩家身边，不在召唤者身边")
	var kills: int = g.kills
	z.take_damage(z.max_hp + 1.0, Vector2.RIGHT, 0.0)
	_check(_count_kind(g, "imp") == 0, "召唤者死后小鬼一起散")
	_check(g.kills == kills + 1, "散掉的小鬼不算击杀")
	# 贴太近会后退，不站着挨打
	await _arena_reset(g)
	var shy: Node2D = _arena_spawn(g, "summoner", Vector2(50, 0))
	await _sec(0.05)
	shy._brain._cd = 99.0
	var d0: float = shy.position.distance_to(p.position)
	await _sec(0.5)
	_check(shy.position.distance_to(p.position) > d0 + 2.0, "召唤者会和玩家保持距离")


func _arena_screamer(g: Variant) -> void:
	await _arena_reset(g)
	var z: Node2D = _arena_spawn(g, "screamer", Vector2(90, 0))
	var near: Node2D = _arena_spawn(g, "walker", Vector2(120, 16))
	var far: Node2D = _arena_spawn(g, "walker", Vector2(0, 0))
	far.position = Vector2(4, 4) * 16.0
	far.stun(5.0)
	await _sec(0.05)
	z._brain._cd = 0.0
	await _sec(0.1)
	_check(z._warn_t > 0.0, "尖叫前有蓄力闪光")
	await _shot("77_screamer_warn")
	await _sec(1.0)
	_check(z._brain.screams == 1, "尖叫者叫了一声")
	_check(near.rallied() and not far.rallied(), "只有附近的僵尸被鼓动")
	await _shot("78_screamer_rally")
	var from: Vector2 = near.position
	await _sec(0.5)
	var rally_speed: float = near.position.distance_to(from) / 0.5
	_check(rally_speed > near._speed * 1.2, "被鼓动的僵尸明显加速（%.0f > %.0f）" % [rally_speed, near._speed])


func _arena_balloon(g: Variant) -> void:
	await _arena_reset(g)
	var p: Variant = g.player
	var wall_cell := -1
	for piece: Variant in g.map.pieces:
		if piece.kind == "wall" and piece.alive:
			wall_cell = piece.cell
			break
	var z: Node2D = _arena_spawn(g, "balloon", Vector2(100, 0))
	await _sec(0.05)
	await _shot("79_balloon")
	z.position = g.map.cell_center(wall_cell)
	_check(z.flying, "气球僵尸会飞")
	var start: Vector2 = z.position
	await _sec(0.5)
	_check(z.position.distance_to(start) > 5.0, "气球僵尸能从围墙上飘走（%.0f）" % z.position.distance_to(start))
	z.position = p.position + Vector2(10, 0)
	z._brain._drop_cd = 0.0
	await _sec(0.05)
	var bombs := 0
	for zone: Variant in g.hazards.zones:
		if zone.kind == "bomb":
			bombs += 1
	_check(bombs >= 1, "气球僵尸到头顶投弹，先亮红圈")
	await _shot("80_balloon_bomb")
	g.god_mode = false
	p.invuln = 0.0
	var hp_before: float = p.hp
	await _sec(1.0)
	_check(p.hp < hp_before, "毒弹落地炸到玩家")
	g.god_mode = true
	p.hp = p.max_hp
	# 打爆气球：摔下一只半血僵尸，落点不在墙里
	z.position = g.map.cell_center(wall_cell)
	var walkers: int = _count_kind(g, "walker")
	z.take_damage(z.max_hp + 1.0, Vector2.RIGHT, 0.0)
	_check(_count_kind(g, "walker") == walkers + 1, "打爆气球摔下一只僵尸")
	var fallen: Node2D = g.zombies[g.zombies.size() - 1]
	_check(fallen.hp == fallen.max_hp * 0.5, "摔下来的僵尸只剩半血")
	g.hazards.clear()
	z = _arena_spawn(g, "balloon", Vector2(100, 0))
	await _sec(0.02)
	z._brain._drop_cd = 0.0
	z.position = p.position + Vector2(10, 0)
	await _sec(0.05)
	var falling: int = g.hazards.zones.size()
	z.take_damage(z.max_hp + 1.0, Vector2.RIGHT, 0.0)
	_check(falling >= 1 and g.hazards.zones.size() == falling, "气球被打爆后半空的毒弹继续落下")
	_check(not g.map.blocks(g.map.cell_of(fallen.position), g.map.BLOCK_ZOMBIE), "摔下来不会卡在墙里")


## 用真实的伤害入口把血打到阈值，确认换阶段、锁血、无敌窗口。
func _arena_boss_phases(g: Variant) -> void:
	for kind: String in GameData.BOSSES.keys():
		await _arena_reset(g)
		var z: Node2D = _arena_spawn(g, kind, Vector2(110, 0))
		await _sec(0.05)
		var brain: Variant = z._brain
		var phases: Array = GameData.BOSSES[kind]["phases"]
		_check(g.boss_list.has(z) and brain.phase == 0, "%s 进入 Boss 列表，从第一阶段开始" % kind)
		_check(z.boss_info()["count"] == phases.size(), "%s 的血条信息正确" % kind)
		await _shot("81_%s_bar" % kind)
		brain._gap = 999.0
		for i in range(1, phases.size()):
			var moves_before: Array = phases[i - 1]["moves"]
			var limit: float = float(phases[i]["at"]) * z.max_hp
			z.take_damage(z.max_hp * 5.0, Vector2.RIGHT, 0.0, false)
			_check(not z.dead and absf(z.hp - limit) < 1.0, "%s 一刀打不穿阶段，血量锁在 %d%%" % [kind, roundi(float(phases[i]["at"]) * 100.0)])
			_check(brain.phase == i and z.boss_info()["name"] == phases[i]["name"], "%s 切到第 %d 阶段" % [kind, i + 1])
			_check(brain.untouchable() and z._warn_t > 0.0, "%s 换阶段时闪光且无敌" % kind)
			_check(phases[i]["moves"] != moves_before, "%s 第 %d 阶段换了招式" % [kind, i + 1])
			var hp_locked: float = z.hp
			z.take_damage(z.max_hp, Vector2.RIGHT, 0.0, false)
			_check(z.hp == hp_locked, "%s 换阶段的无敌窗口打不动" % kind)
			await _shot("82_%s_phase%d" % [kind, i + 1])
			# 等过场结束，进阶段招式放完，清掉召唤物再打下一段
			await _sec(brain.CHANGE_T + 0.1)
			_check(not brain.untouchable(), "%s 过场结束恢复可打" % kind)
			brain._gap = 999.0
			await _wait_move(brain)
			brain.shield = 0.0
			g.dismiss_minions(z)
		# 最后阶段没有阈值，打穿就死
		z.take_damage(z.max_hp * 5.0, Vector2.RIGHT, 0.0, false)
		_check(z.dead and not g.boss_list.has(z), "%s 最后阶段能被击败" % kind)
		g._boss_hold_t = 0.0
		g._queue = ["walker"] as Array[String]
		g.state = g.State.COMBAT


func _wait_move(brain: Variant) -> void:
	for i in 40:
		if brain._act == "":
			return
		await _sec(0.05)


## 每个阶段的每个招式都实际放一遍，校验各自的效果。
func _arena_boss_moves(g: Variant) -> void:
	var used := {}
	for kind: String in GameData.BOSSES.keys():
		var phases: Array = GameData.BOSSES[kind]["phases"]
		for i in phases.size():
			for move: String in phases[i]["moves"]:
				var tag := "%s/%d/%s" % [kind, i + 1, move]
				await _arena_reset(g)
				var z: Node2D = _arena_spawn(g, kind, Vector2(70, 0))
				await _sec(0.02)
				var brain: Variant = z._brain
				brain.phase = i
				brain._apply_phase(z)
				brain._gap = 999.0
				await _try_move(g, z, brain, move, tag)
				used[move] = true
	var expected := ["charge", "charge2", "slam", "rocks", "storm", "fog", "fogring", "fan", "wave", "call", "elites", "shield", "scream"]
	for move: String in expected:
		_check(used.has(move), "招式 %s 被覆盖" % move)


func _try_move(g: Variant, z: Variant, brain: Variant, move: String, tag: String) -> void:
	brain._begin_move(z, move)
	_check(z._warn_t > 0.0, "%s 起手有蓄力闪光" % tag)
	match move:
		"charge", "charge2":
			_check(g.hazards.lanes.size() == 1, "%s 地上亮冲撞通道" % tag)
			await _shot("83_charge_lane")
			await _sec(brain.CHARGE_WARN + 0.05)
			_check(z._charge_t > 0.0 or z.position.distance_to(g.player.position) < 60.0, "%s 蓄力后才冲出去" % tag)
		"slam":
			_check(g.hazards.zones.size() == 1 and g.hazards.zones[0].kind == "slam", "%s 脚下亮红圈" % tag)
			await _shot("84_slam_circle")
			await _sec(1.0)
			_check(g.hazards.zones.is_empty(), "%s 红圈结算" % tag)
		"rocks", "storm":
			await _sec(0.75)
			var rocks := 0
			for zone: Variant in g.hazards.zones:
				if zone.kind == "rock":
					rocks += 1
			var want: int = 3 if move == "storm" else int(brain.phases[brain.phase].get("rocks", 3))
			_check(rocks >= want, "%s 落点全部亮圈（%d/%d）" % [tag, rocks, want])
			await _shot("85_rock_circles")
		"fog", "fogring":
			await _sec(0.7)
			var fogs := 0
			for zone: Variant in g.hazards.zones:
				if zone.kind == "fog":
					fogs += 1
			_check(fogs >= 2, "%s 毒雾落下前有预警圈（%d）" % [tag, fogs])
			await _sec(1.0)
			_check(g.hazards.clouds.size() >= 2, "%s 毒雾留在地上" % tag)
			await _shot("86_fog")
		"fan":
			await _sec(0.65)
			_check(g.bullets.spits.size() == 5, "%s 扇形喷出 5 发毒液" % tag)
		"wave":
			_check(not g.hazards.zones.is_empty(), "%s 起手有预警圈" % tag)
			await _sec(0.95)
			_check(g.hazards.shocks.size() == 1, "%s 放出冲击波" % tag)
			await _shot("87_shockwave")
		"call":
			var before: int = g.zombies.size()
			await _sec(0.85)
			_check(not g.hazards.zones.is_empty(), "%s 召唤前亮紫圈" % tag)
			await _sec(0.9)
			_check(g.zombies.size() > before, "%s 叫来了小怪" % tag)
			await _shot("88_call")
		"elites":
			await _sec(2.0)
			var pool: Array = GameData.BOSSES[z.kind].get("elites", [])
			var ok := true
			var n := 0
			for other: Variant in g.zombies:
				if other.master == z:
					n += 1
					ok = ok and pool.has(other.kind)
			_check(n == 3 and ok, "%s 召来前面出现过的精英（%d）" % [tag, n])
			var guard: Variant = brain.phases[brain.phase].get("guard", null)
			if guard != null:
				await _sec(0.05)
				_check(brain.guarded(), "%s 精英活着时本体减伤" % tag)
				var before: float = z.hp
				z.take_damage(20.0, Vector2.RIGHT, 0.0, false)
				_check(before - z.hp < 20.0 * float(guard) + 1.0 and before > z.hp, "%s 减伤数值生效" % tag)
				g.dismiss_minions(z)
				await _sec(0.05)
				_check(not brain.guarded(), "%s 精英清完减伤消失" % tag)
			await _shot("89_elites")
		"shield":
			await _sec(0.75)
			_check(brain.shield > 0.0, "%s 张开护盾" % tag)
			var before: float = z.hp
			z.take_damage(10.0, Vector2.RIGHT, 0.0, false)
			_check(z.hp == before and brain.shield < brain.shield_max, "%s 护盾先吃伤害" % tag)
			await _shot("90_shield")
			z.take_damage(brain.shield + 5.0, Vector2.RIGHT, 0.0, false)
			_check(brain.shield <= 0.0 and z.hp < before, "%s 护盾打破后伤害溢出到本体" % tag)
		"scream":
			var minion: Node2D = _arena_spawn(g, "walker", Vector2(100, 20))
			await _sec(0.95)
			_check(minion.rallied(), "%s 全场尖叫鼓动僵尸" % tag)


## 危险提示的意义：蓄力期间不掉血、站在圈外不掉血、站在圈内才掉血，晕眩能打断。
func _arena_boss_warnings(g: Variant) -> void:
	await _arena_reset(g)
	var p: Variant = g.player
	var z: Node2D = _arena_spawn(g, "boss", Vector2(30, 0))
	await _sec(0.02)
	var brain: Variant = z._brain
	brain._gap = 999.0
	z._attack_t = 99.0
	g.god_mode = false
	p.invuln = 0.0
	var hp0: float = p.hp
	brain._begin_move(z, "slam")
	await _sec(0.5)
	_check(p.hp == hp0, "重砸蓄力期间不掉血")
	await _sec(0.5)
	_check(p.hp < hp0, "站在红圈里挨砸（%.0f）" % (hp0 - p.hp))
	p.hp = p.max_hp
	# 站在圈外毫发无损
	await _sec(0.6)
	p.invuln = 0.0
	hp0 = p.hp
	g.hazards.slam(p.position + Vector2(90, 0), 40.0, 30.0, 0.2, z)
	g.hazards.rock(p.position + Vector2(90, 30), 30.0, 0.2)
	await _sec(0.35)
	_check(p.hp == hp0, "站在红圈外不受伤")
	# 落石
	g.hazards.rock(p.position, 12.0, 0.2)
	await _sec(0.3)
	_check(p.hp < hp0, "站在落石圈里被砸")
	p.hp = p.max_hp
	# 毒雾和血清
	g.hazards.clear()
	await _sec(0.6)
	hp0 = p.hp
	g.hazards.fog(p.position, 30.0, 3.0, null)
	await _sec(0.5)
	_check(p.hp == hp0, "毒雾预警期间不掉血")
	await _sec(1.0)
	var fog_loss: float = hp0 - p.hp
	_check(fog_loss > 0.5, "毒雾持续掉血（%.1f）" % fog_loss)
	g.hazards.clear()
	p.hp = p.max_hp
	# 冲击波：冲刺的无敌帧能穿过去
	p.invuln = 0.0
	hp0 = p.hp
	g.hazards.shockwave(p.position + Vector2(40, 0), 120.0, 300.0, 15.0)
	await _sec(0.25)
	_check(p.hp < hp0, "冲击波扫到会掉血")
	p.hp = p.max_hp
	p.invuln = 0.0
	hp0 = p.hp
	p.dash_t = 0.3
	g.hazards.shockwave(p.position + Vector2(10, 0), 40.0, 300.0, 15.0)
	await _sec(0.1)
	_check(p.hp == hp0, "冲刺能穿过冲击波")
	p.dash_t = 0.0
	g.god_mode = true
	p.hp = p.max_hp
	g.hazards.clear()
	# 晕眩打断蓄力，Boss 的冲锋也停
	brain._begin_move(z, "charge")
	_check(brain._act == "charge", "开始蓄力冲撞")
	z.stun(0.2)
	_check(brain._act == "", "晕眩打断蓄力")
	await _sec(0.3)
	# 施法者死了，没落地的招式作废
	brain._gap = 999.0
	brain._begin_move(z, "slam")
	z.take_damage(99999.0, Vector2.RIGHT, 0.0, false)
	_check(g.hazards.zones.is_empty(), "Boss 死后没落地的招式作废")


## 屠夫狂怒的连冲：蓄力时贴脸霰弹或闪光弹能打断并硬直；第一阶段的冲撞和别的 Boss 不吃霰弹打断。
func _arena_boss_break(g: Variant) -> void:
	var p: Variant = g.player
	var z: Node2D = await _break_setup(g, "boss", 1)
	var brain: Variant = z._brain
	brain._begin_move(z, "charge2")
	_check(brain._breakable and g.hazards.lanes.size() == 1, "屠夫狂怒的连冲蓄力可以打断")
	await _buckshot(g, z)
	_check(brain._act == "" and z._charge_t <= 0.0, "贴脸一枪霰弹打断连冲蓄力（累计击退 %.0f）" % brain._brace)
	_check(z._stun_t > 0.5, "霰弹打断后硬直（还剩 %.2f 秒）" % z._stun_t)
	_check(g.hazards.lanes.is_empty(), "打断后冲撞通道撤掉")
	await _shot("93_butcher_break")
	brain._begin_move(z, "charge", true)
	_check(brain._breakable, "连冲的第二段蓄力也能打断")
	# 闪光弹：Boss 本来只晕一下，打断连冲时补足硬直
	z = await _break_setup(g, "boss", 1)
	brain = z._brain
	brain._begin_move(z, "charge2")
	g.ordnance._flash_burst(z.center(), float(GameData.ITEMS["flash"]["radius"]), float(GameData.ITEMS["flash"]["power"]))
	_check(brain._act == "" and brain._chain == 0 and g.hazards.lanes.is_empty(), "闪光弹打断连冲蓄力并撤掉通道")
	_check(z._stun_t >= brain.BREAK_STUN - 0.01, "闪光打断后硬直约 %.1f 秒（%.2f）" % [brain.BREAK_STUN, z._stun_t])
	# 第一阶段的冲撞照旧只能闪光打断
	z = await _break_setup(g, "boss", 0)
	brain = z._brain
	brain._begin_move(z, "charge")
	_check(not brain._breakable, "屠夫第一阶段的冲撞不吃霰弹打断")
	await _buckshot(g, z)
	_check(brain._act == "charge" and z._stun_t <= 0.0, "霰弹打不断第一阶段的冲撞")
	z = await _break_setup(g, "vanguard", 1)
	z._brain._begin_move(z, "charge2")
	_check(not z._brain._breakable, "裂颚先锋的连冲不吃霰弹打断")
	p.switch_weapon("pistol")
	await _arena_reset(g)


func _break_setup(g: Variant, kind: String, phase: int) -> Node2D:
	await _arena_reset(g)
	var z: Node2D = _arena_spawn(g, kind, Vector2(40, 0))
	await _sec(0.02)
	var brain: Variant = z._brain
	brain.phase = phase
	brain._apply_phase(z)
	brain._gap = 999.0
	z._attack_t = 99.0
	return z


## 用真实的开火路径对着 Boss 开一枪霰弹。
func _buckshot(g: Variant, z: Variant) -> void:
	var p: Variant = g.player
	p.switch_weapon("shotgun")
	p.cooldown = 0.0
	p.weapon_state["shotgun"]["mag"] = p.mag_size()
	_test_bot.aim_dir = (z.center() - (p.position + Vector2(0, -7))).normalized()
	_test_bot.firing = true
	await _sec(0.05)
	_test_bot.firing = false
	await _sec(0.15)


func _arena_boss_loot(g: Variant) -> void:
	await _arena_reset(g)
	var p: Variant = g.player
	g.pickups.enabled = true
	g.pickups.items.clear()
	# 屠夫：金币、必掉道具、专属战利品
	var z: Node2D = _arena_spawn(g, "boss", Vector2(150, 0))
	await _sec(0.02)
	z._brain.phase = z._brain.phases.size() - 1
	var minion: Node2D = _arena_spawn(g, "imp", Vector2(170, 10))
	minion.master = z
	z.take_damage(z.max_hp * 5.0, Vector2.RIGHT, 0.0)
	var spec: Dictionary = GameData.BOSSES["boss"]
	var counts := {}
	var coin_total := 0
	for it: Variant in g.pickups.items:
		counts[it.kind] = int(counts.get(it.kind, 0)) + 1
		if it.kind == "coin":
			coin_total += it.value
	_check(coin_total == int(GameData.ZOMBIES["boss"]["coins"]), "Boss 掉金币雨（%d）" % coin_total)
	_check(int(counts.get("item", 0)) == spec["drops"].size(), "Boss 必掉 %d 件道具" % spec["drops"].size())
	_check(int(counts.get("trophy", 0)) == 1 and int(counts.get("med", 0)) == 1, "Boss 掉专属战利品和急救包")
	_check(_gone(minion), "Boss 死后召唤物一起散")
	_check(g._boss_hold_t > 0.0 and g.state == g.State.COMBAT, "击败后留出捡战利品的时间")
	await _shot("91_boss_loot")
	g.pickups.items.clear()
	# 裂颚先锋是小 Boss：只掉道具和急救包，没有专属战利品
	var mini_boss: Node2D = _arena_spawn(g, "vanguard", Vector2(150, 0))
	await _sec(0.02)
	mini_boss._brain.phase = mini_boss._brain.phases.size() - 1
	mini_boss.take_damage(mini_boss.max_hp * 5.0, Vector2.RIGHT, 0.0)
	counts = {}
	for it: Variant in g.pickups.items:
		counts[it.kind] = int(counts.get(it.kind, 0)) + 1
	_check(mini_boss.dead and int(counts.get("item", 0)) == GameData.BOSSES["vanguard"]["drops"].size(), "裂颚先锋掉 %d 件道具" % GameData.BOSSES["vanguard"]["drops"].size())
	_check(int(counts.get("trophy", 0)) == 0 and int(counts.get("med", 0)) == 1, "裂颚先锋没有专属战利品，掉急救包")
	g.pickups.items.clear()
	g._boss_hold_t = 0.0
	# 战利品效果
	var max_before: float = p.max_hp
	p.hp = 10.0
	g.pickups.drop(p.position, "trophy", 1, "heart")
	await _sec(1.2)
	_check(p.max_hp == max_before + GameData.TROPHY_HP and p.hp == p.max_hp, "屠夫之心加生命上限并回满")
	g.pickups.drop(p.position, "trophy", 1, "serum")
	await _sec(1.2)
	_check(p.dot_mult == GameData.TROPHY_DOT, "母体血清减半持续伤害")
	var score_before: int = g.score
	g.pickups.drop(p.position, "trophy", 1, "crown")
	await _sec(1.2)
	_check(g.score == score_before + GameData.TROPHY_SCORE, "尸王之冠加分")
	p.dot_mult = 1.0
	# 通关瞬间地上的战利品也要算数
	score_before = g.score
	g.pickups.drop(p.position + Vector2(400, 0), "trophy", 1, "crown")
	g.pickups.collect_all()
	_check(g.score == score_before + GameData.TROPHY_SCORE and g.pickups.items.is_empty(), "通关时地上的战利品自动结算")
	g.pickups.enabled = false
	# 尸王倒下：场上和队列里的僵尸全部散掉
	await _arena_reset(g)
	g._queue = ["walker", "walker"] as Array[String]
	var king: Node2D = _arena_spawn(g, "overlord", Vector2(150, 0))
	var a: Node2D = _arena_spawn(g, "walker", Vector2(80, 0))
	var b: Node2D = _arena_spawn(g, "tank", Vector2(100, 20))
	await _sec(0.02)
	king._brain.phase = king._brain.phases.size() - 1
	king.take_damage(king.max_hp * 5.0, Vector2.RIGHT, 0.0)
	_check(king.dead and _gone(a) and _gone(b), "尸王倒下全场僵尸一起死")
	_check(g._queue.is_empty(), "尸王倒下清空剩余出怪")
	g._queue = ["walker"] as Array[String]
	g._boss_hold_t = 0.0


func _arena_specials(g: Variant) -> void:
	await _arena_reset(g)
	var wave_before: int = g.wave
	g.wave = 8
	g._acid_t = 0.0
	await _sec(0.05)
	var drops := 0
	for zone: Variant in g.hazards.zones:
		if zone.kind == "acid":
			drops += 1
	_check(drops == GameData.ACID_RAIN_COUNT, "第 8 波下酸雨，落点先亮圈（%d）" % drops)
	await _shot("92_acid_rain")
	g.god_mode = false
	g.player.invuln = 0.0
	g.hazards.clear()
	var hp0: float = g.player.hp
	g.hazards.acid(g.player.position, 10.0)
	await _sec(1.2)
	_check(g.player.hp < hp0, "酸雨落地伤害玩家")
	g.god_mode = true
	g.player.hp = g.player.max_hp
	# 第 8 波的瘟疫母体在场时酸雨变稀
	g.hazards.clear()
	var mother: Node2D = _arena_spawn(g, "plague", Vector2(150, 0))
	await _sec(0.02)
	mother._brain._gap = 999.0
	g._acid_t = 0.0
	await _sec(0.05)
	drops = 0
	for zone: Variant in g.hazards.zones:
		if zone.kind == "acid":
			drops += 1
	_check(drops == GameData.ACID_RAIN_COUNT - 1, "Boss 在场时酸雨每轮少一滴（%d）" % drops)
	_check(g._acid_t > GameData.ACID_RAIN_GAP * (GameData.ACID_RAIN_BOSS_GAP - 0.1), "Boss 在场时酸雨间隔拉长（%.1f 秒）" % g._acid_t)
	mother.no_blast = true
	mother.take_damage(99999.0, Vector2.RIGHT, 0.0, false)
	g._boss_hold_t = 0.0
	g.hazards.clear()
	g.wave = 12
	var dark: Color = g._combat_tint()
	g.wave = 11
	var normal: Color = g._combat_tint()
	_check(dark.r < normal.r and dark.b <= normal.b, "第 12 波断电比普通夜晚更暗")
	g.wave = wave_before
	g._acid_t = 99999.0
	g.hazards.clear()
	g.bullets.clear_hazards()


func _flow_explosion_test(g: Variant) -> void:
	var count_before: int = g.fx.blasts.size()
	g.explode(g.player.position + Vector2(200, 0), 30.0, 40.0, false)
	_check(g.fx.blasts.size() == count_before + 1, "爆炸特效生成")


# ---------------------------------------------------------------------------
# 地图和随机事件：三张图逐一校验布局，再在每张图上跑一遍全部事件
# ---------------------------------------------------------------------------

func _run_map_test(title: Node) -> void:
	await _map_title_checks(title)
	var obstacles := {}
	for id: String in GameData.MAP_ORDER:
		await _map_load(id)
		var g: Variant = _game
		print("[flow] ---- 地图 %s ----" % id)
		_map_arena(g)
		obstacles[id] = _map_layout_checks(g, id)
		await _map_walk_checks(g)
		_map_turret_checks(g)
		_event_rule_checks(g)
		await _event_night(g)
		await _event_storm(g)
		await _event_fog(g)
		await _event_airdrop(g)
		await _event_vanguard(g)
		await _event_emp(g)
		_check(g.state != g.State.OVER, "地图 %s 跑完事件后游戏没有结束" % id)
	_check(int(obstacles["parking"]) < int(obstacles["ruins"]), "停车场障碍比废墟少（%d < %d）" % [obstacles["parking"], obstacles["ruins"]])
	_check(int(obstacles["ruins"]) < int(obstacles["alley"]), "窄巷障碍比废墟多（%d > %d）" % [obstacles["alley"], obstacles["ruins"]])
	_finish_flow()


func _map_title_checks(title: Node) -> void:
	title.click_gate.visible = false
	var panel: Control = title.map_panel
	title._on_start()
	_check(panel.visible, "开始游戏先打开选图")
	_check(panel.cards.size() >= 3, "至少三张地图可选（%d）" % panel.cards.size())
	await _sec(0.1)
	await _shot("70_map_select")
	_send_key(KEY_ESCAPE, true)
	_send_key(KEY_ESCAPE, false)
	await _sec(0.1)
	_check(not panel.visible, "Esc 关闭选图")
	title._on_start()
	panel.back_button.pressed.emit()
	_check(not panel.visible, "返回按钮关闭选图")
	var names := {}
	for id: String in GameData.MAP_ORDER:
		names[GameData.MAPS[id]["name"]] = true
		var tex: Texture2D = panel.cards[id].icon
		_check(tex != null and tex.get_size() == Vector2(128, 88), "地图 %s 有缩略图" % id)
	_check(names.size() == GameData.MAP_ORDER.size(), "地图不重名")
	title._on_start()
	_check(panel.cards["ruins"].has_focus(), "选图默认聚焦上次的地图")
	_send_key(KEY_RIGHT, true)
	_send_key(KEY_RIGHT, false)
	await _sec(0.1)
	_check(panel.cards["parking"].has_focus(), "方向键能切换地图")
	var escaped := false
	for id: String in GameData.MAP_ORDER:
		for side: Side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			var next: Control = panel.cards[id].find_valid_focus_neighbor(side)
			escaped = escaped or next == null or not panel.is_ancestor_of(next)
	_check(not escaped, "方向键不会跳到面板后面的按钮")
	_game = null
	_send_key(KEY_ENTER, true)
	_send_key(KEY_ENTER, false)
	while _game == null:
		await get_tree().process_frame
	_check(_game.map.map_id == "parking", "回车进入选中的地图")
	_check(Save.map_id == "parking", "选择写入设置")
	Save.load_all()
	_check(Save.map_id == "parking", "选择能从存档读回")
	var cfg := ConfigFile.new()
	cfg.load(Save.path)
	cfg.set_value("settings", "map", "no_such_map")
	cfg.save(Save.path)
	Save.load_all()
	_check(Save.map_id == "ruins", "存档里的地图不存在时回到默认")
	await _map_load("alley")
	_game.pause_ui._restart()
	_game = null
	while _game == null:
		await get_tree().process_frame
	_check(_game.map.map_id == "alley", "暂停菜单重开沿用当前地图")


func _map_load(id: String) -> void:
	_game = null
	Save.map_id = id
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	while _game == null:
		await get_tree().process_frame
	await _sec(0.1)


func _map_arena(g: Variant) -> void:
	_test_bot = BotScript.new(g)
	g.player.bot = _test_bot
	g.god_mode = true
	g.state = g.State.COMBAT
	g._queue = ["walker"] as Array[String]
	g._spawn_t = 99999.0
	g.base_damage_scale = 0.0


## 校验布局，返回不可破坏障碍的格数。
func _map_layout_checks(g: Variant, id: String) -> int:
	var m: Variant = g.map
	var spec: Dictionary = GameData.MAPS[id]
	_check(m.map_id == id, "加载的是所选地图")
	_check(g.coins == int(spec["coins"]), "开局金币按地图设置（%d）" % g.coins)
	var rows: Array = m.Layouts.grid(id)
	if not rows.is_empty():
		var sized: bool = rows.size() == m.H
		for row: String in rows:
			sized = sized and row.length() == m.W
		_check(sized, "布局是 %dx%d" % [m.W, m.H])
	_check(m.base_cells.size() == 12 and m.base_x1 - m.base_x0 == 3 and m.base_y1 - m.base_y0 == 2, "基地占 4x3 格")
	_check(g.base.position.x == (m.base_x0 + 2) * m.TILE, "基地摆在布局指定的位置")
	_check(not m._box_hits(m.player_start.x, m.player_start.y, g.player.BOX_R, m.BLOCK_PLAYER), "玩家出生点没有卡在障碍里")
	_check(g.player.position.distance_to(m.player_start) < 40.0, "玩家从布局指定的位置出生")
	var reach: PackedInt32Array = m.reach_field(m.cell_of(m.player_start), m.BLOCK_PLAYER)
	var solid := 0
	var pockets := 0
	var unreachable := 0
	for i in m.W * m.H:
		if m.flags[i] == 0 and reach[i] < 0:
			pockets += 1
		if m.flags[i] & m.BLOCK_ZOMBIE != 0 and not m.structures.has(i):
			solid += 1
	_check(pockets == 0, "所有空地玩家都走得到（封闭 %d 格）" % pockets)
	for side: String in ["top", "bottom", "left", "right"]:
		var cells: Array = m.spawn_cells[side]
		_check(cells.size() > 0, "%s 边有出怪点（%d）" % [side, cells.size()])
		for cell: int in cells:
			if reach[cell] < 0:
				unreachable += 1
			var at: int = cell
			var steps := 0
			while at >= 0 and not m.is_base_cell(at) and steps < m.W * m.H:
				at = m.next_cell[at]
				steps += 1
			if at < 0 or not m.is_base_cell(at):
				unreachable += 1
	_check(unreachable == 0, "每个出怪点都有路到基地，玩家也走得到（不通 %d）" % unreachable)
	if id == "alley":
		_check(_alley_two_wide(m, rows), "窄巷最窄也有 2 格，能走能绕")
		_check(m.minimap_tex != null, "窄巷的小地图画出楼房")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bad := 0
	for k in 40:
		var spot: Vector2 = m.edge_spot(rng, m.player_start)
		var c: int = m.cell_of(spot)
		var margin: int = mini(mini(c % m.W, m.W - 1 - c % m.W), mini(c / m.W, m.H - 1 - c / m.W))
		if reach[c] < 0 or m.flags[c] != 0 or margin > m.EDGE_BAND:
			bad += 1
	_check(bad == 0, "补给箱落点都在地图边缘且走得到")
	return solid


func _alley_two_wide(m: Variant, rows: Array) -> bool:
	var open := func(x: int, y: int) -> bool:
		return m.in_bounds(x, y) and String(rows[y])[x] != "#"
	for y in m.H:
		for x in m.W:
			if not open.call(x, y):
				continue
			var ok := false
			for ox in [-1, 0]:
				for oy in [-1, 0]:
					if open.call(x + ox, y + oy) and open.call(x + ox + 1, y + oy) and open.call(x + ox, y + oy + 1) and open.call(x + ox + 1, y + oy + 1):
						ok = true
			if not ok:
				print("[flow] 过窄的格子 ", x, ",", y)
				return false
	return true


## 四个方向各放一只快跑僵尸，确认真的能走到基地附近。
func _map_walk_checks(g: Variant) -> void:
	var m: Variant = g.map
	var racers := []
	for side: String in ["top", "bottom", "left", "right"]:
		g._spawn_side = side
		g._spawn_zombie("runner")
		var z: Variant = g.zombies[g.zombies.size() - 1]
		racers.append({"z": z, "from": m.dist[m.cell_of(z.position)], "side": side})
	await _sec(24.0)
	for r: Dictionary in racers:
		var z: Variant = r["z"]
		var near: bool = not is_instance_valid(z) or z.dead or z.position.distance_to(g.base.position) < 170.0
		_check(near, "%s 边的僵尸走到了基地附近（流场 %d -> %d）" % [r["side"], r["from"], m.dist[m.cell_of(z.position)] if is_instance_valid(z) else 0])
	await _shot("71_walk_%s" % m.map_id)
	_map_reset(g)


func _map_turret_checks(g: Variant) -> void:
	g.coins = 99999
	for i in 8:
		_test_bot._place_turret()
	_check(g.turrets.size() >= 6, "炮塔点位都能放（%d）" % g.turrets.size())
	for t: Variant in g.turrets.duplicate():
		t.take_damage(99999.0)
	_check(g.turrets.is_empty(), "炮塔能清掉")
	g.map.rebuild_flow()
	g.coins = 0


func _map_reset(g: Variant) -> void:
	for z: Variant in g.zombies.duplicate():
		z.no_blast = true
		z.dismissed = true
		z.take_damage(99999.0, Vector2.RIGHT, 0.0, false)
	g.ordnance.clear_field()
	g.bullets.clear_hazards()
	g.hazards.clear()
	g.pickups.items.clear()
	g.player.position = g.map.player_start
	g.player.velocity = Vector2.ZERO
	g.player.hp = g.player.max_hp
	_test_bot.move = Vector2.ZERO
	_test_bot.firing = false
	_test_bot._nav_goal = -1
	_test_bot._nav_t = 0.0


func _ev_begin(g: Variant, id: String, wave: int) -> void:
	var ev: Variant = g.events
	ev.enabled = true
	ev.forced = id
	ev._plan_wave = 0
	g._begin_countdown(wave)
	await _sec(0.05)
	if GameData.EVENTS[id]["slot"] == "weather":
		_check((g.hud.event_warn_titles() as Array).has(String(GameData.EVENTS[id]["name"])), "%s 有预警提示" % GameData.EVENTS[id]["name"])
	g.state = g.State.COMBAT
	g._queue = ["walker"] as Array[String]
	g._spawn_t = 99999.0


func _ev_end(g: Variant) -> void:
	var ev: Variant = g.events
	ev.on_wave_cleared()
	ev.forced = ""
	ev.enabled = false
	ev.crates.clear()
	_check(is_equal_approx(ev.zombie_speed, 1.0) and is_equal_approx(ev.player_speed, 1.0) and is_equal_approx(ev.splash_mult, 1.0) and is_equal_approx(ev.arc_mult, 1.0) and is_equal_approx(ev.coin_mult, 1.0) and is_equal_approx(ev.aggro_mult, 1.0) and is_equal_approx(ev.turret_range, 1.0), "事件结束后倍率全部复原")
	_check(not ev.jammed() and ev.weather == "", "事件结束后状态清空")
	g.state = g.State.COMBAT
	g.wave = 2
	_map_reset(g)
	await _sec(0.05)


## 事件排期规则：和特殊波、Boss 波不冲突，不重名，保底不会连着两波没事件。
func _event_rule_checks(g: Variant) -> void:
	var ev: Variant = g.events
	var wave_names := {}
	for cfg: Dictionary in GameData.WAVES:
		wave_names[cfg["name"]] = true
	for id: String in GameData.EVENT_ORDER:
		_check(not wave_names.has(GameData.EVENTS[id]["name"]), "事件「%s」不和波次重名" % GameData.EVENTS[id]["name"])
	ev.enabled = true
	ev.forced = ""
	var seen := {}
	var bad := []
	var longest_quiet := 0
	for run in 200:
		ev._quiet_waves = 0
		ev._last_weather = ""
		ev._last_incident = ""
		var quiet := 0
		for wave in range(1, GameData.MAX_WAVE + 1):
			ev.plan_wave(wave)
			var weather: String = ev.planned_weather()
			var incident: String = ev.planned_incident()
			seen[weather] = true
			seen[incident] = true
			if wave == 1 and (weather != "" or incident != ""):
				bad.append("第 1 波有事件")
			if weather != "" and (GameData.wave_special(wave) != "" or GameData.boss_wave(wave)):
				bad.append("第 %d 波叠了天气 %s" % [wave, weather])
			if weather == "night" and wave == 11:
				bad.append("黑夜降临叠了夜战")
			if incident == "emp" and (wave == 12 or GameData.boss_wave(wave)):
				bad.append("第 %d 波电磁干扰" % wave)
			if GameData.boss_wave(wave) and incident != "" and incident != "airdrop":
				bad.append("Boss 波有 %s" % incident)
			quiet = quiet + 1 if weather == "" and incident == "" and wave > 1 else 0
			longest_quiet = maxi(longest_quiet, quiet)
	_check(bad.is_empty(), "事件和特殊波、Boss 波不冲突 %s" % str(bad.slice(0, 3)))
	_check(longest_quiet <= 1, "不会连着两波没有事件（最长 %d）" % longest_quiet)
	for id: String in GameData.EVENT_ORDER:
		_check(seen.has(id), "事件 %s 会被抽到" % id)
	ev.enabled = false
	ev._plan_wave = 0


## 实测一只普通僵尸沿流场走 1 秒的路程。
func _zombie_pace(g: Variant) -> float:
	var m: Variant = g.map
	var cells: Array = m.spawn_cells["left"]
	var start: int = cells[cells.size() / 2]
	g._spawn_zombie("walker")
	var z: Variant = g.zombies[g.zombies.size() - 1]
	z.position = m.cell_center(start)
	z._speed = 30.0
	z._phase = 0
	await _sec(0.1)
	var total := 0.0
	var last: Vector2 = z.position
	for i in 10:
		await _sec(0.1)
		total += last.distance_to(z.position)
		last = z.position
	z.no_blast = true
	z.dismissed = true
	z.take_damage(99999.0, Vector2.RIGHT, 0.0, false)
	return total


func _event_night(g: Variant) -> void:
	var calm: float = await _zombie_pace(g)
	await _ev_begin(g, "night", 3)
	var ev: Variant = g.events
	_check(ev.weather == "night", "夜战开始")
	await _sec(1.4)
	_check(ev.veil_alpha() > 0.6, "夜战画面变暗（%.2f）" % ev.veil_alpha())
	_check((ev.chips() as Array).size() == 1, "HUD 标签显示夜战")
	var pace: float = await _zombie_pace(g)
	_check(pace > calm * 1.05, "夜战僵尸真的变快（%.1f -> %.1f）" % [calm, pace])
	_test_bot.aim_point = g.player.position + Vector2(100, 0)
	await _shot("72_night_%s" % g.map.map_id)
	# 金币加成：杀一只普通僵尸，地上的金币按倍率结算
	g.pickups.items.clear()
	g._spawn_zombie("walker")
	var z: Variant = g.zombies[g.zombies.size() - 1]
	z.position = g.player.position + Vector2(0, -200)
	z.take_damage(99999.0, Vector2.RIGHT, 0.0, false)
	var coins := 0
	for it: Variant in g.pickups.items:
		if it.kind == "coin":
			coins += it.value
	var expect: int = ceili(float(GameData.ZOMBIES["walker"]["coins"]) * 1.25)
	_check(coins == expect, "夜战金币 +25%%（%d == %d）" % [coins, expect])
	await _ev_end(g)
	_check(g._combat_tint() != Color.BLACK, "夜战结束后色调正常")


func _arc_hit(g: Variant) -> float:
	g._spawn_zombie("tank")
	var z: Variant = g.zombies[g.zombies.size() - 1]
	z.position = g.player.position + Vector2(40, z.center_h)
	z._stun_t = 9.0
	await _sec(0.05)
	var hp0: float = z.hp
	g.ordnance.arc(g.player.position, Vector2.RIGHT, 100.0, 10.0, 0, 40.0, 0.0)
	await _sec(0.05)
	var lost: float = hp0 - z.hp
	z.no_blast = true
	z.dismissed = true
	z.take_damage(99999.0, Vector2.RIGHT, 0.0, false)
	return lost


## 放一只僵尸在爆炸半径边上，返回它有没有被炸到。
func _splash_reaches(g: Variant) -> bool:
	var at: Vector2 = g.player.position
	g._spawn_zombie("tank")
	var z: Variant = g.zombies[g.zombies.size() - 1]
	z.position = at + Vector2(0, -56 + z.center_h)
	z._stun_t = 9.0
	await _sec(0.05)
	var hp0: float = z.hp
	g.explode(at, 30.0, 50.0, true, true)
	var hit: bool = z.hp < hp0
	z.no_blast = true
	z.dismissed = true
	z.take_damage(99999.0, Vector2.RIGHT, 0.0, false)
	await _sec(0.05)
	return hit


func _event_storm(g: Variant) -> void:
	var calm: float = await _zombie_pace(g)
	var calm_arc: float = await _arc_hit(g)
	_check(await _splash_reaches(g), "晴天爆炸能炸到边上的僵尸")
	await _ev_begin(g, "storm", 2)
	var ev: Variant = g.events
	var m: Variant = g.map
	_check(g.player.move_speed() < g.player.SPEED, "暴雨玩家略慢（%.1f）" % g.player.move_speed())
	var pace: float = await _zombie_pace(g)
	_check(pace < calm * 0.95, "暴雨僵尸更慢（%.1f -> %.1f）" % [calm, pace])
	_check(not await _splash_reaches(g), "暴雨爆炸范围变小")
	var arc_hit: float = await _arc_hit(g)
	_check(arc_hit > calm_arc * 1.2, "暴雨电弧枪更强（%.1f -> %.1f）" % [calm_arc, arc_hit])
	var far: Vector2 = g.player.position + Vector2(0, 200)
	g.bullets.add_pool(far, 4.0, 5.0)
	await _sec(1.0)
	_check(g.bullets.pools[g.bullets.pools.size() - 1].t < 3.6, "暴雨冲淡酸液池")
	g.bullets.clear_hazards()
	# 水洼：只铺在空地上，踩上去打滑
	var wet_cell := -1
	var dry_cell := -1
	var wet_on_solid := 0
	for i in m.W * m.H:
		if ev._wet[i] == 1:
			if m.flags[i] != 0:
				wet_on_solid += 1
			wet_cell = i
		elif m.flags[i] == 0 and dry_cell < 0 and m.reach_field(m.cell_of(m.player_start), m.BLOCK_PLAYER)[i] >= 0:
			dry_cell = i
	_check(wet_cell >= 0, "暴雨铺了水洼")
	_check(wet_on_solid == 0, "水洼不在障碍上")
	_check(ev.zombie_speed_at(m.cell_center(wet_cell)) < ev.zombie_speed, "僵尸踩水更慢")
	await _shot("73_storm_%s" % g.map.map_id)
	var slide := func(cell: int) -> float:
		g.player.position = m.cell_center(cell)
		g.player.velocity = Vector2(90, 0)
		return 0.0
	slide.call(wet_cell)
	await _sec(0.1)
	var wet_v: float = g.player.velocity.length()
	slide.call(dry_cell)
	await _sec(0.1)
	var dry_v: float = g.player.velocity.length()
	_check(wet_v > dry_v * 1.5, "水洼里刹不住（%.1f > %.1f）" % [wet_v, dry_v])
	await _ev_end(g)
	_check(not ev.is_wet(m.cell_center(wet_cell)), "雨停后水洼消失")


func _event_fog(g: Variant) -> void:
	var noticed: bool = await _notices_player(g)
	_check(noticed, "晴天僵尸能发现玩家")
	g.turret_level = 1
	await _ev_begin(g, "fog", 3)
	var ev: Variant = g.events
	await _sec(1.4)
	_check(ev.veil_alpha() > 0.6, "大雾遮挡视野（%.2f）" % ev.veil_alpha())
	_check(ev.turret_range < 1.0, "大雾炮塔射程变短")
	noticed = await _notices_player(g)
	_check(not noticed, "大雾里僵尸更难发现玩家")
	await _shot("74_fog_%s" % g.map.map_id)
	await _ev_end(g)


func _notices_player(g: Variant) -> bool:
	g._spawn_zombie("walker")
	var z: Variant = g.zombies[g.zombies.size() - 1]
	z.position = g.player.position + Vector2(32, 0)
	z._aggro = 40.0
	z._recenter_t = 0.0
	z._stun_t = 9.0
	await _sec(0.05)
	z._think()
	var chasing: bool = z._chasing
	z.no_blast = true
	z.dismissed = true
	z.take_damage(99999.0, Vector2.RIGHT, 0.0, false)
	return chasing


func _event_airdrop(g: Variant) -> void:
	await _ev_begin(g, "airdrop", 3)
	var ev: Variant = g.events
	var m: Variant = g.map
	ev._incident_t = 0.001
	await _sec(0.1)
	_check((g.hud.event_warn_titles() as Array).has("补给空投"), "空投有预警")
	_check(ev.crates.is_empty(), "预警期间还没落箱")
	await _sec(3.1)
	_check(ev.crates.size() == 1, "预警后投下补给箱")
	if ev.crates.is_empty():
		await _ev_end(g)
		return
	var crate: Variant = ev.crates[0]
	_check(crate.fall > 0.0, "箱子从空中落下")
	await _sec(0.5)
	await _shot("75_airdrop_fall_%s" % m.map_id)
	await _sec(ev.FALL_TIME)
	_check(crate.fall <= 0.0, "箱子落地")
	_check((ev.chips() as Array).size() == 1, "HUD 标签提示去捡")
	_check(m.reach_field(m.cell_of(g.player.position), m.BLOCK_PLAYER)[m.cell_of(crate.pos)] >= 0, "玩家走得到落点")
	var coins0: int = g.coins
	g.pickups.items.clear()
	var waited := 0.0
	while not ev.crates.is_empty() and waited < 28.0:
		_test_bot.move = _test_bot.go_to(g.player, crate.pos)
		await _sec(0.05)
		waited += 0.05
	_test_bot.move = Vector2.ZERO
	_check(ev.crates.is_empty() and crate.life > 0.0, "限时内走过去捡到了（%.1f 秒）" % waited)
	_check(g.pickups.items.size() >= 3, "开箱掉出金币、弹药和道具（%d）" % g.pickups.items.size())
	await _sec(1.5)
	_check(g.coins > coins0, "金币入账（%d -> %d）" % [coins0, g.coins])
	g.player.position = m.player_start
	# 限时：不捡就过期，也不给东西
	var coins1: int = g.coins
	g.pickups.items.clear()
	ev.drop_crate(m.edge_spot(g._rng, g.player.position))
	var late: Variant = ev.crates[0]
	late.fall = 0.01
	late.life = 0.2
	await _sec(0.5)
	_check(ev.crates.is_empty(), "过期的箱子会消失")
	_check(g.pickups.items.is_empty() and g.coins == coins1, "过期的箱子不给东西")
	# 商店里不计时，下一波还能去捡
	ev.drop_crate(m.edge_spot(g._rng, g.player.position))
	var kept: Variant = ev.crates[0]
	g.state = g.State.SHOP
	await _sec(0.3)
	_check(is_equal_approx(kept.fall, ev.FALL_TIME), "商店里箱子不计时")
	g.state = g.State.COMBAT
	# 第 8 波起投两个
	ev.crates.clear()
	g.wave = 8
	ev._incident = "airdrop"
	ev._fire_incident()
	_check(ev.crates.size() == 2, "后期波次投两个箱子")
	await _ev_end(g)


func _event_vanguard(g: Variant) -> void:
	var ev: Variant = g.events
	ev.enabled = true
	ev.forced = "vanguard"
	ev._plan_wave = 0
	g.wave = 6
	var full: int = GameData.build_spawn_queue(6).size()
	g._begin_countdown(6)
	_check(g.state == g.State.COUNTDOWN, "先遣尸群在波前触发")
	_check(g._state_t > g.COUNTDOWN_TIME, "倒计时加长了")
	_check(g.zombies.is_empty() and g._queue.size() == full, "预警时还没出怪")
	await _sec(0.1)
	_check((g.hud.event_warn_titles() as Array).has("先遣尸群"), "先遣尸群有预警")
	await _sec(1.6)
	_check(g.state == g.State.COUNTDOWN, "先遣尸群出现时还在倒计时")
	_check(g.zombies.size() == GameData.VANGUARD_COUNT + 1, "提前刷出一小撮（%d）" % g.zombies.size())
	_check(g.zombies.size() + g._queue.size() == full, "本波总数不变（%d）" % full)
	var kinds_ok := true
	for z: Variant in g.zombies:
		kinds_ok = kinds_ok and (z.kind == "walker" or z.kind == "runner")
	_check(kinds_ok, "先遣的都是小怪")
	await _shot("76_vanguard_%s" % g.map.map_id)
	g._queue = ["walker"] as Array[String]
	g._spawn_t = 99999.0
	g.state = g.State.COMBAT
	await _ev_end(g)


func _event_emp(g: Variant) -> void:
	var m: Variant = g.map
	# 没有炮塔时换成空投，不白等
	await _ev_begin(g, "emp", 4)
	var ev: Variant = g.events
	ev.begin_incident("emp")
	_check(ev._incident == "airdrop", "没有炮塔时电磁干扰换成空投")
	ev._incident = ""
	ev._warn_t = -1.0
	g.coins = 99999
	var cell: int = m.cell_of(m.player_start) + 3
	_check(g.try_place_turret(cell), "放一座测试炮塔")
	g.coins = 0
	var t: Variant = g.turrets[0]
	g._spawn_zombie("tank")
	var z: Variant = g.zombies[g.zombies.size() - 1]
	z.position = t.position + Vector2(40, z.center_h - 6.0)
	z.hp = 1e6
	z.max_hp = 1e6
	z._stun_t = 999.0
	await _sec(1.5)
	_check(z.hp < 1e6, "平时炮塔会开火")
	ev.begin_incident("emp")
	_check((g.hud.event_warn_titles() as Array).has("电磁干扰"), "电磁干扰有预警")
	_check(not ev.jammed(), "预警期间炮塔还能打")
	await _sec(3.1)
	_check(ev.jammed(), "预警后炮塔被干扰")
	await _sec(0.5)
	var hp_jam: float = z.hp
	await _shot("77_emp_%s" % m.map_id)
	await _sec(2.0)
	_check(is_equal_approx(z.hp, hp_jam), "干扰期间炮塔不开火")
	_check((ev.chips() as Array).size() >= 1, "HUD 显示电磁干扰")
	await _sec(GameData.EMP_JAM_TIME - 2.2)
	_check(not ev.jammed() and ev.overclock_t > 0.0, "干扰结束转入过载")
	_check(ev.turret_rate() < 1.0, "过载时射速提升")
	var hp_over: float = z.hp
	await _sec(1.0)
	_check(z.hp < hp_over, "干扰结束后炮塔恢复开火")
	t.take_damage(99999.0)
	g.map.rebuild_flow()
	await _ev_end(g)

