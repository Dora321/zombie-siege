extends RefCounted
## 自动化测试机器人：用和玩家相同的输入接口打完整局，验证流程和粗测平衡。

var game: Node
var move := Vector2.ZERO
var aim_dir := Vector2.RIGHT
var firing := false
var want_dash := false
var want_reload := false
var want_weapon := -1

## 1.0 是完美瞄准；越低瞄准误差越大、反应越慢，用来模拟普通玩家。
var skill := 1.0
var _strafe := 1.0
var _strafe_t := 0.0
var _aim_error := 0.0
var _aim_error_t := 0.0
var _dash_wait := 0.0


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
	var target_d: float = p.position.distance_to(target.position)
	firing = target_d < 210.0
	_pick_weapon(p, nearest_d)
	_manage_reload(p)
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


func _pick_weapon(p: Variant, nearest_d: float) -> void:
	var sg: Dictionary = p.weapon_state["shotgun"]
	var mg: Dictionary = p.weapon_state["smg"]
	var pick := 0
	if nearest_d < 60.0 and (int(sg["mag"]) > 0 or int(sg["reserve"]) > 0):
		pick = 1
	elif game.zombies.size() > 6 and (int(mg["mag"]) > 0 or int(mg["reserve"]) > 0):
		pick = 2
	if GameData.WEAPON_ORDER[pick] != p.weapon_id:
		want_weapon = pick


func _manage_reload(p: Variant) -> void:
	if int(p.weapon_state[p.weapon_id]["mag"]) <= 0:
		want_reload = true
	elif not firing and int(p.weapon_state[p.weapon_id]["mag"]) < p.mag_size():
		want_reload = true


## 商店策略：先救急，再炮塔和升级，剩余钱补弹药。
func shop() -> void:
	var priorities := ["repair", "heal", "base_repair", "ammo_smg", "turret", "up_smg", "up_pistol", "reinforce",
		"up_shotgun", "turret_up", "max_hp", "ammo_shotgun", "boots", "dash", "magnet"]
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
