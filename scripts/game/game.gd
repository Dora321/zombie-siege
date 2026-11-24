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
const AUTO_REPAIR_INTERVAL := 4.0
const REPAIR_COLOR := Color("#88f098")

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
@onready var touch_ui: Control = $UI/TouchControls
@onready var shop_ui: Control = $UI/Shop
@onready var perk_ui: Control = $UI/PerkPicker
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
var endless := false
var boss_rush := false
var hero_id := "captain"
var perks: Array[String] = []
var placing_turret_kind := "mg"
var _endless_recorded_victory := false
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
var _auto_repair_t := 0.0
var _vamp_kills := 0
var _perk_pending := false
var _perk_choices: Array[String] = []
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
	var resume: Dictionary = {}
	if not Harness.automated() and not Save.pending_resume.is_empty():
		resume = Save.pending_resume.duplicate(true)
		Save.pending_resume = {}
		Save.map_id = String(resume.get("map_id", Save.map_id))
		Save.danger = int(resume.get("danger", 0))
		Save.contracts.assign(resume.get("contracts", []))
		Save.hero_id = String(resume.get("hero_id", "captain"))
		Save.game_mode = "boss_rush" if bool(resume.get("boss_rush", false)) else "normal"
	if not Harness.automated():
		hero_id = Save.hero_id if GameData.HEROES.has(Save.hero_id) else "captain"
		boss_rush = Save.game_mode == "boss_rush"
	danger = Save.danger
	contracts = Save.contracts.duplicate()
	score_mult = GameData.run_mult(danger, contracts)
	regen_on = has_contract("regen")
	_map_spec = GameData.MAPS[Save.map_id]
	_map_tint = Color(String(_map_spec["tint"]))
	coins = GameData.BOSS_RUSH_START_COINS if boss_rush else int(_map_spec["coins"])
	if resume.is_empty() and hero_id == "engineer":
		coins += 40
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
	touch_ui.setup(self)
	shop_ui.setup(self)
	perk_ui.setup(self)
	pause_ui.setup(self)
	over_ui.setup(self)
	Harness.on_game_ready(self)
	if not resume.is_empty():
		_restore_resume_state(resume)
		events.plan_wave(wave + 1)
		if _perk_choices.is_empty():
			_open_shop()
		else:
			_open_perk_picker()
		hud.announce("继续行动", "第 %d 波前休整" % (wave + 1), 2.0)
	elif boss_rush:
		events.plan_wave(1)
		_open_shop()
	else:
		_begin_countdown(Harness.start_wave)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Mobile.reset_placement(Vector2.ZERO, false)


# ---------------------------------------------------------------------------
# 波次间续玩存档
# ---------------------------------------------------------------------------

func _save_resume_state() -> void:
	if Harness.automated():
		return
	var turret_entries: Array[Dictionary] = []
	var turret_hp := {}
	for t: Variant in turrets:
		if t.alive:
			turret_entries.append({
				"cell": t.cell, "kind": t.get_meta("turret_kind", "mg"),
				"cost": t.get_meta("purchase_cost", 0),
			})
			turret_hp[t.cell] = t.hp
	var wall_hp := {}
	for piece: Variant in map.pieces:
		if piece.kind != "barrel" and piece.hp < piece.max_hp:
			wall_hp[piece.cell] = piece.hp
	var player_data: Dictionary
	if player.has_method("export_run_state"):
		player_data = player.call("export_run_state")
	else:
		player_data = {
			"hp": player.hp, "max_hp": player.max_hp, "armor": player.armor,
			"weapon_id": player.weapon_id, "weapon_slots": player.weapon_slots,
			"loadout": player.loadout, "weapon_state": player.weapon_state,
			"items": player.items, "used_items": player.used_items, "selected_item": player.selected_item,
			"dot_mult": player.dot_mult,
			"sticky_mult": player.sticky_mult, "status_bonus": player.status_bonus,
			"blast_boss_mult": player.blast_boss_mult, "reflect_mult": player.reflect_mult,
		}
	Save.save_resume_run({
		"wave": wave, "endless": endless, "boss_rush": boss_rush, "score": score, "raw_score": raw_score,
		"hero_id": hero_id, "perks": perks, "perk_choices": _perk_choices,
		"auto_repair_t": _auto_repair_t, "vamp_kills": _vamp_kills,
		"coins": coins, "kills": kills, "coins_earned": coins_earned,
		"best_combo": best_combo, "time_alive": time_alive,
		"shots_fired": bullets.shots_fired, "shots_hit": bullets.shots_hit,
		"map_id": map.map_id, "danger": danger, "contracts": contracts,
		"turret_level": turret_level, "wall_tier": map.wall_tier,
		"base_hp": base.hp, "base_max_hp": base.max_hp, "purchases": purchases,
		"kind_kills": kind_kills, "turret_entries": turret_entries, "player": player_data,
		"wall_hp": wall_hp, "turret_hp": turret_hp,
	})


func _restore_resume_state(data: Dictionary) -> void:
	wave = int(data.get("wave", 1))
	endless = not boss_rush and bool(data.get("endless", false))
	_endless_recorded_victory = endless
	for id: Variant in data.get("perks", []):
		if id is String and GameData.PERKS.has(id) and not has_perk(id):
			perks.append(id)
	for id: Variant in data.get("perk_choices", []):
		if id is String and GameData.PERKS.has(id) and not has_perk(id) and not _perk_choices.has(id):
			_perk_choices.append(id)
	_auto_repair_t = clampf(float(data.get("auto_repair_t", 0.0)), 0.0, AUTO_REPAIR_INTERVAL)
	_vamp_kills = clampi(int(data.get("vamp_kills", 0)), 0, 9)
	score = int(data.get("score", 0))
	raw_score = int(data.get("raw_score", 0))
	coins = int(data.get("coins", coins))
	kills = int(data.get("kills", 0))
	coins_earned = int(data.get("coins_earned", 0))
	best_combo = int(data.get("best_combo", 0))
	time_alive = float(data.get("time_alive", 0.0))
	bullets.shots_fired = int(data.get("shots_fired", 0))
	bullets.shots_hit = int(data.get("shots_hit", 0))
	turret_level = int(data.get("turret_level", 1))
	purchases = data.get("purchases", {})
	kind_kills = data.get("kind_kills", {})
	base.max_hp = float(data.get("base_max_hp", base.max_hp))
	base.hp = float(data.get("base_hp", base.max_hp))
	base.heal(0.0)
	for i in clampi(int(data.get("wall_tier", 0)), 0, Shop.MAX_WALL_TIER):
		map.raise_wall_tier()
	var wall_hp: Dictionary = data.get("wall_hp", {})
	for piece: Variant in map.pieces:
		if piece.kind == "barrel" or not wall_hp.has(piece.cell):
			continue
		piece.hp = clampf(float(wall_hp[piece.cell]), 0.0, piece.max_hp)
		if piece.hp <= 0.0:
			_hide_resume_structure(piece)
		else:
			piece._update_sprite()
	var turret_hp: Dictionary = data.get("turret_hp", {})
	var entries: Array = data.get("turret_entries", [])
	if not data.has("turret_entries"):
		for saved_cell: Variant in data.get("turret_cells", []):
			entries.append({"cell": saved_cell, "kind": "mg"})
	for entry: Dictionary in entries:
		var cell := int(entry.get("cell", -1))
		if cell < 0 or cell >= map.flags.size():
			continue
		# 重建地图时，补出的桶可能占到存档中的炮塔格。
		var occupant: Variant = map.structures.get(cell)
		if occupant != null and occupant.kind in ["barrel", "wall", "barricade"]:
			_hide_resume_structure(occupant)
		if map.flags[cell] == 0:
			var kind := String(entry.get("kind", "mg"))
			var cost := int(entry.get("cost", 0))
			var t := _add_turret(cell, kind, cost)
			t.hp = minf(float(turret_hp.get(cell, t.max_hp)), t.max_hp)
	map.refresh_wall_faces()
	var player_data: Dictionary = data.get("player", {})
	player_data["hero_id"] = hero_id
	# 旧存档没有保存移速和冲刺冷却，用购买次数恢复。
	if not player_data.has("speed_mult"):
		player.speed_mult += 0.08 * int(purchases.get("boots", 0))
	if not player_data.has("dash_cd_base"):
		player.dash_cd_base *= pow(0.8, int(purchases.get("dash", 0)))
	player.magnet_range *= pow(1.4, int(purchases.get("magnet", 0)))
	if player.has_method("import_run_state"):
		player.call("import_run_state", player_data)
	else:
		_restore_player_fallback(player_data)
	player.position = map.unstick(player.position, player.BOX_R, map.BLOCK_PLAYER)
	_cam_pos = player.position
	camera.position = _cam_pos


func _hide_resume_structure(piece: Node2D) -> void:
	piece.hp = 0.0
	piece.alive = false
	piece.hide()
	map.clear_structure(piece.cell)


func _restore_player_fallback(data: Dictionary) -> void:
	player.max_hp = float(data.get("max_hp", player.max_hp))
	player.hp = float(data.get("hp", player.max_hp))
	player.armor = float(data.get("armor", player.armor))
	player.weapon_slots = int(data.get("weapon_slots", player.weapon_slots))
	player.loadout.assign(data.get("loadout", player.loadout))
	player.weapon_state.merge(data.get("weapon_state", {}), true)
	for id: String in GameData.WEAPON_ORDER:
		player._refresh_stats(id)
	player.weapon_id = String(data.get("weapon_id", player.weapon_id))
	player._set_gun_sprite()
	player.items.merge(data.get("items", {}), true)
	player.used_items = data.get("used_items", {})
	player.selected_item = String(data.get("selected_item", player.selected_item))
	player.dot_mult = float(data.get("dot_mult", player.dot_mult))
	player.sticky_mult = float(data.get("sticky_mult", player.sticky_mult))
	player.status_bonus = float(data.get("status_bonus", player.status_bonus))
	player.blast_boss_mult = float(data.get("blast_boss_mult", player.blast_boss_mult))
	player.reflect_mult = float(data.get("reflect_mult", player.reflect_mult))


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
			if has_perk("auto_repair"):
				_tick_auto_repair(dt)
			_boss_hold_t -= dt
			if _queue.is_empty() and zombies.is_empty() and _boss_hold_t <= 0.0:
				_wave_cleared()
		State.CLEARED:
			if _state_t <= 0.0:
				_open_wave_reward()
		State.PLACING:
			if Mobile.is_touch():
				if Mobile.place_cancel:
					Mobile.place_cancel = false
					cancel_turret_placement()
				elif Mobile.place_confirm:
					Mobile.place_confirm = false
					try_place_turret(map.cell_of(Mobile.place_world_pos))
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
		elif Mobile.is_touch():
			return
		elif event.is_action_pressed("fire"):
			try_place_turret(map.cell_of(get_global_mouse_position() + Vector2(0, 4)))
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# 切走窗口或把应用送到后台时自动暂停，并释放所有触点。
	if not is_node_ready():
		return
	if what == NOTIFICATION_PAUSED:
		touch_ui.hide()
		return
	if what not in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		return
	touch_ui.reset_controls()
	if not Harness.automated() and (state == State.COMBAT or state == State.COUNTDOWN or (Mobile.is_touch() and player_can_walk())):
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
	var wave_name: String
	var sub := ""
	if boss_rush:
		_queue = GameData.build_boss_rush_queue(wave, _rng)
		var boss_kind := _queue[0]
		if GameData.BOSSES.has(boss_kind):
			wave_name = GameData.boss_rush_wave_name(wave)
		else:
			# 连战表里的 mother 沿用无尽别名，生成时使用瘟疫母体的实际种类。
			boss_kind = String(GameData.ENDLESS_BOSS_SPAWN[boss_kind])
			_queue[0] = boss_kind
			wave_name = "连战 · %s" % GameData.BOSSES[boss_kind]["title"]
	elif wave > GameData.MAX_WAVE:
		_queue = _build_endless_queue(wave)
		wave_name = "无尽尸潮 #%d" % (wave - GameData.MAX_WAVE)
	else:
		_queue = GameData.build_spawn_queue(wave)
		wave_name = GameData.wave_name(wave)
		sub = GameData.wave_hint(wave)
	_group_left = 0
	pickups.magnet_all = false
	if wave > 1:
		var dropped: int = map.alive_barrels()
		if dropped < 10:
			map.respawn_barrels(_rng, 2)
	events.on_countdown(wave)
	_tween_tint(_combat_tint())
	if sub == "":
		sub = "共 %d 只僵尸，准备迎战" % _queue.size()
	hud.announce("第 %d 波：%s" % [wave, wave_name], sub, COUNTDOWN_TIME)
	Sfx.play_music("menu")


func _build_endless_queue(next_wave: int) -> Array[String]:
	if GameData.has_method("build_endless_queue"):
		return GameData.call("build_endless_queue", next_wave, _rng)
	var extra := next_wave - GameData.MAX_WAVE
	var kinds: Array[String] = ["runner", "spitter", "exploder", "tank", "shielder", "splitter", "stalker", "screamer", "summoner", "balloon"]
	var queue: Array[String] = []
	var count := roundi(mini(52 + extra * 5, 160) * float(_map_spec["count_scale"]))
	for i in count:
		queue.append(kinds[_rng.randi_range(0, kinds.size() - 1)])
	if next_wave % 2 == 0:
		var bosses: Array = GameData.BOSSES.keys()
		queue.insert(queue.size() / 2, String(bosses[(extra / 2) % bosses.size()]))
	return queue


func _begin_combat() -> void:
	state = State.COMBAT
	_spawn_t = 0.0
	Sfx.play("siren", -4.0, 0.0)
	events.on_combat()
	if boss_rush:
		_play_boss_music()
		return
	Sfx.play_music("combat")
	for kind: String in GameData.BOSSES.keys():
		if _queue.has(kind):
			if wave >= GameData.MAX_WAVE:
				_play_boss_music()
			hud.announce("Boss 战：%s" % GameData.BOSSES[kind]["title"], "击退前锋后它就会现身", 2.6)
			Sfx.play("boss_roar", -6.0)
			break


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
	if wave > GameData.MAX_WAVE:
		burst = mini(burst, MAX_ALIVE - zombies.size())
	for i in burst:
		if _queue.is_empty():
			break
		var kind: String = _queue.pop_front() if boss_rush else _queue.pop_back()
		_spawn_zombie(kind)
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
	if wave > GameData.MAX_WAVE:
		var extra := wave - GameData.MAX_WAVE
		var hp_mult := 1.0 + 0.14 * extra
		var speed_mult := minf(1.35, 1.0 + 0.025 * extra)
		if GameData.has_method("endless_hp_mult"):
			hp_mult = float(GameData.call("endless_hp_mult", wave))
		if GameData.has_method("endless_speed_mult"):
			speed_mult = float(GameData.call("endless_speed_mult", wave))
		z.max_hp *= hp_mult
		z.hp *= hp_mult
		z._speed *= speed_mult
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
	_play_boss_music()
	add_shake(0.4)


func _play_boss_music() -> void:
	if boss_rush:
		Sfx.play_music("final_boss" if wave == GameData.boss_rush_wave_count() else "boss")
		return
	# 连杀音效和扩充曲目由同一版音频脚本提供。
	Sfx.play_music("final_boss" if wave >= GameData.MAX_WAVE and Sfx.has_method("play_kill") else "boss")


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
	if not boss_rush and boss_list.is_empty():
		Sfx.play_music("combat")
	if not endless and bool(spec.get("final", false)):
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
	if boss_rush or wave > GameData.MAX_WAVE or GameData.wave_special(wave) != "acid_rain" or _queue.is_empty() and zombies.is_empty():
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


func _tick_auto_repair(dt: float) -> void:
	_auto_repair_t += dt
	if _auto_repair_t < AUTO_REPAIR_INTERVAL:
		return
	_auto_repair_t -= AUTO_REPAIR_INTERVAL
	if base.alive and base.hp < base.max_hp:
		base.heal(10.0)
		fx.ring(base.position + Vector2(0, -24), 14.0, 0.35, REPAIR_COLOR)
	var wall := _most_damaged(map.pieces)
	if wall != null:
		wall.repair(35.0)
		fx.ring(wall.position + Vector2(0, -8), 10.0, 0.35, REPAIR_COLOR)
	var turret := _most_damaged(turrets)
	if turret != null:
		turret.hp = minf(turret.max_hp, turret.hp + 25.0)
		fx.ring(turret.position + Vector2(0, -8), 10.0, 0.35, REPAIR_COLOR)


func _most_damaged(structures: Array) -> Node2D:
	var target: Node2D = null
	var lowest_ratio := 1.0
	for structure: Variant in structures:
		if not structure.alive or structure.kind == "barrel":
			continue
		var ratio: float = structure.hp / structure.max_hp
		if ratio < lowest_ratio:
			lowest_ratio = ratio
			target = structure
	return target


func _wave_cleared() -> void:
	events.on_wave_cleared()
	bullets.clear_hazards()
	hazards.clear()
	ordnance.clear_field()
	pickups.magnet_all = true
	var bonus := 160 + wave * 45 if boss_rush else GameData.wave_bonus(wave)
	coins += bonus
	coins_earned += bonus
	score += 100 * wave + roundi(base.hp / base.max_hp * 100.0) * wave
	Sfx.play("wave_clear")
	Sfx.play_music("menu")
	_tween_tint(_map_tint)
	if boss_rush and wave == GameData.boss_rush_wave_count():
		victory = true
		pickups.collect_all()
		Save.record_boss_rush(time_alive)
		_finish_game("八大 Boss 全部击破！")
		return
	if not boss_rush and wave >= GameData.MAX_WAVE and not endless:
		victory = true
		pickups.collect_all()
		hud.announce("守住了！救援直升机抵达", "你撑过了全部 %d 波" % GameData.MAX_WAVE, CLEARED_TIME)
		_finish_game("基地守住了，幸存者全部撤离。")
		return
	if endless:
		Save.record_endless(wave)
	state = State.CLEARED
	_state_t = CLEARED_TIME
	hud.announce("第 %d 波 肃清" % wave, "奖励金币 +%d" % bonus, CLEARED_TIME)


func _open_wave_reward() -> void:
	var has_reward := boss_rush or (wave % 3 == 0 if endless else GameData.boss_wave(wave))
	if not Harness.automated() and has_reward and perks.size() < GameData.PERK_ORDER.size():
		_perk_choices = GameData.roll_perks(perks, _rng, 3)
		if not _perk_choices.is_empty():
			_open_perk_picker()
			return
	_open_shop()


func _open_perk_picker() -> void:
	state = State.SHOP
	_perk_pending = true
	pickups.collect_all()
	_save_resume_state()
	perk_ui.open(_perk_choices)
	Sfx.play_music("shop")


func on_perk_picked(id: String) -> void:
	if not _perk_pending or not _perk_choices.has(id):
		return
	_perk_pending = false
	_perk_choices.clear()
	add_perk(id)
	_open_shop()


func _open_shop() -> void:
	state = State.SHOP
	# 打扫战场：把没捡到的东西都塞给玩家
	if not Harness.automated():
		pickups.collect_all()
		_save_resume_state()
	shop_ui.open()
	if not Sfx.has_method("play_kill"):
		Sfx.play_music("menu")
	Sfx.play_music("shop")
	Harness.on_shop_open(self)


func continue_endless() -> void:
	if boss_rush or not _endless_recorded_victory or not victory or endless or state != State.OVER:
		return
	endless = true
	victory = false
	# 胜利结算已经乘过倍率，继续时回到原分，避免无尽结算时乘两次。
	score = raw_score
	_over_t = -1.0
	over_ui.hide()
	Engine.time_scale = 1.0
	get_tree().paused = false
	player.heal(player.max_hp * 0.35)
	base.heal(base.max_hp * 0.25)
	_open_shop()


func start_next_wave() -> void:
	if _perk_pending:
		return
	shop_ui.close()
	player.reload_t = 0.0
	_begin_countdown(wave + 1)


func _combat_tint() -> Color:
	return _wave_tint() * _map_tint * events.tint_color()


func _wave_tint() -> Color:
	if boss_rush:
		return Color(0.82, 0.58, 0.58) if wave == GameData.boss_rush_wave_count() else Color(0.82, 0.68, 0.68)
	if wave >= GameData.MAX_WAVE:
		return Color(0.82, 0.58, 0.58)
	if GameData.wave_special(wave) == "blackout":
		return Color(0.42, 0.45, 0.68)
	if GameData.wave_special(wave) == "acid_rain":
		return Color(0.78, 0.92, 0.66)
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
	if Sfx.has_method("play_kill"):
		Sfx.call("play_kill", combo)
	score += roundi(int(stat["score"]) * combo_multiplier())
	if player.alive:
		if has_perk("vamp_armor"):
			_vamp_kills += 1
			if _vamp_kills == 10:
				_vamp_kills = 0
				player.armor = minf(GameData.ARMOR_MAX, player.armor + 5.0)
		if has_perk("dash_reset"):
			player.dash_cd = maxf(player.dash_cd - 0.28, 0.0)
	var perk_coin_mult := 1.3 if combo >= 10 and has_perk("gold_magnet") else 1.0
	if not drops:
		pickups.drop(z.position, "coin", roundi(int(stat["coins"]) * perk_coin_mult))
		return
	var total: int = ceili(float(stat["coins"]) * events.coin_mult * GameData.danger_coin_mult(danger))
	# Boss 叫来的精英只给一半钱，否则站着刷怪比打 Boss 还赚
	if z.master != null:
		total = (total + 1) / 2
	total = roundi(total * perk_coin_mult)
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


func has_perk(id: String) -> bool:
	return perks.has(id)


func add_perk(id: String) -> void:
	if not GameData.PERKS.has(id) or has_perk(id):
		return
	perks.append(id)
	var spec: Dictionary = GameData.PERKS[id]
	hud.announce(String(spec["name"]), String(spec["desc"]), 2.0)
	fx.text(player.position + Vector2(0, -20), String(spec["name"]), Color(String(spec["color"])))


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
	if state == State.PLACING:
		Mobile.reset_placement(Vector2.ZERO, false)
	state = State.OVER
	end_reason = reason
	_over_t = 1.6
	shop_ui.close()
	perk_ui.hide()
	# 最后的慢镜头
	Engine.time_scale = 0.35 if not victory else 1.0
	_stop_until_ms = 0
	Sfx.play_music("")
	Sfx.play("victory" if victory else "game_over")
	# 危险和契约的倍率在结算时一次乘上；通关解锁下一级危险
	raw_score = score
	score = floori(score * score_mult + 0.001)
	if not boss_rush:
		if victory:
			Save.unlock_danger(danger + 1)
			_endless_recorded_victory = true
		if endless:
			Save.record_endless(wave)
		result_rank = Save.submit(score, wave, kills, victory, danger, contracts, score_mult)
	if not Harness.automated():
		Save.clear_resume_run()
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
	var self_damage_mult := 0.6 if friendly else 1.0
	# 目前只有玩家的手雷和榴弹同时标记为友方且保护基地。
	if friendly and spare_base:
		if hero_id == "demo":
			radius *= 1.2
			self_damage_mult *= 0.5
		if has_perk("blast_suit"):
			damage *= 1.15
			self_damage_mult = 0.0
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
	if player != null and player.alive and self_damage_mult > 0.0:
		var pd: float = pos.distance_to(player.position + Vector2(0, -6))
		if pd < radius:
			var falloff := 1.0 - clampf(pd / radius, 0.0, 0.7)
			player.take_damage(damage * falloff * self_damage_mult, pos)
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
	if not Shop.buy(self, id):
		return false
	_save_resume_state()
	return true


func after_repair() -> void:
	for t: Variant in turrets:
		t.repair_full()
	player.position = map.unstick(player.position, player.BOX_R, map.BLOCK_PLAYER)


func turret_max_count() -> int:
	return Shop.MAX_TURRETS + (2 if hero_id == "engineer" else 0)


func turret_cost_for(kind := "mg") -> int:
	var spec: Dictionary = GameData.TURRET_TYPES.get(kind, GameData.TURRET_TYPES["mg"])
	var discount := 0.75 if hero_id == "engineer" else 1.0
	return roundi(Shop.turret_cost(self) * float(spec["cost_mult"]) * discount)


func begin_turret_placement(kind := "") -> void:
	# 无参数时也接收商店已经写入的选型。完成或取消后回到机枪炮塔。
	var selected := placing_turret_kind if kind.is_empty() else kind
	placing_turret_kind = selected if GameData.TURRET_TYPES.has(selected) else "mg"
	state = State.PLACING
	Mobile.reset_placement(player.position + player.aim * 32.0, true)
	shop_ui.close()


func cancel_turret_placement() -> void:
	state = State.SHOP
	placing_turret_kind = "mg"
	Mobile.reset_placement(Vector2.ZERO, false)
	shop_ui.open()


func try_place_turret(cell: int) -> bool:
	var cost := turret_cost_for(placing_turret_kind)
	if (has_contract("no_turret") or coins < cost or turrets.size() >= turret_max_count()
			or cell < 0 or cell >= map.flags.size() or not map.can_place_turret(cell)):
		Sfx.play("deny")
		return false
	var t := _add_turret(cell, placing_turret_kind, cost)
	spend_coins(cost)
	Sfx.play("buy")
	fx.dust(t.position, 8)
	if state == State.PLACING:
		cancel_turret_placement()
	_save_resume_state()
	return true


func last_turret_refund() -> int:
	if turrets.is_empty():
		return 0
	var cost := int(turrets.back().get_meta("purchase_cost"))
	return floori(cost * 0.6)


func sell_last_turret() -> bool:
	if turrets.is_empty():
		return false
	var refund := last_turret_refund()
	var t: Node2D = turrets.pop_back()
	map.clear_structure(t.cell)
	t.alive = false
	t.set_physics_process(false)
	t.queue_free()
	coins += refund
	Sfx.play("buy")
	_save_resume_state()
	return true


func _add_turret(cell: int, kind := "mg", cost := 0) -> Node2D:
	kind = kind if GameData.TURRET_TYPES.has(kind) else "mg"
	var t: Node2D = TurretScene.instantiate()
	if "turret_type" in t:
		t.turret_type = kind
	t.set_meta("turret_kind", kind)
	t.set_meta("purchase_cost", cost if cost > 0 else turret_cost_for(kind))
	entities.add_child(t)
	t.setup(self, map, cell)
	turrets.append(t)
	return t


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
	if player.alive and player_can_walk() and Harness.bot == null:
		var look: Vector2
		if Mobile.is_touch():
			if Mobile.aiming or Mobile.firing:
				look = player.aim * 44.0
			elif Mobile.move_vec.length_squared() > 0.01:
				look = Mobile.move_vec * 24.0
			else:
				look = Vector2.ZERO
		else:
			look = (get_global_mouse_position() - player.position).limit_length(float(_map_spec["look_limit"]))
		target += look * float(_map_spec["look_gain"])
	_cam_pos = _cam_pos.lerp(target, clampf(dt * 7.0, 0.0, 1.0))
	var vp_half := get_viewport_rect().size * 0.5
	_cam_pos.x = map.PIXEL_W * 0.5 if map.PIXEL_W <= vp_half.x * 2.0 else clampf(_cam_pos.x, vp_half.x, map.PIXEL_W - vp_half.x)
	_cam_pos.y = map.PIXEL_H * 0.5 if map.PIXEL_H <= vp_half.y * 2.0 else clampf(_cam_pos.y, vp_half.y, map.PIXEL_H - vp_half.y)
	_trauma = maxf(_trauma - dt * 2.2, 0.0)
	_shake_time += dt
	_kick = _kick.lerp(Vector2.ZERO, clampf(dt * 16.0, 0.0, 1.0))
	var strength := _trauma * _trauma * 9.0
	var shake := Vector2(sin(_shake_time * 61.0 + 1.3), cos(_shake_time * 53.0)) * strength
	camera.position = _cam_pos.round()
	camera.offset = (shake + _kick).round()


func _update_mouse_mode() -> void:
	var want := Input.MOUSE_MODE_VISIBLE
	if not Mobile.is_touch() and not get_tree().paused and player_can_act():
		want = Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != want:
		Input.mouse_mode = want
