extends RefCounted
## 自动化测试机器人：用和玩家相同的输入接口打完整局，验证流程和粗测平衡。

var game: Node
var move := Vector2.ZERO
var aim_dir := Vector2.RIGHT
var aim_point := Vector2.ZERO
var firing := false
var want_dash := false
var want_reload := false
var want_weapon := -1
var want_item := ""

## 1.0 是完美瞄准；越低瞄准误差越大、反应越慢，用来模拟普通玩家。
var skill := 1.0
var _strafe := 1.0
var _strafe_t := 0.0
var _aim_error := 0.0
var _aim_error_t := 0.0
var _dash_wait := 0.0
var _item_wait := 0.0


func _init(g: Node) -> void:
	game = g


func tick(dt: float) -> void:
	var p: Variant = game.player
	if p == null or not p.alive:
		return
	_strafe_t -= dt
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(0.8, 2.0)
		_strafe = -_strafe
	var nearest: Variant = null
	var nearest_d := 1e9
	var threat: Variant = null
	var threat_d := 1e9
	for z: Variant in game.zombies:
		var d: float = p.position.distance_to(z.position)
		if d < nearest_d:
			nearest_d = d
			nearest = z
		# 优先清理正在啃建筑、离基地最近的僵尸
		var base_d: float = game.base.position.distance_to(z.position)
		if base_d < threat_d:
			threat_d = base_d
			threat = z
	var target: Variant = nearest if nearest_d < 120.0 else threat
	var home: Vector2 = game.base.position + Vector2(0, 26)
	if target == null:
		firing = false
		move = (home - p.position).limit_length(1.0) if p.position.distance_to(home) > 20.0 else Vector2.ZERO
		_manage_reload(p)
		return
	var from: Vector2 = p.position + Vector2(0, -p.HAND_H)
	_aim_error_t -= dt
	_dash_wait -= dt
	if _aim_error_t <= 0.0:
		_aim_error_t = randf_range(0.1, 0.3)
		_aim_error = randf_range(-1.0, 1.0) * (1.0 - skill) * 0.55
	aim_dir = from.direction_to(target.center()).rotated(_aim_error)
	aim_point = target.center()
	var target_d: float = p.position.distance_to(target.position)
	firing = target_d < 210.0
	_pick_weapon(p, nearest_d, target)
	_manage_reload(p)
	_use_items(p, dt, target)
	# 走位：离威胁保持距离，否则回防基地附近、朝威胁靠拢
	if nearest_d < 46.0:
		var away: Vector2 = (p.position - nearest.position).normalized()
		move = (away + away.orthogonal() * _strafe * 0.6).normalized()
		if nearest_d < 26.0 and _dash_wait <= 0.0:
			want_dash = true
			_dash_wait = (1.0 - skill) * 5.0
	elif target_d > 170.0 or (game.zombies.size() <= 3 and target_d > 60.0):
		# 残敌主动去追，距离太远子弹也打不到
		move = p.position.direction_to(target.position)
	else:
		move = p.position.direction_to(home) * 0.5 if p.position.distance_to(home) > 90.0 else Vector2.ZERO
		move += aim_dir.orthogonal() * _strafe * 0.5
	# 踩到酸液就走开
	for pool: Variant in game.bullets.pools:
		if p.position.distance_to(pool.pos) < pool.r + 6.0:
			move = (p.position - pool.pos).normalized()
			return
	# 被障碍挡住视线或路线时横向绕开
	if not game.map.line_clear(p.position, target.position, game.map.BLOCK_BULLET | game.map.BLOCK_PLAYER):
		move = (move * 0.3 + aim_dir.orthogonal() * _strafe).normalized()


func _usable(p: Variant, id: String) -> bool:
	if not p.owns_weapon(id):
		return false
	var st: Dictionary = p.weapon_state[id]
	return int(st["mag"]) > 0 or int(st["reserve"]) > 0


## 按局面挑枪：贴脸用火焰和霰弹，大怪用狙和冰冻，人多用电弧和榴弹。
func _pick_weapon(p: Variant, nearest_d: float, target: Variant) -> void:
	var count: int = game.zombies.size()
	var target_d: float = p.position.distance_to(target.position)
	var big: bool = target.kind == "tank" or target.kind == "boss"
	var pick := "pistol"
	if nearest_d < 50.0 and _usable(p, "flamer"):
		pick = "flamer"
	elif nearest_d < 60.0 and _usable(p, "shotgun"):
		pick = "shotgun"
	elif big and target_d < 140.0 and _usable(p, "cryo") and target.vulnerability() <= 1.0:
		pick = "cryo"
	elif big and _usable(p, "sniper"):
		pick = "sniper"
	elif count > 8 and target_d < 170.0 and target_d > 60.0 and _usable(p, "grenade"):
		pick = "grenade"
	elif count > 4 and target_d < 150.0 and _usable(p, "arc"):
		pick = "arc"
	elif count > 6 and _usable(p, "smg"):
		pick = "smg"
	elif target_d < 130.0 and _usable(p, "boomerang") and int(p.weapon_state["boomerang"]["mag"]) > 0:
		pick = "boomerang"
	if pick != p.weapon_id:
		want_weapon = GameData.WEAPON_ORDER.find(pick)


## 和人一样隔一会儿才用一次道具，优先保命。
func _use_items(p: Variant, dt: float, target: Variant) -> void:
	_item_wait -= dt
	if _item_wait > 0.0:
		return
	_item_wait = 1.0
	var inv: Dictionary = p.items
	var near := 0
	# tick 跑在 _process 里，空间哈希可能还留着刚释放的僵尸，这里直接遍历存活列表
	for z: Variant in game.zombies:
		if p.position.distance_squared_to(z.position) < 12100.0:
			near += 1
	var pick := ""
	if p.hp < p.max_hp * 0.5 and int(inv["medkit"]) > 0:
		pick = "medkit"
	elif p.armor <= 0.0 and int(inv["armor"]) > 0:
		pick = "armor"
	elif (game.zombies.size() >= 40 or game.base.hp < game.base.max_hp * 0.3) and int(inv["nuke"]) > 0 and game.nuke_wave != game.wave:
		pick = "nuke"
	elif near >= 8 and int(inv["flash"]) > 0:
		pick = "flash"
	elif near >= 7 and int(inv["decoy"]) > 0:
		pick = "decoy"
	elif near >= 5 and int(inv["frag"]) > 0:
		pick = "frag"
	elif (target.kind == "tank" or target.kind == "boss") and int(inv["sticky"]) > 0:
		pick = "sticky"
	elif near >= 5 and p.buff_damage_t <= 0.0 and int(inv["damage"]) > 0:
		pick = "damage"
	elif near >= 5 and p.buff_speed_t <= 0.0 and int(inv["speed"]) > 0:
		pick = "speed"
	elif near >= 5 and p.buff_ammo_t <= 0.0 and int(inv["inf_ammo"]) > 0:
		pick = "inf_ammo"
	elif not _usable(p, "smg") and int(inv["ammo_crate"]) > 0:
		pick = "ammo_crate"
	want_item = pick


func _manage_reload(p: Variant) -> void:
	if int(p.weapon_state[p.weapon_id]["mag"]) <= 0:
		want_reload = true
	elif not firing and int(p.weapon_state[p.weapon_id]["mag"]) < p.mag_size():
		want_reload = true


## 商店策略：先救急，再炮塔和升级，新武器和道具排在基础防御后面，剩余钱补弹药。
func shop() -> void:
	var priorities := ["repair", "heal", "base_repair", "ammo_smg", "turret", "up_smg", "up_arc", "up_pistol",
		"item_frag", "up_flamer", "reinforce", "up_sniper", "item_medkit", "up_grenade", "up_cryo", "up_boomerang",
		"item_armor", "up_shotgun", "turret_up", "max_hp", "item_flash", "item_sticky", "item_decoy", "ammo_shotgun",
		"item_damage", "item_speed", "item_inf_ammo", "item_ammo_crate", "item_nuke", "boots", "dash", "magnet"]
	# 已解锁武器的弹药少于一包才补，否则钱全砸在弹药上
	for id: String in game.player.owned_weapons():
		var spec: Dictionary = GameData.WEAPONS[id]
		if id != "smg" and id != "shotgun" and spec.has("ammo_pack") and int(game.player.weapon_state[id]["reserve"]) < int(spec["ammo_pack"]):
			priorities.insert(5, "ammo_" + id)
	if game.base.hp > game.base.max_hp * 0.8:
		priorities.erase("base_repair")
	if game.player.hp > game.player.max_hp * 0.7:
		priorities.erase("heal")
	if int(game.player.weapon_state["smg"]["reserve"]) > 200:
		priorities.erase("ammo_smg")
	var guard := 0
	var bought := true
	while bought and guard < 60:
		bought = false
		guard += 1
		for id: String in priorities:
			if _try_buy(id):
				bought = true
				break


func _try_buy(id: String) -> bool:
	if id == "turret":
		if game.turrets.size() >= 8:
			return false
		for item: Dictionary in game.shop_items():
			if item["id"] == "turret" and game.shop_can_buy(item):
				return _place_turret()
		return false
	if id == "repair" and game.map.missing_wall_hp() < 20.0:
		return false
	for item: Dictionary in game.shop_items():
		if item["id"] == id and game.shop_can_buy(item):
			return game.shop_buy(id)
	return false


func _place_turret() -> bool:
	# 沿围墙内圈放炮塔
	var map: Variant = game.map
	var spots := [
		Vector2i(26, 17), Vector2i(37, 17), Vector2i(26, 26), Vector2i(37, 26),
		Vector2i(28, 21), Vector2i(35, 21), Vector2i(31, 17), Vector2i(31, 26),
	]
	for s: Vector2i in spots:
		var cell: int = map.idx(s.x, s.y)
		if map.can_place_turret(cell):
			return game.try_place_turret(cell)
	return false
