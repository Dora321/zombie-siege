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
var _nav_goal := -1
var _nav_t := 0.0
var _nav_field := PackedInt32Array()


func _init(g: Node) -> void:
	game = g


func tick(dt: float) -> void:
	var p: Variant = game.player
	if p == null or not p.alive:
		return
	_nav_t -= dt
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
	# 召唤者和尖叫者离得不远就先点掉，和人一样打有威胁的
	for z: Variant in game.zombies:
		if (z.kind == "summoner" or z.kind == "screamer") and nearest_d > 40.0 and p.position.distance_to(z.position) < 190.0:
			target = z
			break
	var home: Vector2 = game.base.position + Vector2(0, 26)
	if target == null:
		firing = false
		move = go_to(p, home) if p.position.distance_to(home) > 20.0 else Vector2.ZERO
		_fetch_crate(p)
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
	firing = target_d < 210.0 and game.map.line_clear(from, target.center(), game.map.BLOCK_BULLET)
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
		move = go_to(p, target.position)
	else:
		move = go_to(p, home) * 0.5 if p.position.distance_to(home) > 90.0 else Vector2.ZERO
		move += aim_dir.orthogonal() * _strafe * 0.5
	if nearest_d > 60.0:
		_fetch_crate(p)
	# 红圈、毒雾、冲撞通道：直接跑开，通道上来不及就冲刺
	var danger: Variant = game.hazards.threat_at(p.position, 8.0)
	if danger != null:
		var off: Vector2 = p.position - danger
		move = off.normalized() if off.length_squared() > 1.0 else aim_dir.orthogonal()
		if skill > 0.5 and _dash_wait <= 0.0:
			want_dash = true
			_dash_wait = 2.0
		return
	# 踩到酸液就走开
	for pool: Variant in game.bullets.pools:
		if p.position.distance_to(pool.pos) < pool.r + 6.0:
			move = (p.position - pool.pos).normalized()
			return
	# 被障碍挡住视线或路线时横向绕开
	if not game.map.line_clear(p.position, target.position, game.map.BLOCK_BULLET | game.map.BLOCK_PLAYER):
		if not _on_crate_run(p, nearest_d):
			move = go_to(p, target.position)


## 去捡补给箱，和人一样周围没僵尸贴脸时才去。
func _fetch_crate(p: Variant) -> void:
	var crate: Variant = game.events.nearest_crate(p.position)
	if crate != null:
		move = go_to(p, crate.pos)


func _on_crate_run(p: Variant, nearest_d: float) -> bool:
	return nearest_d > 60.0 and game.events.nearest_crate(p.position) != null


## 按地形寻路走向目标：看得见就直走，否则沿广度优先场绕过去（窄巷地图必须这样）。
func go_to(p: Variant, dest: Vector2) -> Vector2:
	var map: Variant = game.map
	# 中心线通不算数，身体两侧也要通，否则会顶着车角走不动
	var side: Vector2 = p.position.direction_to(dest).orthogonal() * 7.0
	if map.line_clear(p.position + side, dest + side, map.BLOCK_PLAYER) and map.line_clear(p.position - side, dest - side, map.BLOCK_PLAYER):
		return p.position.direction_to(dest)
	var goal: int = map.cell_of(dest)
	if goal != _nav_goal and _nav_t <= 0.0 or _nav_field.is_empty():
		_nav_goal = goal
		_nav_t = 0.4
		_nav_field = map.reach_field(goal, map.BLOCK_PLAYER)
	var here: int = map.cell_of(p.position)
	var best := -1
	var best_d: int = _nav_field[here] if _nav_field[here] >= 0 else 1 << 30
	var x: int = here % map.W
	var y: int = here / map.W
	for k in 8:
		var nx: int = x + map.DIRS[k].x
		var ny: int = y + map.DIRS[k].y
		if not map.in_bounds(nx, ny):
			continue
		var j: int = map.idx(nx, ny)
		var d: int = _nav_field[j]
		if d < 0 or d >= best_d:
			continue
		# 斜着走不能切墙角
		if k >= 4 and (map.blocks(map.idx(nx, y), map.BLOCK_PLAYER) or map.blocks(map.idx(x, ny), map.BLOCK_PLAYER)):
			continue
		best_d = d
		best = j
	if best < 0:
		return p.position.direction_to(dest)
	return p.position.direction_to(map.cell_center(best))


func _usable(p: Variant, id: String) -> bool:
	if not p.owns_weapon(id):
		return false
	var st: Dictionary = p.weapon_state[id]
	return int(st["mag"]) > 0 or int(st["reserve"]) > 0


## 按局面挑枪：贴脸用火焰和霰弹，大怪用狙和冰冻，人多用电弧和榴弹。
func _pick_weapon(p: Variant, nearest_d: float, target: Variant) -> void:
	var count: int = game.zombies.size()
	var target_d: float = p.position.distance_to(target.position)
	var big: bool = target.kind == "tank" or target.is_boss
	var pick := "pistol"
	if nearest_d < 50.0 and _usable(p, "flamer"):
		pick = "flamer"
	elif target.kind == "shielder" and target._brain.up or target.kind == "mirror":
		# 护盾兵和镜面女皇不走正面：优先范围武器和电弧
		if target_d < 150.0 and _usable(p, "arc"):
			pick = "arc"
		elif target_d < 170.0 and target_d > 50.0 and _usable(p, "grenade"):
			pick = "grenade"
		elif target_d < 70.0 and _usable(p, "flamer"):
			pick = "flamer"
		elif _usable(p, "smg"):
			pick = "smg"
	elif target.kind == "graveborn" and target._chill_t <= 0.0 and target._burn_t <= 0.0:
		# 再生坟主：先挂冰或火压住再生
		if target_d < 70.0 and _usable(p, "flamer"):
			pick = "flamer"
		elif target_d < 140.0 and _usable(p, "cryo"):
			pick = "cryo"
		elif _usable(p, "smg"):
			pick = "smg"
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
	elif (target.kind == "tank" or target.is_boss) and int(inv["sticky"]) > 0:
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
	var offsets := [
		Vector2i(-4, -3), Vector2i(7, -3), Vector2i(-4, 6), Vector2i(7, 6),
		Vector2i(-2, 1), Vector2i(5, 1), Vector2i(1, -3), Vector2i(1, 6),
	]
	for s: Vector2i in offsets:
		var cell: int = map.idx(map.base_x0 + s.x, map.base_y0 + s.y)
		if map.can_place_turret(cell):
			return game.try_place_turret(cell)
	return false
