extends Node2D
## 玩家：移动、冲刺、瞄准射击、换弹、切枪、道具。输入可以来自键鼠或测试机器人。

const WeaponMods := preload("res://scripts/game/weapon_mods.gd")
const SPEED := 96.0
const ACCEL := 16.0
const DASH_SPEED := 300.0
const DASH_TIME := 0.15
const BOX_R := 5.0
const HAND_H := 7.0
const AIM_ASSIST_RANGE := 220.0
const AUTO_LOCK_RANGE := 260.0
const AIM_ASSIST_ANGLE := deg_to_rad(24.0)
const ELEMENTAL_STATUS_BONUS := 0.6
const HUNTER_SPEED_MULT := 1.15
const HUNTER_DASH_MULT := 0.6
## 进化武器的名字和 HUD 标记用这个颜色。
const EVO_COLOR := Color("#80f0ff")

var game: Node
var map: Node2D
var bot: Variant = null

var hero_id := "captain"
var hp := 100.0
var max_hp := 100.0
var alive := true
var speed_mult := 1.0
var dash_cd_base := 1.3
var magnet_range := 42.0:
	get:
		return magnet_range * 2.0 if _has_perk("gold_magnet") else magnet_range
	set(value):
		# 商店在当前拾取范围上乘倍率，天赋倍率不计入基础值。
		magnet_range = value * 0.5 if _has_perk("gold_magnet") else value

var weapon_id := "pistol"
## 每把枪的等级和弹药；level 为 0 表示还没解锁。
var weapon_state := {}
## 随身枪袋：只有装在里面的枪能切出来用、能补弹药。顺序同 WEAPON_ORDER，手枪永远在里面。
var loadout: Array[String] = []
var weapon_slots := GameData.BASE_WEAPON_SLOTS
## 本局每种道具用掉了几次，进化条件要看。
var used_items := {}
var stats := {}
var cooldown := 0.0
var reload_t := 0.0
var reload_total := 1.0

var velocity := Vector2.ZERO
var aim := Vector2.RIGHT
var aim_point := Vector2.ZERO
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.RIGHT
var invuln := 0.0
## 持续伤害系数，母体血清减半。
var dot_mult := 1.0
# Boss 战利品的伤害、状态和射速倍率。
var sticky_mult := 1.0
var status_bonus := 0.0
var blast_boss_mult := 1.0
var reflect_mult := 1.0
var magma_fire_mult := 1.0
var frost_dur_mult := 1.0
var volt_rate_mult := 1.0
var mech_reload_mult := 1.0
var recoil_px := 0.0
var fired_kick := 0.0

var armor := 0.0
var items := {}
var selected_item := "frag"
var buff_speed_t := 0.0
var buff_damage_t := 0.0
var buff_ammo_t := 0.0

var _hero_tint := Color.WHITE
var _knock := Vector2.ZERO
var _flash_t := 0.0
var _dir := 0
var _walk := 0.0
var _ghost_t := 0.0
var _overdrive_ghost_t := 0.0
var _no_ammo_note := 0.0
var _body_key := -1
# 单次按键用事件锁存，命中停顿拉慢物理帧时也不会丢
var _latch_dash := false
var _latch_reload := false
var _latch_overdrive := false
var _latch_weapon := -1
var _latch_item := ""
var _latch_item_next := false
var _buff_tint := false
var _aim_assist_offset := 0.0
var _touch_fire_hold_t := 0.0
var _minigun_spin := 0.0
var _using_item := false
var touch_lock_target: Node2D = null

@onready var body: Sprite2D = $Body
@onready var gun: Sprite2D = $Gun
@onready var shadow: Sprite2D = $Shadow


func setup(g: Node, m: Node2D) -> void:
	game = g
	map = m
	hero_id = String(g.get("hero_id")) if "hero_id" in g else ("captain" if Harness.automated() else Save.hero_id)
	if not GameData.HEROES.has(hero_id):
		hero_id = "captain"
	shadow.texture = Art.shadow_small
	shadow.position = Vector2(0, -1)
	var size := Art.char_size("player")
	body.offset = Vector2(-size.x / 2, -size.y + 1)
	for id: String in GameData.WEAPON_ORDER:
		var spec: Dictionary = GameData.WEAPONS[id]
		var start_level := 1 if int(spec["unlock_cost"]) == 0 else 0
		# 禁冲锋枪契约：开局不给
		if id == "smg" and g.has_contract("no_smg"):
			start_level = 0
		weapon_state[id] = {"level": start_level, "mag": 0, "reserve": spec["start_reserve"], "mods": WeaponMods.empty_loadout()}
		_refresh_stats(id)
		weapon_state[id]["mag"] = int(stats[id]["mag"])
		if start_level > 0:
			loadout.append(id)
	for id: String in GameData.ITEM_ORDER:
		items[id] = int(GameData.ITEMS[id]["start"])
	if hero_id != "captain":
		_apply_hero_loadout()
	if g.has_contract("glass"):
		max_hp *= GameData.GLASS_HP
		hp = max_hp
	_set_gun_sprite()


func _apply_hero_loadout() -> void:
	var spec: Dictionary = GameData.HEROES[hero_id]
	max_hp = float(spec["hp"])
	hp = max_hp
	_hero_tint = Color(String(spec["tint"]))
	_update_body_tint()
	match hero_id:
		"demo":
			weapon_id = "grenade"
			items["frag"] += 2
		"elemental":
			weapon_id = "cryo"
			items["sticky"] += 1
			status_bonus += ELEMENTAL_STATUS_BONUS
		"hunter":
			weapon_id = "boomerang"
			speed_mult *= HUNTER_SPEED_MULT
			dash_cd_base *= HUNTER_DASH_MULT
	if weapon_id != "pistol":
		upgrade_weapon(weapon_id)


func _has_perk(id: String) -> bool:
	return game != null and game.has_method("has_perk") and game.has_perk(id)


func get_weapon_mods(id: String) -> Dictionary:
	if not weapon_state.has(id):
		return WeaponMods.empty_loadout()
	return WeaponMods.sanitize_mods(weapon_state[id].get("mods"))


func equip_weapon_mod(id: String, slot: String, mod_id: String) -> bool:
	if not weapon_state.has(id) or not owns_weapon(id):
		return false
	if not WeaponMods.SLOT_ORDER.has(slot) or not WeaponMods.MODS.has(mod_id):
		return false
	if String(WeaponMods.MODS[mod_id]["slot"]) != slot:
		return false
	var mods := get_weapon_mods(id)
	var old_mag := int(stats[id]["mag"])
	mods[slot] = mod_id
	weapon_state[id]["mods"] = mods
	_refresh_stats(id)
	var new_mag := int(stats[id]["mag"])
	if new_mag > old_mag:
		weapon_state[id]["mag"] = mini(int(weapon_state[id]["mag"]) + (new_mag - old_mag), new_mag)
	else:
		weapon_state[id]["mag"] = mini(int(weapon_state[id]["mag"]), new_mag)
	queue_redraw()
	return true


func remove_weapon_mod(id: String, slot: String) -> bool:
	if not weapon_state.has(id) or not WeaponMods.SLOT_ORDER.has(slot):
		return false
	var mods := get_weapon_mods(id)
	if String(mods.get(slot, "")) == "":
		return false
	mods[slot] = ""
	weapon_state[id]["mods"] = mods
	_refresh_stats(id)
	weapon_state[id]["mag"] = mini(int(weapon_state[id]["mag"]), int(stats[id]["mag"]))
	queue_redraw()
	return true


func _refresh_stats(id: String) -> void:
	var base := GameData.weapon_stats(id, maxi(int(weapon_state[id]["level"]), 1))
	stats[id] = WeaponMods.apply_to_stats(base, get_weapon_mods(id))


func export_run_state() -> Dictionary:
	return {
		"hero_id": hero_id, "speed_mult": speed_mult, "dash_cd_base": dash_cd_base,
		"hp": hp, "max_hp": max_hp, "armor": armor,
		"weapon_id": weapon_id, "weapon_slots": weapon_slots, "loadout": loadout.duplicate(),
		"weapon_state": weapon_state.duplicate(true), "items": items.duplicate(true),
		"used_items": used_items.duplicate(true), "selected_item": selected_item,
		"dot_mult": dot_mult, "sticky_mult": sticky_mult, "status_bonus": status_bonus,
		"blast_boss_mult": blast_boss_mult, "reflect_mult": reflect_mult,
		"magma_fire_mult": magma_fire_mult, "frost_dur_mult": frost_dur_mult,
		"volt_rate_mult": volt_rate_mult, "mech_reload_mult": mech_reload_mult,
	}


func import_run_state(d: Dictionary) -> void:
	var was_hunter := hero_id == "hunter"
	var saved_hero: Variant = d.get("hero_id", "captain")
	hero_id = saved_hero if saved_hero is String and GameData.HEROES.has(saved_hero) else "captain"
	var is_hunter := hero_id == "hunter"
	# 旧存档靠购买次数恢复属性，补上角色差值后再读取新存档中的完整数值。
	if was_hunter != is_hunter:
		speed_mult += (HUNTER_SPEED_MULT - 1.0) * (1.0 if is_hunter else -1.0)
		dash_cd_base *= HUNTER_DASH_MULT if is_hunter else 1.0 / HUNTER_DASH_MULT
	speed_mult = _saved_number(d, "speed_mult", speed_mult)
	dash_cd_base = _saved_number(d, "dash_cd_base", dash_cd_base)
	_hero_tint = Color(String(GameData.HEROES[hero_id]["tint"]))
	_update_body_tint()
	max_hp = maxf(_saved_number(d, "max_hp", max_hp), 1.0)
	hp = clampf(_saved_number(d, "hp", hp), 0.0, max_hp)
	armor = clampf(_saved_number(d, "armor", armor), 0.0, GameData.ARMOR_MAX)
	weapon_slots = clampi(int(_saved_number(d, "weapon_slots", weapon_slots)), GameData.BASE_WEAPON_SLOTS, GameData.MAX_WEAPON_SLOTS)

	var saved_weapons: Variant = d.get("weapon_state")
	for id: String in GameData.WEAPON_ORDER:
		if saved_weapons is Dictionary and saved_weapons.get(id) is Dictionary:
			var st: Dictionary = weapon_state[id]
			var saved: Dictionary = saved_weapons[id].duplicate(true)
			saved["level"] = clampi(int(_saved_number(saved, "level", st["level"])), 1 if id == "pistol" else 0, GameData.MAX_WEAPON_LEVEL)
			saved["mag"] = maxi(int(_saved_number(saved, "mag", st["mag"])), 0)
			saved["reserve"] = maxi(int(_saved_number(saved, "reserve", st["reserve"])), -1)
			var evo: Variant = saved.get("evo", "")
			if not (evo is String and GameData.EVOLUTIONS.get(evo, {}).get("base") == id):
				saved.erase("evo")
			saved["mods"] = WeaponMods.sanitize_mods(saved.get("mods"))
			weapon_state[id] = saved
		_refresh_stats(id)

	var saved_loadout: Variant = d.get("loadout")
	if not saved_loadout is Array:
		saved_loadout = loadout.duplicate()
	loadout.assign(["pistol"])
	for id: Variant in saved_loadout:
		if id is String and weapon_state.has(id) and owns_weapon(id) and not carries(id) and not loadout_full():
			loadout.append(id)
	var saved_weapon: Variant = d.get("weapon_id", weapon_id)
	weapon_id = saved_weapon if saved_weapon is String and carries(saved_weapon) else "pistol"

	var saved_items: Variant = d.get("items")
	if saved_items is Dictionary:
		for id: String in GameData.ITEM_ORDER:
			items[id] = clampi(int(_saved_number(saved_items, id, items[id])), 0, int(GameData.ITEMS[id]["max"]))
	var saved_used_items: Variant = d.get("used_items")
	if saved_used_items is Dictionary:
		used_items = saved_used_items.duplicate(true)
	var saved_item: Variant = d.get("selected_item")
	if saved_item is String and GameData.ITEMS.has(saved_item):
		selected_item = saved_item
	dot_mult = _saved_number(d, "dot_mult", dot_mult)
	sticky_mult = _saved_number(d, "sticky_mult", sticky_mult)
	status_bonus = _saved_number(d, "status_bonus", status_bonus)
	blast_boss_mult = _saved_number(d, "blast_boss_mult", blast_boss_mult)
	reflect_mult = _saved_number(d, "reflect_mult", reflect_mult)
	magma_fire_mult = _saved_number(d, "magma_fire_mult", 1.0)
	frost_dur_mult = _saved_number(d, "frost_dur_mult", 1.0)
	volt_rate_mult = maxf(_saved_number(d, "volt_rate_mult", 1.0), 1.0)
	mech_reload_mult = _saved_number(d, "mech_reload_mult", 1.0)

	alive = hp > 0.0
	visible = alive
	reload_t = 0.0
	_set_gun_sprite()
	_animate(0.0, Vector2.ZERO)
	queue_redraw()


func _saved_number(d: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = d.get(key)
	return float(value) if (value is int or value is float) and is_finite(float(value)) else fallback


func owns_weapon(id: String) -> bool:
	return int(weapon_state[id]["level"]) > 0


## 随身带着的枪（HUD、切枪、补弹都只看这些）。
func owned_weapons() -> Array[String]:
	var out: Array[String] = []
	for id: String in loadout:
		if owns_weapon(id):
			out.append(id)
	return out


func carries(id: String) -> bool:
	return loadout.has(id)


func loadout_full() -> bool:
	return loadout.size() >= weapon_slots


## 把已解锁的枪装进枪袋。枪袋满了返回 false。
func equip(id: String) -> bool:
	if not owns_weapon(id) or carries(id) or loadout_full():
		return false
	loadout.append(id)
	loadout.sort_custom(func(a, b): return GameData.WEAPON_ORDER.find(a) < GameData.WEAPON_ORDER.find(b))
	return true


func can_unequip(id: String) -> bool:
	return carries(id) and id != "pistol" and loadout.size() > 1


## 卸下的枪保留等级和弹药，只是切不出来。手里正拿着就换回手枪。
func unequip(id: String) -> bool:
	if not can_unequip(id):
		return false
	loadout.erase(id)
	if weapon_id == id:
		weapon_id = "pistol"
		reload_t = 0.0
		_set_gun_sprite()
		queue_redraw()
	return true


## 这把枪进化成了什么，没进化返回空串。
func evolution(id: String) -> String:
	return String(weapon_state[id].get("evo", ""))


func weapon_name(id: String) -> String:
	var evo := evolution(id)
	return String(GameData.EVOLUTIONS[evo]["name"]) if evo != "" else String(GameData.WEAPONS[id]["name"])


## 能不能进化：满级、还没进化、need 满足。consume 是要扣的道具数，reason 是不满足时给商店看的原因。
func evolve_check(id: String) -> Dictionary:
	var evo := GameData.evolution_of(id)
	var out := {"evo": evo, "ok": false, "consume": 0, "reason": ""}
	if evo == "" or evolution(id) != "":
		return out
	if int(weapon_state[id]["level"]) < GameData.MAX_WEAPON_LEVEL:
		out["reason"] = "满级后可进化"
		return out
	var need: Dictionary = GameData.EVOLUTIONS[evo]["need"]
	var item := String(need["item"])
	var consume := int(need["consume"])
	var kills: Dictionary = need.get("kills", {})
	var have_kills: int = game.kills_of(kills["kinds"]) if not kills.is_empty() else 0
	if not kills.is_empty() and have_kills >= int(kills["count"]):
		out["ok"] = true
	elif bool(need.get("used", false)) and int(used_items.get(item, 0)) > 0:
		out["ok"] = true
	elif int(items[item]) >= maxi(consume, 1):
		out["ok"] = true
		out["consume"] = consume
	if out["ok"]:
		return out
	var item_name := String(GameData.ITEMS[item]["name"])
	var reason := "需%s×%d" % [item_name, consume] if consume > 0 else "需带着%s" % item_name
	if bool(need.get("used", false)):
		reason += "或本局用过"
	if not kills.is_empty():
		var names: Array[String] = []
		for k: String in kills["kinds"]:
			names.append(GameData.short_name(k))
		reason += "或击杀%s %d/%d" % ["/".join(names), have_kills, int(kills["count"])]
	out["reason"] = reason
	return out


## 原地进化，扣掉要消耗的道具。金币由商店扣。
func try_evolve(id: String) -> bool:
	var check := evolve_check(id)
	if not bool(check["ok"]):
		return false
	var evo := String(check["evo"])
	var item := String(GameData.EVOLUTIONS[evo]["need"]["item"])
	items[item] = int(items[item]) - int(check["consume"])
	if int(items[selected_item]) <= 0:
		cycle_item()
	weapon_state[id]["evo"] = evo
	return true


func damage_mult() -> float:
	var mult := GameData.DAMAGE_BUFF if buff_damage_t > 0.0 else 1.0
	return mult * 1.25 if game.overdrive_active() else mult


func muzzle_pos() -> Vector2:
	return position + Vector2(0, -HAND_H) + aim * (float(Art.guns[weapon_id]["w"]) - 1.0)


## 抛物线的落点：准星位置，超出射程就落在射程边缘。
func lob_target(max_range: float) -> Vector2:
	var hand := position + Vector2(0, -HAND_H)
	if not _using_item and Mobile.is_touch() and Mobile.aiming:
		return hand + aim * lerpf(minf(56.0, max_range), max_range, Mobile.aim_pull)
	var to := aim_point - hand
	if to.length() < 1.0:
		to = aim
	return hand + to.limit_length(max_range)


func current_stats() -> Dictionary:
	return stats[weapon_id]


func upgrade_weapon(id: String) -> void:
	var st: Dictionary = weapon_state[id]
	var unlocking := int(st["level"]) == 0
	var old_mag := int(stats[id]["mag"])
	st["level"] = int(st["level"]) + 1
	_refresh_stats(id)
	if unlocking:
		equip(id)
	# 升级后顺手填满新增的弹匣容量
	if id == "pistol" or unlocking:
		st["mag"] = int(stats[id]["mag"])
	elif bool(stats[id].get("returns", false)):
		st["mag"] = int(st["mag"]) + int(stats[id]["mag"]) - old_mag


func _set_gun_sprite() -> void:
	var g: Dictionary = Art.guns[weapon_id]
	gun.texture = g["tex"]
	gun.centered = false
	gun.offset = Vector2(-3, -int(g["h"]) / 2)


func _physics_process(dt: float) -> void:
	if not alive:
		return
	if _latch_overdrive or Mobile.latch_overdrive:
		_latch_overdrive = false
		Mobile.latch_overdrive = false
		if game.activate_overdrive():
			reload_t = 0.0
	var control: bool = game.player_can_act()
	var move_input := Vector2.ZERO
	var firing := false
	var want_dash := false
	var want_reload := false
	var weapon_pick := -1
	var item_pick := ""
	var item_has_target := false
	var item_target := Vector2.ZERO
	if bot != null:
		move_input = bot.move
		aim = bot.aim_dir
		aim_point = bot.aim_point
		firing = bot.firing
		want_dash = bot.want_dash
		want_reload = bot.want_reload
		weapon_pick = bot.want_weapon
		bot.want_dash = false
		bot.want_reload = false
		bot.want_weapon = -1
		item_pick = bot.want_item
		bot.want_item = ""
	else:
		move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var touch := Mobile.is_touch()
		var hand := position + Vector2(0, -HAND_H)
		firing = Input.is_action_pressed("fire")
		if Mobile.gamepad_active:
			touch_lock_target = null
			_aim_assist_offset = 0.0
			_touch_fire_hold_t = 0.0
			if Mobile.gamepad_aim_vec.length_squared() > 0.01:
				aim = Mobile.gamepad_aim_vec
			elif move_input.length_squared() > 0.01:
				_turn_aim_toward(move_input.normalized(), dt * 18.0)
			aim_point = hand + aim * 120.0
		elif touch:
			_touch_fire_hold_t = maxf(_touch_fire_hold_t - dt, 0.0)
			if Mobile.move_vec.length_squared() > 0.0001:
				move_input = Mobile.move_vec
			var auto_fire := Save.auto_fire_on and control and not Mobile.aiming and not Mobile.firing and not firing
			if Mobile.aiming and Mobile.aim_vec.length_squared() > 0.01:
				# 右摇杆拖动：360° 手动精准瞄准（开启自动瞄准时做轻微扇形磁吸）
				aim = Mobile.aim_vec.normalized()
				if Save.auto_aim_on and Mobile.firing:
					aim = _assisted_touch_aim(aim, hand, dt)
				else:
					_aim_assist_offset = 0.0
					touch_lock_target = null
				aim_point = hand + aim * 120.0
				_touch_fire_hold_t = 0.32
			else:
				# 未拖动右摇杆时，按住开火或开启自动开火都可以锁定目标。
				_aim_assist_offset = 0.0
				touch_lock_target = _find_auto_lock_target(hand, auto_fire) if Save.auto_aim_on or auto_fire else null
				if touch_lock_target != null and (Mobile.firing or auto_fire):
					aim_point = touch_lock_target.center()
					var to := aim_point - hand
					if to.length_squared() > (0.0 if auto_fire else 4.0):
						aim = to.normalized()
					_touch_fire_hold_t = 0.32
					firing = true
				else:
					if move_input.length_squared() > 0.01 and (Mobile.firing or _touch_fire_hold_t <= 0.0):
						_turn_aim_toward(move_input.normalized(), dt * 18.0)
					if Mobile.firing:
						_touch_fire_hold_t = 0.32
					aim_point = hand + aim * 120.0
			firing = firing or Mobile.firing
		else:
			touch_lock_target = null
			var mouse := get_global_mouse_position()
			aim_point = mouse
			if mouse.distance_squared_to(hand) > 4.0:
				aim = (mouse - hand).normalized()
		want_dash = _latch_dash
		want_reload = _latch_reload
		weapon_pick = _latch_weapon
		_latch_dash = false
		_latch_reload = false
		_latch_weapon = -1
		item_pick = _latch_item
		_latch_item = ""
		if _latch_item_next:
			_latch_item_next = false
			cycle_item()
		if touch:
			want_dash = want_dash or Mobile.latch_dash
			want_reload = want_reload or Mobile.latch_reload
			var id := Mobile.latch_weapon_id
			if weapon_state.has(id) and owns_weapon(id) and carries(id):
				weapon_pick = GameData.WEAPON_ORDER.find(id)
			elif Mobile.latch_weapon_step != 0:
				weapon_pick = _next_owned(Mobile.latch_weapon_step)
			if GameData.ITEMS.has(Mobile.latch_item_select):
				selected_item = Mobile.latch_item_select
			if Mobile.latch_item_next:
				cycle_item()
			if GameData.ITEMS.has(Mobile.latch_item_use):
				item_pick = Mobile.latch_item_use
				item_has_target = Mobile.latch_item_has_target
				item_target = Mobile.latch_item_target
			Mobile.latch_dash = false
			Mobile.latch_reload = false
			Mobile.latch_weapon_id = ""
			Mobile.latch_weapon_step = 0
			Mobile.latch_item_select = ""
			Mobile.latch_item_use = ""
			Mobile.latch_item_has_target = false
			Mobile.latch_item_next = false

	if not control:
		item_pick = ""
		firing = false
		want_dash = false
		want_reload = false
		weapon_pick = -1
		if not game.player_can_walk():
			move_input = Vector2.ZERO

	_tick_timers(dt)
	if weapon_pick >= 0:
		switch_weapon(GameData.WEAPON_ORDER[weapon_pick])
	if want_reload:
		start_reload()
	if want_dash:
		_try_dash(move_input)
	if item_pick != "":
		var weapon_aim := aim
		var weapon_aim_point := aim_point
		if item_has_target:
			aim_point = item_target
			var to := aim_point - (position + Vector2(0, -HAND_H))
			if to.length_squared() > 16.0:
				aim = to.normalized()
		use_item(item_pick)
		# 同一帧还可能开火，投掷落点只对道具生效。
		aim = weapon_aim
		aim_point = weapon_aim_point
	var can_spin: bool = buff_ammo_t > 0.0 or game.overdrive_active() or int(weapon_state[weapon_id]["mag"]) > 0
	var spinning := firing and evolution(weapon_id) == "pulse_minigun" and reload_t <= 0.0 and dash_t <= 0.0 and can_spin
	_minigun_spin = move_toward(_minigun_spin, 1.0 if spinning else 0.0, dt * (2.0 if spinning else 1.6))
	if firing:
		_try_fire()
	_move(move_input, dt)
	_animate(dt, move_input)


func _turn_aim_toward(target_dir: Vector2, weight: float) -> void:
	var diff := wrapf(target_dir.angle() - aim.angle(), -PI, PI)
	aim = Vector2.from_angle(aim.angle() + diff * clampf(weight, 0.0, 1.0))


func _find_auto_lock_target(hand: Vector2, clear_only := false) -> Node2D:
	var view := get_viewport_rect().grow(12.0)
	var canvas := get_canvas_transform()
	var best_clear: Node2D = null
	var best_clear_score := INF
	var best_any: Node2D = null
	var best_any_score := INF
	# 自动开火按子弹的地面投影检查遮挡。
	var ground_offset := Vector2(0, HAND_H) if clear_only else Vector2.ZERO
	var current_valid: bool = is_instance_valid(touch_lock_target) and not bool(touch_lock_target.get("dead")) and not touch_lock_target.cloaked() and not bool(touch_lock_target.get("burrowed"))
	for z: Variant in game.zombies_near(hand, AUTO_LOCK_RANGE):
		if z.dead or z.cloaked() or z.burrowed or not z.is_visible_in_tree():
			continue
		var target: Vector2 = z.center()
		var dist := hand.distance_to(target)
		if dist > AUTO_LOCK_RANGE or not view.has_point(canvas * target):
			continue
		var score := dist - (22.0 if current_valid and z == touch_lock_target else 0.0)
		if map.line_clear(hand + ground_offset, target + ground_offset, map.BLOCK_BULLET):
			if score < best_clear_score:
				best_clear_score = score
				best_clear = z
		elif not clear_only and score < best_any_score:
			best_any_score = score
			best_any = z
	return best_clear if best_clear != null else best_any


func _assisted_touch_aim(direction: Vector2, hand: Vector2, dt: float) -> Vector2:
	var best_angle := AIM_ASSIST_ANGLE
	var correction := 0.0
	var assisted: Node2D = null
	var view := get_viewport_rect()
	var canvas := get_canvas_transform()
	for z: Variant in game.zombies_near(hand, AIM_ASSIST_RANGE):
		if z.dead or z.cloaked() or z.burrowed or not z.is_visible_in_tree():
			continue
		var target: Vector2 = z.center()
		var delta := target - hand
		if delta.length_squared() > AIM_ASSIST_RANGE * AIM_ASSIST_RANGE or not view.has_point(canvas * target):
			continue
		var angle := direction.angle_to(delta)
		if absf(angle) <= best_angle and map.line_clear(hand, target, map.BLOCK_BULLET):
			best_angle = absf(angle)
			correction = angle * 0.6
			assisted = z
	touch_lock_target = assisted
	_aim_assist_offset = lerpf(_aim_assist_offset, correction, 1.0 - exp(-18.0 * dt))
	return direction.rotated(_aim_assist_offset)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("dash"):
		_latch_dash = true
	elif event.is_action_pressed("reload"):
		_latch_reload = true
	elif event.is_action_pressed("overdrive"):
		_latch_overdrive = true
	elif event.is_action_pressed("weapon_next"):
		_latch_weapon = _next_owned(1)
	elif event.is_action_pressed("weapon_prev"):
		_latch_weapon = _next_owned(-1)
	elif event.is_action_pressed("item_use"):
		_latch_item = selected_item
	elif event.is_action_pressed("item_next"):
		_latch_item_next = true
	elif event.is_action_pressed("item_medkit"):
		_latch_item = "medkit"
	elif event.is_action_pressed("item_frag"):
		_latch_item = "frag"
	elif event.is_action_pressed("item_nuke"):
		_latch_item = "nuke"
	else:
		for i in GameData.WEAPON_ORDER.size():
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				_latch_weapon = i
				break


## 滚轮只在随身的枪之间切换。
func _next_owned(step: int) -> int:
	var carried := owned_weapons()
	var i := carried.find(weapon_id)
	if carried.is_empty():
		return GameData.WEAPON_ORDER.find(weapon_id)
	return GameData.WEAPON_ORDER.find(carried[posmod(i + step, carried.size())])


func _tick_timers(dt: float) -> void:
	cooldown -= dt
	dash_cd -= dt
	invuln -= dt
	_flash_t -= dt
	_no_ammo_note -= dt
	if game.player_can_act():
		buff_speed_t = maxf(buff_speed_t - dt, 0.0)
		buff_damage_t = maxf(buff_damage_t - dt, 0.0)
		buff_ammo_t = maxf(buff_ammo_t - dt, 0.0)
	var tinted := buff_damage_t > 0.0
	if tinted != _buff_tint:
		_update_body_tint()
	recoil_px = move_toward(recoil_px, 0.0, dt * 22.0)
	fired_kick = move_toward(fired_kick, 0.0, dt * 3.5)
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			_finish_reload()
		queue_redraw()


func _update_body_tint() -> void:
	_buff_tint = buff_damage_t > 0.0
	body.modulate = _hero_tint * Color(1.5, 0.85, 0.8) if _buff_tint else _hero_tint


func _move(move_input: Vector2, dt: float) -> void:
	var overdrive: bool = game.overdrive_active() and game.player_can_act()
	if dash_t > 0.0:
		dash_t -= dt
		velocity = dash_dir * DASH_SPEED
		_ghost_t -= dt
		if _ghost_t <= 0.0 and not overdrive:
			_ghost_t = 0.03
			game.fx.ghost(body.texture, position + body.offset, body.flip_h, Color(0.5, 0.85, 1.0, 0.55), 0.2)
		if dash_t <= 0.0:
			velocity *= 0.4
	else:
		var target: Vector2 = move_input.limit_length(1.0) * move_speed()
		velocity = velocity.lerp(target, clampf(ACCEL * game.events.traction_at(position) * dt, 0.0, 1.0))
	_knock = _knock.lerp(Vector2.ZERO, clampf(10.0 * dt, 0.0, 1.0))
	var previous := position
	position = map.move_box(position, (velocity + _knock) * dt, BOX_R, map.BLOCK_PLAYER)
	if overdrive and position.distance_squared_to(previous) > 0.01:
		_overdrive_ghost_t -= dt
		if _overdrive_ghost_t <= 0.0:
			_overdrive_ghost_t += 0.08
			game.fx.ghost(body.texture, previous + body.offset, body.flip_h, Color(game.OVERDRIVE_COLOR, 0.55), 0.2)
	else:
		_overdrive_ghost_t = 0.0


func move_speed() -> float:
	var speed := SPEED * speed_mult * float(game.events.player_speed) * (GameData.SPEED_BUFF if buff_speed_t > 0.0 else 1.0)
	if game.overdrive_active():
		speed *= 1.20
	return speed * 1.12 if _has_perk("overclock") else speed


func _animate(dt: float, _move_input: Vector2) -> void:
	# 身体朝向跟随准星，看起来更像在“边退边打”
	var dir := Art.DIR_DOWN
	if absf(aim.x) > absf(aim.y):
		dir = Art.DIR_SIDE
	elif aim.y < 0.0:
		dir = Art.DIR_UP
	_dir = dir
	body.flip_h = aim.x < 0.0 and dir == Art.DIR_SIDE
	var spd := velocity.length()
	if spd > 8.0:
		# 倒退时反向播放走路帧
		var back: float = -1.0 if velocity.dot(aim) < -5.0 else 1.0
		_walk += dt * spd * 0.14 * back
	else:
		_walk = 0.0
	var f := posmod(int(floorf(_walk)), Art.FRAMES)
	var white := _flash_t > 0.0
	var key := dir * 100 + f * 10 + (1 if white else 0)
	if key != _body_key:
		_body_key = key
		body.texture = Art.frame("player", dir, f, white)
	body.visible = not (invuln > 0.0 and _flash_t <= 0.0 and int(invuln * 24.0) % 2 == 0) or dash_t > 0.0
	# 枪
	gun.rotation = aim.angle()
	gun.flip_v = aim.x < 0.0
	gun.position = Vector2(0, -HAND_H) + aim * (3.0 - recoil_px)
	gun.show_behind_parent = false
	gun.z_index = -1 if dir == Art.DIR_UP else 0
	# 回旋镖扔出去后手里是空的
	gun.visible = not bool(stats[weapon_id].get("returns", false)) or int(weapon_state[weapon_id]["mag"]) > 0
	if stats.has(weapon_id) and bool(stats[weapon_id].get("mod_laser", false)):
		queue_redraw()


func switch_weapon(id: String) -> void:
	if id == weapon_id:
		return
	if not owns_weapon(id) or not carries(id):
		if _no_ammo_note <= 0.0:
			_no_ammo_note = 0.8
			game.fx.text(position + Vector2(0, -22), "%s %s" % [GameData.WEAPONS[id]["name"], "未解锁" if not owns_weapon(id) else "不在枪袋里"], Color("#ff8060"))
			Sfx.play("deny")
		return
	weapon_id = id
	reload_t = 0.0
	cooldown = maxf(cooldown, 0.12)
	if evolution(id) != "":
		game.fx.text(position + Vector2(0, -22), weapon_name(id), EVO_COLOR)
	_set_gun_sprite()
	Sfx.play("reload", -6.0, 0.15)
	queue_redraw()


func mag_size() -> int:
	return int(stats[weapon_id]["mag"])


func start_reload() -> void:
	var st: Dictionary = weapon_state[weapon_id]
	if reload_t > 0.0 or int(st["mag"]) >= mag_size() or buff_ammo_t > 0.0 or game.overdrive_active():
		return
	if bool(stats[weapon_id].get("returns", false)):
		return
	if int(st["reserve"]) == 0:
		if _no_ammo_note <= 0.0:
			_no_ammo_note = 0.8
			game.fx.text(position + Vector2(0, -22), "没有备弹！", Color("#ff8060"))
			Sfx.play("empty")
		return
	reload_total = float(stats[weapon_id]["reload"]) * mech_reload_mult
	if _has_perk("overclock"):
		reload_total *= 0.75
	reload_t = reload_total
	Sfx.play("reload")
	if _has_perk("reload_nova"):
		var damage := 16.0 * damage_mult()
		# 击杀会立即把僵尸从列表移除，按快照遍历。
		for z: Variant in game.zombies.duplicate():
			var offset: Vector2 = z.position - position
			if not z.dead and offset.length_squared() <= 58.0 * 58.0:
				z.take_damage(damage, offset.normalized(), 95.0)
		game.fx.dust(position, 10)
		Sfx.play("slam", -10.0)


func _finish_reload() -> void:
	reload_t = 0.0
	var st: Dictionary = weapon_state[weapon_id]
	var need := mag_size() - int(st["mag"])
	if int(st["reserve"]) < 0:
		st["mag"] = mag_size()
	else:
		var take := mini(need, int(st["reserve"]))
		st["mag"] = int(st["mag"]) + take
		st["reserve"] = int(st["reserve"]) - take
	Sfx.play("reload_done")


func _try_fire() -> void:
	if cooldown > 0.0 or reload_t > 0.0 or dash_t > 0.0:
		return
	var st: Dictionary = weapon_state[weapon_id]
	var s: Dictionary = stats[weapon_id]
	var returns := bool(s.get("returns", false))
	var overdrive: bool = game.overdrive_active()
	# 无限弹药对回旋镖无效：手里没镖就是没镖
	var free_shot := (buff_ammo_t > 0.0 or overdrive) and not returns
	if int(st["mag"]) <= 0 and not free_shot:
		cooldown = 0.18
		if not returns:
			Sfx.play("empty")
			start_reload()
		return
	var damage := float(s["damage"]) * damage_mult()
	if not returns and _has_perk("last_stand") and int(st["mag"]) <= maxi(1, ceili(float(mag_size()) * 0.25)):
		damage *= 1.6
	var crit_chance := float(s.get("mod_crit_chance", 0.0))
	var crit_proc := crit_chance > 0.0 and randf() < crit_chance
	if crit_proc:
		damage *= float(s.get("mod_crit_mult", 1.5))
		game.fx.text(position + Vector2(0, -24), "暴击！", Color("#ffe060"))
	if not free_shot:
		st["mag"] = int(st["mag"]) - 1
	cooldown = float(s["cooldown"])
	if weapon_id == "arc":
		cooldown /= volt_rate_mult
	if overdrive:
		cooldown *= 0.70
	if evolution(weapon_id) == "pulse_minigun":
		cooldown *= lerpf(1.0, 0.68, _minigun_spin)
	var muzzle := muzzle_pos()
	_fire_mode(s, muzzle, damage)
	if bot == null and weapon_id in ["shotgun", "sniper", "grenade"]:
		Mobile.haptic_light()
	if s.has("casing"):
		game.fx.casing(position + Vector2(0, -HAND_H), aim, s["casing"] == "red")
	game.add_shake(float(s["shake"]))
	game.kick_camera(aim * float(s["recoil"]))
	recoil_px = float(s["recoil"])
	fired_kick = minf(fired_kick + 0.35, 1.0)
	velocity -= aim * float(s["recoil"]) * 6.0
	Sfx.play(String(s["sfx"]))
	if int(st["mag"]) <= 0 and not free_shot:
		start_reload()


func _fire_mode(s: Dictionary, muzzle: Vector2, damage: float) -> void:
	if hero_id == "elemental" and weapon_id in ["cryo", "flamer", "arc"]:
		damage *= 1.2
	# 榴弹的熔岩核加成在 game.explode() 落地结算。
	if weapon_id == "flamer":
		damage *= magma_fire_mult
	var mode := String(s.get("mode", "bullet"))
	var flash := String(s.get("flash", ""))
	var evo := evolution(weapon_id)
	if flash != "none" and flash != "flame":
		game.fx.muzzle_flash(muzzle, aim, bool(s.get("big_flash", false)), flash)
	match mode:
		"beam":
			game.ordnance.beam(muzzle, aim, float(s["range"]), damage, float(s["knock"]), int(s["pierce"]), evo == "puncturer")
		"flame":
			if evo == "blue_furnace" and game.ordnance.has_method("flame_blue"):
				game.ordnance.flame_blue(muzzle, aim, float(s["range"]) * 1.15, float(s["cone"]) * 1.1, damage * 1.2)
			else:
				game.ordnance.flame(muzzle, aim, float(s["range"]), float(s["cone"]), damage)
		"lob":
			game.ordnance.lob("thermite" if evo == "thermite" else "grenade", muzzle, lob_target(float(s["range"])), damage, float(s["radius"]))
		"arc":
			game.ordnance.arc(muzzle, aim, float(s["range"]), damage, int(s["chain"]), float(s["jump"]), float(s["knock"]), evo == "storm_rod")
		"boomerang":
			var saw := evo == "saw_rang"
			game.ordnance.boomerang(muzzle, aim, float(s["speed"]), float(s["range"]), damage * (GameData.SAW_MULT if saw else 1.0), float(s["knock"]), saw)
		_:
			var knock := float(s["knock"])
			var life := float(s["life"])
			var pierce := int(s["pierce"])
			if _has_perk("ricochet"):
				pierce += 1
				damage *= 1.12
			if evo == "twin_handgun":
				var offset := aim.orthogonal() * 2.5
				var shot_velocity := aim * float(s["speed"]) * randf_range(0.92, 1.05)
				for side: float in [-1.0, 1.0]:
					game.bullets.fire(muzzle + offset * side, shot_velocity, damage * 1.25, knock, life, pierce + 1, Color("#ffe870"), true)
				return
			var color := Color(String(s["color"]))
			var dragon := evo == "dragon_breath"
			if dragon:
				knock *= 1.25
				color = Color("#ff7830")
			elif evo == "pulse_minigun":
				knock *= 1.4
			var spread := deg_to_rad(float(s["spread"]))
			for i in int(s["pellets"]):
				var d := aim.rotated(randf_range(-spread, spread))
				var bullet_speed := float(s["speed"]) * randf_range(0.92, 1.05)
				var b: Variant = game.bullets.fire(muzzle, d * bullet_speed, damage, knock, life, pierce, color, true)
				b.chill = float(s.get("chill", 0.0))
				b.buckshot = int(s["pellets"]) > 1
				b.mine = evo == "frost_mine"
				if (dragon or bool(s.get("mod_burn", false))) and "burn" in b:
					b.burn = true


## 回旋镖飞回手里。
func catch_boomerang() -> void:
	var st: Dictionary = weapon_state["boomerang"]
	st["mag"] = mini(int(st["mag"]) + 1, int(stats["boomerang"]["mag"]))


# ---------------------------------------------------------------------------
# 道具
# ---------------------------------------------------------------------------

func use_item(id: String) -> bool:
	if int(items.get(id, 0)) <= 0:
		if _no_ammo_note <= 0.0:
			_no_ammo_note = 0.8
			game.fx.text(position + Vector2(0, -22), "没有%s" % GameData.ITEMS[id]["name"] if id != "" else "没有道具", Color("#ff8060"))
			Sfx.play("deny")
		return false
	_using_item = true
	var applied: bool = game.ordnance.use_item(id, self)
	_using_item = false
	if not applied:
		Sfx.play("deny")
		return false
	items[id] = int(items[id]) - 1
	used_items[id] = int(used_items.get(id, 0)) + 1
	if id == selected_item and int(items[id]) <= 0:
		cycle_item()
	return true


## 切到下一种还有存货的道具；全都没有就不动。
func cycle_item() -> void:
	var order := GameData.ITEM_ORDER
	var i := order.find(selected_item)
	for k in order.size():
		i = (i + 1) % order.size()
		if int(items[order[i]]) > 0:
			if order[i] != selected_item:
				selected_item = order[i]
				Sfx.play("ui_click", -6.0)
			return


## 捡到或买到道具。已带满时返回 false。
func add_item(id: String, amount: int) -> bool:
	var cap := int(GameData.ITEMS[id]["max"])
	if int(items[id]) >= cap:
		return false
	items[id] = mini(int(items[id]) + amount, cap)
	if int(items[selected_item]) <= 0:
		selected_item = id
	return true


func refill_all(ammo_drops: int) -> void:
	reload_t = 0.0
	for id: String in owned_weapons():
		var st: Dictionary = weapon_state[id]
		if bool(stats[id].get("returns", false)):
			continue
		st["mag"] = int(stats[id]["mag"])
		if int(st["reserve"]) >= 0:
			st["reserve"] = int(st["reserve"]) + int(GameData.WEAPONS[id].get("ammo_drop", 0)) * ammo_drops


func start_inf_ammo(seconds: float) -> void:
	buff_ammo_t = seconds
	reload_t = 0.0
	queue_redraw()


func _try_dash(move_input: Vector2) -> void:
	if dash_cd > 0.0 or dash_t > 0.0:
		return
	dash_dir = move_input.normalized() if move_input.length() > 0.1 else aim
	dash_t = DASH_TIME
	dash_cd = dash_cd_base
	invuln = maxf(invuln, DASH_TIME + 0.08)
	if _has_perk("dash_arc"):
		game.ordnance.arc(position + Vector2(0, -HAND_H), dash_dir, 96.0, 26.0 * damage_mult(), 3, 58.0, 18.0, false)
	Sfx.play("dash")
	game.fx.dust(position, 6)
	if bot == null and Mobile.is_touch():
		Mobile.haptic_medium()


func take_damage(amount: float, attacker_pos: Variant = null) -> void:
	if not alive or invuln > 0.0 or game.god_mode:
		return
	var soaked := minf(armor, amount)
	armor -= soaked
	hp -= amount - soaked
	invuln = 0.5
	_flash_t = 0.1
	if attacker_pos != null:
		var from: Vector2 = attacker_pos
		_knock += (position - from).normalized() * 150.0
	game.on_player_hurt(amount)
	if bot == null and Mobile.is_touch():
		Mobile.haptic_heavy()
	game.fx.blood_hit(position + Vector2(0, -7), Vector2.UP, 6, Color("#a01c1c"))
	if hp <= 0.0:
		hp = 0.0
		alive = false
		visible = false
		game.fx.gibs("player", position, Vector2.UP)
		game.decals.stamp(Art.blood_splats_dark[randi() % Art.blood_splats_dark.size()], position)
		game.on_player_died()


## 酸液这类持续伤害不触发无敌帧。
func take_dot(amount: float) -> void:
	if not alive or game.god_mode or dash_t > 0.0:
		return
	hp -= amount * dot_mult
	game.hud.flash_dot()
	if hp <= 0.0:
		hp = 0.0
		invuln = 0.0
		take_damage(1.0)


## Boss 战利品：捡到立刻生效。
func apply_trophy(id: String) -> void:
	match id:
		"heart":
			max_hp += GameData.TROPHY_HP
			hp = max_hp
		"serum":
			dot_mult = GameData.TROPHY_DOT
		"crown":
			game.score += GameData.TROPHY_SCORE
		"plating":
			sticky_mult = GameData.TROPHY_STICKY
		"ash":
			status_bonus = GameData.TROPHY_STATUS_TIME + (ELEMENTAL_STATUS_BONUS if hero_id == "elemental" else 0.0)
			status_bonus += frost_dur_mult - 1.0
		"soil":
			blast_boss_mult = GameData.TROPHY_BLAST_BOSS
		"shard":
			reflect_mult = GameData.TROPHY_REFLECT
		"magma_core":
			magma_fire_mult = GameData.TROPHY_MAGMA_FIRE
		"frost_heart":
			if frost_dur_mult == 1.0:
				frost_dur_mult = GameData.TROPHY_FROST_MULT
				status_bonus += frost_dur_mult - 1.0
		"volt_coil":
			volt_rate_mult = GameData.TROPHY_VOLT_RATE
		"mech_chip":
			if mech_reload_mult == 1.0:
				mech_reload_mult = GameData.TROPHY_MECH_RELOAD
				dash_cd_base *= GameData.TROPHY_MECH_DASH


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)


func _draw() -> void:
	if alive and game != null and game.player_can_act() and stats.has(weapon_id) and bool(stats[weapon_id].get("mod_laser", false)):
		var start := Vector2(0, -HAND_H) + aim * (float(Art.guns[weapon_id]["w"]) - 1.0)
		var laser_len := 150.0
		var step := 10.0
		var end_world := position + start
		for k in int(laser_len / step):
			var probe := position + start + aim * (float(k + 1) * step)
			if map.blocks(map.cell_of(probe), map.BLOCK_BULLET):
				break
			end_world = probe
		draw_line(start, end_world - position, Color(1.0, 0.22, 0.22, 0.45), 1.0)
	if reload_t > 0.0:
		var ratio := 1.0 - reload_t / reload_total
		draw_rect(Rect2(-8, -22, 16, 3), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(-7, -21, 14.0 * ratio, 1), Color("#f0d050"))
