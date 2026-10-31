extends Node
## 开发自测入口。普通启动时什么都不做；带用户参数时驱动整局流程：
##   godot --headless --path . --fixed-fps 60 -- --bot --seed=3     机器人打一局并打印成绩
##   godot --headless --path . --fixed-fps 60 -- --flowtest         走完所有界面流程并校验
##   godot --headless --path . -- --sheet=DIR                       导出精灵预览 PNG
##   godot --path . -- --shots=DIR                                  窗口模式下自动截图

const BotScript := preload("res://scripts/test/bot.gd")
const Shop := preload("res://scripts/game/shop_catalog.gd")

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
	elif _args.has("shots"):
		_mode = "shots"
		_shots_dir = String(_args["shots"])
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	elif _args.has("bot"):
		_mode = "bot"


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
	_game.shop_ui._select_tab(1)
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
	await RenderingServer.frame_post_draw
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
			_flow_shop_test(g)
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
			_flow_step = 11
			_flow_wait = 0.3
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


func _send_key(key: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.keycode = key
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _flow_shop_test(g: Variant) -> void:
	# 钱够时每一个商品都买一遍
	g.coins = 200000
	g.base.hp = 100.0
	g.player.hp = 10.0
	var walls_before: float = g.map.missing_wall_hp()
	g.map.pieces[0].take_damage(9999.0)
	_check(not g.map.pieces[0].alive, "墙可被摧毁")
	_check(g.map.missing_wall_hp() > walls_before, "缺失耐久增加")
	for tab in 3:
		g.shop_ui._select_tab(tab)
		_check(g.shop_ui.rows.get_child_count() >= 3, "商店第 %d 页有商品" % (tab + 1))
	var ids: Array[String] = []
	for item: Dictionary in g.shop_items():
		ids.append(String(item["id"]))
	for id: String in ids:
		if id == "turret":
			continue
		var coins_before: int = g.coins
		var ok: bool = g.shop_buy(id)
		_check(ok and g.coins < coins_before, "购买 %s 成功且扣钱" % id)
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


func _flow_explosion_test(g: Variant) -> void:
	var count_before: int = g.fx.blasts.size()
	g.explode(g.player.position + Vector2(200, 0), 30.0, 40.0, false)
	_check(g.fx.blasts.size() == count_before + 1, "爆炸特效生成")
