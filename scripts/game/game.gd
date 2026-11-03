extends Node2D
## 游戏主控：状态机、波次导演、经济与计分、屏幕震动、命中停顿。

enum State {COUNTDOWN, COMBAT, CLEARED, SHOP, PLACING, OVER}

const PlayerScene := preload("res://scenes/entities/player.tscn")
const ZombieScene := preload("res://scenes/entities/zombie.tscn")
const TurretScene := preload("res://scenes/entities/turret.tscn")
const BaseScene := preload("res://scenes/entities/base_core.tscn")
const Shop := preload("res://scripts/game/shop_catalog.gd")

const COUNTDOWN_TIME := 3.0
const CLEARED_TIME := 2.2
const MAX_ALIVE := 90
const BUCKET := 32
const BUCKET_W := 33
const BUCKET_H := 23
const COMBO_WINDOW := 2.6
## 召唤物和分裂小怪可以稍微超过同屏上限，免得分裂体死了没有小怪。
const MINION_OVERFLOW := 15
## Boss 在场时普通僵尸出得慢一些，把注意力留给 Boss。
const BOSS_SPAWN_SLOW := 1.8
const BOSS_DOWN_HOLD := 2.2

@onready var map: Node2D = $Map
@onready var decals: Node2D = $Decals
@onready var events: Node2D = $Events
@onready var pickups: Node2D = $Pickups
@onready var entities: Node2D = $Entities
@onready var hazards: Node2D = $Hazards
@onready var bullets: Node2D = $Bullets
@onready var ordnance: Node2D = $Ordnance
@onready var fx: Node2D = $Fx
@onready var camera: Camera2D = $Camera
@onready var tint: CanvasModulate = $Tint
@onready var hud: Control = $UI/HUD
@onready var shop_ui: Control = $UI/Shop
@onready var pause_ui: Control = $UI/PauseMenu
@onready var over_ui: Control = $UI/GameOver

var state := State.COUNTDOWN
var wave := 0
var score := 0
var coins := 130
var kills := 0
var coins_earned := 0
var combo := 0
var combo_t := 0.0
var best_combo := 0
var time_alive := 0.0
var turret_level := 1
## 基地有装甲：僵尸对基地的伤害打折，否则尸群一贴上来几秒就没了。
var base_damage_scale := 0.42
var purchases := {}
## 上一次用核弹的波次，每波限一次。
var nuke_wave := 0
var god_mode := false
var victory := false
var end_reason := ""
var result_rank := 0
## 克制反馈飘字（叮、弱点！……）各出现了几次，机器人日志和测试看这个。
var cue_stats := {}
## 本局每种僵尸杀了几只，进化条件要看。
var kind_kills := {}
## 危险等级和契约：开局从存档读，整局不变。结算分 = 原分 × score_mult，raw_score 留着给结算界面看。
var danger := 0
var contracts: Array[String] = []
var score_mult := 1.0
var raw_score := 0
## 不灭契约，僵尸每帧都要看，缓存一下。
var regen_on := false

var player: Node2D
var base: Node2D
var zombies: Array = []
var turrets: Array = []
var boss_list: Array = []

var _rng := RandomNumberGenerator.new()
var _queue: Array[String] = []
var _spawn_t := 0.0
var _state_t := 0.0
var _spawn_side := "top"
var _group_left := 0
var _buckets: Array = []
var _used_buckets: Array[int] = []
var _trauma := 0.0
var _kick := Vector2.ZERO
var _cam_pos := Vector2.ZERO
var _shake_time := 0.0
var _stop_until_ms := 0
var _groan_t := 3.0
var _base_alert_t := 0.0
var _over_t := -1.0
var _hit_marker := 0.0
var _boss_hold_t := 0.0
var _acid_t := 0.0
var _map_spec: Dictionary = {}
var _map_tint := Color.WHITE


func _ready() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	process_physics_priority = -10
	_rng.randomize()
	if Harness.fixed_seed >= 0:
		_rng.seed = Harness.fixed_seed
	_buckets.resize(BUCKET_W * BUCKET_H)
	for i in _buckets.size():
		_buckets[i] = []
	danger = Save.danger
	contracts = Save.contracts.duplicate()
	score_mult = GameData.run_mult(danger, contracts)
	regen_on = has_contract("regen")
	_map_spec = GameData.MAPS[Save.map_id]
	_map_tint = Color(String(_map_spec["tint"]))
	coins = int(_map_spec["coins"])
	base_damage_scale = float(_map_spec["base_scale"])
	tint.color = _map_tint
	map.setup(self, _rng)
	decals.position = Vector2.ZERO
	bullets.setup(self, map)
	ordnance.setup(self, map)
	hazards.setup(self, map)
	fx.setup(self, decals)
	pickups.setup(self)
	events.setup(self, map, _rng)
	base = BaseScene.instantiate()
	entities.add_child(base)
	base.setup(self, map)
	player = PlayerScene.instantiate()
	player.position = map.player_start
	entities.add_child(player)
	player.setup(self, map)
	_cam_pos = player.position
	camera.position = _cam_pos
	camera.make_current()
	hud.setup(self)
	shop_ui.setup(self)
	pause_ui.setup(self)
	over_ui.setup(self)
	Sfx.play_music("menu")
	Harness.on_game_ready(self)
	_begin_countdown(Harness.start_wave)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ---------------------------------------------------------------------------
# 主循环
# ---------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_rebuild_buckets()
	_state_t -= dt
	match state:
		State.COUNTDOWN:
			if _state_t <= 0.0:
				_begin_combat()
		State.COMBAT:
			time_alive += dt
			_tick_spawner(dt)
			_tick_ambience(dt)
			_tick_special(dt)
			_boss_hold_t -= dt
			if _queue.is_empty() and zombies.is_empty() and _boss_hold_t <= 0.0:
				_wave_cleared()
		State.CLEARED:
			if _state_t <= 0.0:
				_open_shop()
		State.OVER:
			_tick_game_over()
	if combo > 0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
	_hit_marker = maxf(_hit_marker - dt, 0.0)
	_base_alert_t = maxf(_base_alert_t - dt, 0.0)
	_update_camera(dt)
	_update_mouse_mode()


func _process(_dt: float) -> void:
	# 命中停顿用真实时间结束，不受 time_scale 影响
	if _stop_until_ms > 0 and Time.get_ticks_msec() >= _stop_until_ms:
		_stop_until_ms = 0
		if state != State.OVER:
			Engine.time_scale = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		if state == State.PLACING:
			cancel_turret_placement()
		elif state != State.OVER:
			pause_ui.open()
		get_viewport().set_input_as_handled()
		return
	if state == State.PLACING:
		if event.is_action_pressed("cancel"):
			cancel_turret_placement()
		elif event.is_action_pressed("fire"):
			try_place_turret(map.cell_of(get_global_mouse_position() + Vector2(0, 4)))
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# 切走窗口时自动暂停，避免回来时基地已经没了。网页版只发窗口焦点通知
	if (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT) and not Harness.automated() and is_node_ready():
		if state == State.COMBAT or state == State.COUNTDOWN:
			pause_ui.open()


func player_can_act() -> bool:
	return state == State.COUNTDOWN or state == State.COMBAT or state == State.CLEARED


func player_can_walk() -> bool:
	return player_can_act() or state == State.PLACING


# ---------------------------------------------------------------------------
# 波次流程
# ---------------------------------------------------------------------------

func _begin_countdown(next_wave: int) -> void:
	wave = next_wave
	state = State.COUNTDOWN
	_state_t = COUNTDOWN_TIME
	_queue = GameData.build_spawn_queue(wave)
	_group_left = 0
	pickups.magnet_all = false
	if wave > 1:
		var dropped: int = map.alive_barrels()
		if dropped < 10:
			map.respawn_barrels(_rng, 2)
	events.on_countdown(wave)
	_tween_tint(_combat_tint())
	var sub: String = GameData.wave_hint(wave)
	if sub == "":
		sub = "共 %d 只僵尸，准备迎战" % _queue.size()
	hud.announce("第 %d 波：%s" % [wave, GameData.wave_name(wave)], sub, COUNTDOWN_TIME)
	Sfx.play_music("menu")


func _begin_combat() -> void:
	state = State.COMBAT
	_spawn_t = 0.0
	Sfx.play("siren", -4.0, 0.0)
	Sfx.play_music("combat")
	events.on_combat()
	for kind: String in GameData.BOSSES.keys():
		if _queue.has(kind):
			hud.announce("Boss 战：%s" % GameData.BOSSES[kind]["title"], "击退前锋后它就会现身", 2.6)
			Sfx.play("boss_roar", -6.0)


func _tick_spawner(dt: float) -> void:
	if _queue.is_empty():
		return
	_spawn_t -= dt
	if _spawn_t > 0.0 or zombies.size() >= MAX_ALIVE:
		return
	_spawn_t = GameData.spawn_interval(wave) * randf_range(0.7, 1.3)
	if not boss_list.is_empty():
		_spawn_t *= BOSS_SPAWN_SLOW
	if _group_left <= 0:
		_spawn_side = ["top", "bottom", "left", "right"][_rng.randi() % 4]
		var group: Array = _map_spec["group"]
		_group_left = _rng.randi_range(int(group[0]), int(group[1]) + wave / int(_map_spec["group_grow"]))
	var burst := 1 + wave / 5
	for i in burst:
		if _queue.is_empty():
			break
		_spawn_zombie(_queue.pop_back())
		_group_left -= 1


func _spawn_zombie(kind: String) -> void:
	var cells: Array = map.spawn_cells[_spawn_side]
	if cells.is_empty():
		for side: String in map.spawn_cells.keys():
			if not map.spawn_cells[side].is_empty():
				cells = map.spawn_cells[side]
				break
	# 优先从道路方向过来，地图边缘看起来才有“涌向基地”的感觉
	var cell: int = cells[_rng.randi() % cells.size()]
	var offset := Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-4, 4))
	var pos: Vector2 = map.cell_center(cell) + offset
	pos = map.unstick(pos, 5.0, map.BLOCK_ZOMBIE)
	var z := _add_zombie(kind, pos)
	if z.is_boss:
		boss_list.append(z)
		_on_boss_spawn(z)


func _add_zombie(kind: String, pos: Vector2) -> Node2D:
	var z: Node2D = ZombieScene.instantiate()
	entities.add_child(z)
	z.setup(self, map, kind, pos, wave)
	zombies.append(z)
	return z


## 先遣尸群：从本波队列里提前放几只小怪，从指定方向来。本波总数不变。
func spawn_vanguard(side: String, count: int) -> int:
	var sent := 0
	var old_side := _spawn_side
	_spawn_side = side
	for kind: String in ["runner", "walker"]:
		while sent < count and _queue.has(kind):
			_queue.erase(kind)
			_spawn_zombie(kind)
			sent += 1
	_spawn_side = old_side
	return sent


## 倒计时加长，给先遣尸群留出提前到场的时间。
func extend_countdown(seconds: float) -> void:
	_state_t += seconds


## 召唤物和分裂小怪。超过上限返回 null。
func spawn_minion(kind: String, pos: Vector2, owner_node: Variant = null) -> Variant:
	if zombies.size() >= MAX_ALIVE + MINION_OVERFLOW:
		return null
	var ground: Vector2 = pos
	if not GameData.ZOMBIES[kind].get("flying", false):
		ground = map.unstick(pos, 5.0, map.BLOCK_ZOMBIE)
	var z := _add_zombie(kind, ground)
	z.master = owner_node
	return z


## 主人死了，它叫来的东西一起散，不给金币。
func dismiss_minions(owner_node: Variant) -> void:
	for z: Variant in zombies.duplicate():
		if z.master == owner_node and not z.dead:
			fx.dust(z.position, 5)
			z.no_blast = true
			z.dismissed = true
			z.take_damage(99999.0, Vector2.UP, 0.0, false)


## 尖叫：半径内的僵尸加速冲锋。
func rally(pos: Vector2, radius: float, seconds: float, source: Variant) -> void:
	for z: Variant in zombies_near(pos, radius + 16.0):
		if z != source and not z.dead and z.position.distance_to(pos) <= radius:
			z.rally(seconds)
	fx.ring(pos + Vector2(0, -8), radius, 0.5, Color("#ff5070"))


# ---------------------------------------------------------------------------
# Boss 战
# ---------------------------------------------------------------------------

func _on_boss_spawn(z: Variant) -> void:
	var spec: Dictionary = GameData.BOSSES[z.kind]
	hud.announce("警告：%s 来袭！" % spec["title"], String(spec["warn"]), 2.6)
	Sfx.play("boss_roar")
	Sfx.play_music("boss")
	add_shake(0.4)


func on_boss_phase(z: Variant, phase_spec: Dictionary, index: int, total: int) -> void:
	var title: String = GameData.BOSSES[z.kind]["title"]
	Harness.note("%s 进入第 %d/%d 阶段 %s（血 %d/%d）" % [title, index + 1, total, phase_spec["name"], roundi(z.hp), roundi(z.max_hp)])
	hud.announce("%s 第 %d/%d 阶段：%s" % [title, index + 1, total, phase_spec["name"]], String(phase_spec["sub"]), 2.2)
	Sfx.play("boss_phase")
	add_shake(0.8)
	fx.ring(z.center(), 70.0, 0.5, Color("#ffd080"))
	fx.dust(z.position, 16)


func on_boss_down(z: Variant) -> void:
	if z.overkill:
		return
	var spec: Dictionary = GameData.BOSSES[z.kind]
	Harness.note("%s 被击败，用过的招式：%s" % [spec["title"], ",".join(z._brain.moves_used.keys())])
	_boss_hold_t = BOSS_DOWN_HOLD
	var loot := "快去捡战利品：%s" % GameData.TROPHIES[spec["trophy"]]["name"] if spec.has("trophy") else "快去捡掉落的补给"
	hud.announce("%s 倒下了！" % spec["title"], loot, BOSS_DOWN_HOLD)
	Sfx.play("boss_down")
	hazards.clear_owner(z)
	for i in 5:
		explode.call_deferred(z.position + Vector2(randf_range(-26, 26), randf_range(-34, 4)), 0.0, 30.0, true)
	if boss_list.is_empty():
		Sfx.play_music("combat")
	if bool(spec.get("final", false)):
		# 尸王一倒，整座城的尸群跟着散，掉落全部飞向玩家
		_queue.clear()
		pickups.magnet_all = true
		hazards.clear()
		for other: Variant in zombies.duplicate():
			if other != z and not other.dead:
				other.no_blast = true
				other.take_damage(99999.0, Vector2.UP, 0.0, false)


## 战利品：金币雨、必掉道具、专属战利品和一个急救包。
func _boss_loot(z: Variant) -> void:
	var spec: Dictionary = GameData.BOSSES[z.kind]
	var at: Vector2 = z.position + Vector2(0, -4)
	for id: String in spec["drops"]:
		pickups.drop(at, "item", 1, id)
	pickups.drop(at, "med", 25)
	if spec.has("trophy"):
		pickups.drop(at, "trophy", 1, String(spec["trophy"]))
	fx.text(z.position + Vector2(0, -z.center_h * 2.0 - 12.0), "金币雨 +%d" % int(GameData.ZOMBIES[z.kind]["coins"]), Color("#ffe060"))


# ---------------------------------------------------------------------------
# 特殊波
# ---------------------------------------------------------------------------

func _tick_special(dt: float) -> void:
	if GameData.wave_special(wave) != "acid_rain" or _queue.is_empty() and zombies.is_empty():
		return
	_acid_t -= dt
	if _acid_t > 0.0 or player == null or not player.alive:
		return
	_acid_t = GameData.ACID_RAIN_GAP
	var count := GameData.ACID_RAIN_COUNT
	# Boss 在场时酸雨变稀，地上的圈不至于和 Boss 的招式搅成一团
	if not boss_list.is_empty():
		_acid_t *= GameData.ACID_RAIN_BOSS_GAP
		count = maxi(1, count - 1)
	for i in count:
		var at: Vector2 = player.position + player.velocity * 0.6 + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 70.0)
		hazards.acid(at, GameData.ACID_RAIN_DAMAGE * GameData.damage_scale(wave))


func _tick_ambience(dt: float) -> void:
	_groan_t -= dt
	if _groan_t <= 0.0 and not zombies.is_empty():
		_groan_t = randf_range(1.4, 3.6)
		Sfx.play("groan", -13.0, 0.25)


func _wave_cleared() -> void:
	events.on_wave_cleared()
	bullets.clear_hazards()
	hazards.clear()
	ordnance.clear_field()
	pickups.magnet_all = true
	var bonus := GameData.wave_bonus(wave)
	coins += bonus
	coins_earned += bonus
	score += 100 * wave + roundi(base.hp / base.max_hp * 100.0) * wave
	Sfx.play("wave_clear")
	Sfx.play_music("menu")
	_tween_tint(_map_tint)
	if wave >= GameData.MAX_WAVE:
		victory = true
		pickups.collect_all()
		hud.announce("守住了！救援直升机抵达", "你撑过了全部 %d 波" % GameData.MAX_WAVE, CLEARED_TIME)
		_finish_game("基地守住了，幸存者全部撤离。")
		return
	state = State.CLEARED
	_state_t = CLEARED_TIME
	hud.announce("第 %d 波 肃清" % wave, "奖励金币 +%d" % bonus, CLEARED_TIME)


func _open_shop() -> void:
	state = State.SHOP
	# 打扫战场：把没捡到的东西都塞给玩家
	shop_ui.open()
	Harness.on_shop_open(self)


func start_next_wave() -> void:
	shop_ui.close()
	player.reload_t = 0.0
	_begin_countdown(wave + 1)


func _combat_tint() -> Color:
	return _wave_tint() * _map_tint * events.tint_color()


func _wave_tint() -> Color:
	if GameData.wave_special(wave) == "blackout":
		return Color(0.42, 0.45, 0.68)
	if GameData.wave_special(wave) == "acid_rain":
		return Color(0.78, 0.92, 0.66)
	if wave >= GameData.MAX_WAVE:
		return Color(0.82, 0.58, 0.58)
	if GameData.boss_wave(wave):
		return Color(0.82, 0.68, 0.68)
	var night := clampf(float(wave) / GameData.MAX_WAVE, 0.0, 1.0)
	return Color(1.0, 0.97, 0.92).lerp(Color(0.62, 0.66, 0.86), night)


func _tween_tint(c: Color) -> void:
	var tw := create_tween()
	tw.tween_property(tint, "color", c, 1.0)


# ---------------------------------------------------------------------------
# 僵尸查询（空间哈希，每帧重建）
# ---------------------------------------------------------------------------

func _rebuild_buckets() -> void:
	for b in _used_buckets:
		_buckets[b].clear()
	_used_buckets.clear()
	for z: Variant in zombies:
		var p: Vector2 = z.position
		var bi := _bucket_index(p)
		if _buckets[bi].is_empty():
			_used_buckets.append(bi)
		_buckets[bi].append(z)


func _bucket_index(p: Vector2) -> int:
	return clampi(int(p.y) / BUCKET, 0, BUCKET_H - 1) * BUCKET_W + clampi(int(p.x) / BUCKET, 0, BUCKET_W - 1)


func zombies_near(pos: Vector2, radius: float) -> Array:
	var out: Array = []
	var x0 := clampi(int(pos.x - radius) / BUCKET, 0, BUCKET_W - 1)
	var x1 := clampi(int(pos.x + radius) / BUCKET, 0, BUCKET_W - 1)
	var y0 := clampi(int(pos.y - radius) / BUCKET, 0, BUCKET_H - 1)
	var y1 := clampi(int(pos.y + radius) / BUCKET, 0, BUCKET_H - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var b: Array = _buckets[y * BUCKET_W + x]
			if not b.is_empty():
				out.append_array(b)
	return out


func remove_zombie(z: Variant) -> void:
	zombies.erase(z)
	boss_list.erase(z)


func remove_turret(t: Variant) -> void:
	turrets.erase(t)


# ---------------------------------------------------------------------------
# 计分与掉落
# ---------------------------------------------------------------------------

func credit_kill(z: Variant, drops: bool) -> void:
	# 主人死后散掉的召唤物不算击杀，也不给钱
	if z.dismissed:
		return
	var stat: Dictionary = GameData.ZOMBIES[z.kind]
	kills += 1
	kind_kills[z.kind] = int(kind_kills.get(z.kind, 0)) + 1
	Harness.on_kill(z.kind)
	combo += 1
	combo_t = COMBO_WINDOW
	best_combo = maxi(best_combo, combo)
	score += roundi(int(stat["score"]) * combo_multiplier())
	if not drops:
		pickups.drop(z.position, "coin", int(stat["coins"]))
		return
	var total: int = ceili(float(stat["coins"]) * events.coin_mult * GameData.danger_coin_mult(danger))
	# Boss 叫来的精英只给一半钱，否则站着刷怪比打 Boss 还赚
	if z.master != null:
		total = (total + 1) / 2
	while total > 0:
		var v := mini(total, 10 if total >= 10 else 3)
		pickups.drop(z.position + Vector2(0, -4), "coin", v)
		total -= v
	if z.is_boss:
		score += int(stat["score"])
		if not z.overkill:
			_boss_loot(z)
		return
	if z.master != null:
		return
	var entry := GameData.roll_drop(z.kind)
	if entry.has("item"):
		pickups.drop(z.position + Vector2(0, -4), "item", 1, String(entry["item"]))
	elif entry.get("kind") == "ammo":
		pickups.drop(z.position + Vector2(0, -4), "ammo", 1)
	elif entry.get("kind") == "med":
		pickups.drop(z.position + Vector2(0, -4), "med", 25)


func has_contract(id: String) -> bool:
	return contracts.has(id)


func kills_of(kinds: Array) -> int:
	var n := 0
	for k: String in kinds:
		n += int(kind_kills.get(k, 0))
	return n


func combo_multiplier() -> float:
	return 1.0 + minf(combo / 10.0, 2.0) * 0.5


func add_coins(amount: int) -> void:
	coins += amount
	coins_earned += amount


func spend_coins(amount: int) -> void:
	coins = maxi(coins - amount, 0)


func grant_ammo_box() -> void:
	for id: String in player.owned_weapons():
		var st: Dictionary = player.weapon_state[id]
		if int(st["reserve"]) >= 0:
			st["reserve"] = int(st["reserve"]) + int(GameData.WEAPONS[id].get("ammo_drop", 0))
	fx.text(player.position + Vector2(0, -22), "弹药补给", Color("#c8e070"))


func count_cue(text: String) -> void:
	cue_stats[text] = int(cue_stats.get(text, 0)) + 1


func on_bullet_hit() -> void:
	_hit_marker = 0.1


func hit_marker_active() -> bool:
	return _hit_marker > 0.0


func on_player_hurt(amount: float) -> void:
	add_shake(0.55)
	hitstop(0.05)
	hud.flash_hurt()
	fx.number(player.position + Vector2(0, -20), roundi(amount), Color("#ff5040"))
	Sfx.play("hurt")
	combo = 0


func on_base_hurt(_amount: float) -> void:
	if _base_alert_t <= 0.0:
		hud.alert_base()
		_base_alert_t = 2.5
	Sfx.play("base_hit", -6.0)
	add_shake(0.08)


func on_player_died() -> void:
	Sfx.play("zombie_die", 2.0)
	_finish_game("你倒下了，基地失去了最后的守卫者。")


func on_base_destroyed() -> void:
	for i in 5:
		explode.call_deferred(base.position + Vector2(randf_range(-30, 30), randf_range(-50, -6)), 0.0, 44.0, true)
	base.visible = false
	decals.stamp(Art.scorch, base.position + Vector2(0, -24))
	_finish_game("基地被摧毁了，这座城市彻底沦陷。")


func _finish_game(reason: String) -> void:
	if state == State.OVER:
		return
	state = State.OVER
	end_reason = reason
	_over_t = 1.6
	shop_ui.close()
	# 最后的慢镜头
	Engine.time_scale = 0.35 if not victory else 1.0
	_stop_until_ms = 0
	Sfx.play_music("")
	Sfx.play("victory" if victory else "game_over")
	# 危险和契约的倍率在结算时一次乘上；通关解锁下一级危险
	raw_score = score
	score = floori(score * score_mult + 0.001)
	if victory:
		Save.unlock_danger(danger + 1)
	result_rank = Save.submit(score, wave, kills, victory, danger, contracts, score_mult)
	Harness.on_game_over(self)


func _tick_game_over() -> void:
	if _over_t < 0.0:
		return
	_over_t -= get_physics_process_delta_time() / maxf(Engine.time_scale, 0.01)
	if _over_t < 0.0:
		Engine.time_scale = 1.0
		over_ui.open()


# ---------------------------------------------------------------------------
# 爆炸（自爆僵尸、炸药桶、炮塔残骸都走这里）
# ---------------------------------------------------------------------------

## spare_base：玩家自己的榴弹和手雷不伤基地。
## heavy 是对坦克和覆甲 Boss 的额外倍率（铝热榴弹）。
func explode(pos: Vector2, damage: float, explode_radius: float, friendly: bool, spare_base := false, heavy := 1.0) -> void:
	var radius: float = explode_radius * events.splash_mult
	fx.explosion(pos, radius)
	ordnance.hurt_decoys(pos, damage, radius)
	decals.stamp(Art.scorch, pos + Vector2(0, 6))
	Sfx.play("explode", -1.0, 0.1)
	add_shake(0.75)
	hitstop(0.07)
	if damage <= 0.0:
		return
	for z: Variant in zombies_near(pos, radius + 12.0):
		if z.dead:
			continue
		var d: float = pos.distance_to(z.center())
		if d < radius + float(z.hit_r):
			var falloff := 1.0 - clampf(d / (radius + 12.0), 0.0, 0.7)
			var mult := 2.2 if friendly else 1.4
			# 战利品「掘地晶石」：玩家的爆炸打 Boss 更疼
			if friendly and z.is_boss:
				mult *= player.blast_boss_mult
			if heavy != 1.0 and (z.kind == "tank" or (z.is_boss and z.armored())):
				mult *= heavy
			# 爆炸不看朝向，还会狠狠削一下盾
			z.shield_hit(damage * falloff * mult)
			z.take_damage(damage * falloff * mult, pos.direction_to(z.center()), 160.0, true, "blast")
	if player != null and player.alive:
		var pd: float = pos.distance_to(player.position + Vector2(0, -6))
		if pd < radius:
			var falloff := 1.0 - clampf(pd / radius, 0.0, 0.7)
			player.take_damage(damage * falloff * (0.6 if friendly else 1.0), pos)
	for s: Variant in _structures_in(pos, radius):
		if s.kind == "barrel":
			s.take_damage.call_deferred(1000.0)
		elif s.kind == "base":
			if not spare_base:
				s.take_damage(damage * 0.6)
		elif not friendly:
			s.take_damage(damage * 1.5)


## 酸雨溅到的僵尸湿身。
func soak_area(pos: Vector2, radius: float, seconds: float) -> void:
	for z: Variant in zombies_near(pos, radius + 12.0):
		if not z.dead and not z.flying and z.position.distance_to(pos) < radius:
			z.soak(seconds)


## Boss 招式的落点结算：伤玩家、诱饵和建筑，不伤僵尸。
func damage_area(pos: Vector2, radius: float, damage: float, structure_mult: float) -> void:
	ordnance.hurt_decoys(pos, damage, radius)
	if player != null and player.alive and pos.distance_to(player.position) < radius:
		player.take_damage(damage, pos)
	for s: Variant in _structures_in(pos, radius):
		if s.kind == "barrel":
			s.take_damage.call_deferred(1000.0)
		elif s.kind == "base":
			s.take_damage(damage)
		else:
			s.take_damage(damage * structure_mult)


func _structures_in(pos: Vector2, radius: float) -> Array:
	var seen := {}
	var tile: int = map.TILE
	var cx0 := clampi(int(pos.x - radius) / tile, 0, map.W - 1)
	var cx1 := clampi(int(pos.x + radius) / tile, 0, map.W - 1)
	var cy0 := clampi(int(pos.y - radius) / tile, 0, map.H - 1)
	var cy1 := clampi(int(pos.y + radius) / tile, 0, map.H - 1)
	var hit_list: Array = []
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var i: int = map.idx(cx, cy)
			if not map.structures.has(i) or map.cell_center(i).distance_to(pos) > radius:
				continue
			var s: Variant = map.structures[i]
			if not seen.has(s):
				seen[s] = true
				hit_list.append(s)
	return hit_list


# ---------------------------------------------------------------------------
# 商店动作
# ---------------------------------------------------------------------------

func shop_items() -> Array:
	return Shop.items(self)


func shop_can_buy(item: Dictionary) -> bool:
	return Shop.can_buy(self, item)


func shop_buy(id: String) -> bool:
	return Shop.buy(self, id)


func after_repair() -> void:
	for t: Variant in turrets:
		t.repair_full()
	player.position = map.unstick(player.position, player.BOX_R, map.BLOCK_PLAYER)


func begin_turret_placement() -> void:
	state = State.PLACING
	shop_ui.close()


func cancel_turret_placement() -> void:
	state = State.SHOP
	shop_ui.open()


func try_place_turret(cell: int) -> bool:
	var cost := Shop.turret_cost(self)
	if coins < cost or not map.can_place_turret(cell):
		Sfx.play("deny")
		return false
	var t: Node2D = TurretScene.instantiate()
	entities.add_child(t)
	t.setup(self, map, cell)
	turrets.append(t)
	spend_coins(cost)
	Sfx.play("buy")
	fx.dust(t.position, 8)
	if state == State.PLACING:
		state = State.SHOP
		shop_ui.open()
	return true


# ---------------------------------------------------------------------------
# 打击感：屏幕震动 + 命中停顿 + 枪口后坐
# ---------------------------------------------------------------------------

func add_shake(amount: float) -> void:
	if Save.shake_on:
		_trauma = minf(_trauma + amount, 1.0)


func kick_camera(v: Vector2) -> void:
	if Save.shake_on:
		_kick -= v


func hitstop(seconds: float) -> void:
	# 核弹波及几十只僵尸，逐只停顿会把冲击波拖成慢动作
	if Harness.bot != null or state == State.OVER or ordnance.nuke_active():
		return
	Engine.time_scale = 0.04
	_stop_until_ms = maxi(_stop_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))


func _update_camera(dt: float) -> void:
	var target: Vector2 = player.position
	if player.alive and player_can_walk():
		var look: Vector2 = get_global_mouse_position() - player.position
		if Harness.bot == null:
			target += look.limit_length(float(_map_spec["look_limit"])) * float(_map_spec["look_gain"])
	_cam_pos = _cam_pos.lerp(target, clampf(dt * 7.0, 0.0, 1.0))
	var half := Vector2(240, 135)
	_cam_pos.x = clampf(_cam_pos.x, half.x, map.PIXEL_W - half.x)
	_cam_pos.y = clampf(_cam_pos.y, half.y, map.PIXEL_H - half.y)
	_trauma = maxf(_trauma - dt * 2.2, 0.0)
	_shake_time += dt
	_kick = _kick.lerp(Vector2.ZERO, clampf(dt * 16.0, 0.0, 1.0))
	var strength := _trauma * _trauma * 9.0
	var shake := Vector2(sin(_shake_time * 61.0 + 1.3), cos(_shake_time * 53.0)) * strength
	camera.position = _cam_pos.round()
	camera.offset = (shake + _kick).round()


func _update_mouse_mode() -> void:
	var want := Input.MOUSE_MODE_VISIBLE
	if not get_tree().paused and (state == State.COMBAT or state == State.COUNTDOWN or state == State.CLEARED):
		want = Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != want:
		Input.mouse_mode = want
