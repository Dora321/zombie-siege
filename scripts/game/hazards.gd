extends Node2D
## 敌人的范围攻击：落石、重砸、毒雾、召唤、冲撞、元素球和空投。
## 全部先在地上亮红圈，圈内的光环涨满才结算。画在实体下面，空中的石头画在最上层。

const FOG_DPS := 7.0
const FALL_H := 110.0
const MAX_CLOUDS := 10
const BOMB_R := 24.0
const ROCK_R := 21.0
const ACID_R := 20.0
const ORB_R := 15.0
const ORB_LIFE := 3.6
const ORB_HEIGHT := Vector2(0, -7)
const EMBER_LIFE := 0.9
const ICE_SLOW := 0.58
const ICE_FREEZE := 3.5
const CAR_R := 34.0
const BUNGEE_R := 16.0
const EMP_COLOR := Color("#bd80ff")
const FROST_COLOR := Color("#8cecff")

class Orb:
	var kind: String
	var pos: Vector2
	var dir: Vector2
	var hp: float
	var max_hp: float
	var damage: float
	var owner_ref: Variant
	var speed := 92.0
	var age := 0.0
	var trail_t := 0.0
	var targets := {}

	func center() -> Vector2:
		return pos + ORB_HEIGHT


class OrbTrail:
	var pos: Vector2
	var t := EMBER_LIFE
	var fire: bool


class StructureBurn:
	var damage := 0.0
	var t := 0.45


class Zone:
	var kind: String
	var pos: Vector2
	var r: float
	var t: float
	var dur: float
	var damage: float
	var from: Variant
	var spawn_kind: String
	var owner_ref: Variant
	## "dig" 是掘地领主的高对比黄圈。
	var tone := ""


class Cloud:
	var pos: Vector2
	var r: float
	var t: float
	var seed_a: float


class Lane:
	var from: Vector2
	var to: Vector2
	var width: float
	var t: float
	var dur: float


class Shock:
	var pos: Vector2
	var r: float
	var max_r: float
	var speed: float
	var damage: float
	var hit: bool


var game: Node
var map: Node2D
var zones: Array[Zone] = []
var clouds: Array[Cloud] = []
var lanes: Array[Lane] = []
var shocks: Array[Shock] = []
var orbs: Array[Orb] = []

var _top: Node2D
var _dot_note := 0.0
var _orb_trail: Array[OrbTrail] = []
var _frozen_turrets := {}
var _structure_burns := {}
var _chilled_player: Variant = null
var _player_chill_t := 0.0
var _player_burn_t := 0.0
var _burn_fx_t := 0.0


func setup(g: Node, m: Node2D) -> void:
	game = g
	map = m
	# 飞在空中的东西要盖住僵尸，单独一层
	_top = Node2D.new()
	_top.z_index = 5
	add_child(_top)
	_top.draw.connect(_draw_top)


func clear() -> void:
	zones.clear()
	clouds.clear()
	lanes.clear()
	shocks.clear()
	orbs.clear()
	_orb_trail.clear()
	_frozen_turrets.clear()
	_structure_burns.clear()
	_player_burn_t = 0.0
	_end_player_chill()


func _exit_tree() -> void:
	_end_player_chill()


## 施法者死亡或电磁脉冲被打断时，撤掉它所有未结算的招式。
func clear_owner(owner_node: Variant) -> void:
	var i := zones.size() - 1
	while i >= 0:
		if zones[i].owner_ref == owner_node:
			zones.remove_at(i)
		i -= 1
	for orb: Orb in orbs.duplicate():
		if orb.owner_ref == owner_node:
			orbs.erase(orb)


## 取消仍在蓄力的地面预警。已经发射的球和空投继续飞行。
func cancel_cast(owner_node: Variant) -> void:
	for z: Zone in zones.duplicate():
		if z.owner_ref == owner_node and z.kind in ["slam", "warn", "emp_pulse", "frost_ring"]:
			zones.erase(z)


func spawn_orb(kind: String, pos: Vector2, dir: Vector2, hp: float, damage: float, owner_node: Variant) -> Orb:
	var orb := Orb.new()
	orb.kind = kind
	orb.pos = pos
	orb.dir = dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	orb.hp = hp
	orb.max_hp = hp
	orb.damage = damage
	orb.owner_ref = owner_node
	orbs.append(orb)
	return orb


## 区域伤害可以同时命中多颗球。
func hit_orb(pos: Vector2, radius: float, damage: float, element: String) -> bool:
	if orbs.is_empty() or damage <= 0.0:
		return false
	var hit := false
	var reach := radius + ORB_R
	for orb: Orb in orbs.duplicate():
		if pos.distance_squared_to(orb.pos + ORB_HEIGHT) <= reach * reach:
			hit = damage_orb(orb, damage, element) or hit
	return hit


## 线段上最早接触球体的位置，用来和子弹命中的僵尸比较。
func orb_on_segment(from: Vector2, to: Vector2, radius: float, hits: Array) -> Dictionary:
	var result := {}
	var seg := to - from
	var length := seg.length()
	var dir := seg / maxf(length, 0.001)
	var reach := radius + ORB_R
	var closest := INF
	for orb in orbs:
		if hits.has(orb):
			continue
		var offset := orb.pos + ORB_HEIGHT - from
		var along := offset.dot(dir)
		var off := offset.cross(dir)
		if length <= 0.001:
			off = offset.length()
		if absf(off) > reach:
			continue
		var half := sqrt(maxf(reach * reach - off * off, 0.0))
		if along + half < 0.0 or along - half > length or along - half >= closest:
			continue
		closest = along - half
		result = {"orb": orb, "t": maxf(closest, 0.0) / maxf(length, 0.001)}
	return result


func damage_orb(orb: Orb, damage: float, element: String) -> bool:
	if damage <= 0.0 or not orbs.has(orb):
		return false
	var fire := orb.kind == "fire_orb"
	var counter := element == "ice" if fire else (element == "fire" or element == "blast")
	orb.hp -= damage * (4.5 if counter else 1.0)
	var at := orb.pos + ORB_HEIGHT
	if counter or not fire:
		game.fx.frost(at)
	elif element == "fire":
		game.fx.ember(at)
	else:
		game.fx.spark(at)
	if orb.hp <= 0.0:
		orbs.erase(orb)
		game.fx.ring(at, ORB_R * 1.8, 0.3, Color("#ffe060") if fire else Color("#a8f4ff"))
		if fire:
			game.fx.explosion(at, ORB_R * 1.4)
		else:
			game.fx.debris(at, "wall")
		game.add_shake(0.35)
		Sfx.play("shield_break")
		var owner: Variant = orb.owner_ref
		if (counter or orb.age <= 1.5) and is_instance_valid(owner) and owner.is_boss and not owner.dead:
			owner._brain.counter_backlash(owner)
	return true


func _zone(kind: String, pos: Vector2, r: float, windup: float, damage: float, owner_node: Variant) -> Zone:
	var z := Zone.new()
	z.kind = kind
	z.pos = pos
	z.r = r
	z.t = windup
	z.dur = windup
	z.damage = damage
	z.owner_ref = owner_node
	zones.append(z)
	return z


func slam(pos: Vector2, r: float, damage: float, windup: float, owner_node: Variant, tone := "") -> void:
	_zone("slam", pos, r, windup, damage, owner_node).tone = tone


## 从 from 抛过来的石头；from 为 null 时从天而降。
func rock(pos: Vector2, damage: float, windup: float, from: Variant = null, owner_node: Variant = null) -> void:
	var z := _zone("rock", pos, ROCK_R, windup, damage, owner_node)
	z.from = from


## 投弹的气球被打爆时炸弹已经在半空了，所以不记施法者。
func bomb(pos: Vector2, damage: float) -> void:
	_zone("bomb", pos, BOMB_R, 0.85, damage, null)


func acid(pos: Vector2, damage: float) -> void:
	_zone("acid", pos, ACID_R, 1.1, damage, null)


## 毒雾不一次性结算，damage 字段存的是持续秒数。
func fog(pos: Vector2, r: float, seconds: float, owner_node: Variant) -> void:
	_zone("fog", pos, r, 1.0, seconds, owner_node)


func spawn_circle(kind: String, pos: Vector2, owner_node: Variant, windup: float) -> void:
	var at: Vector2 = map.unstick(pos, 5.0, map.BLOCK_ZOMBIE)
	var z := _zone("spawn", at, 13.0, windup, 0.0, owner_node)
	z.spawn_kind = kind


func drop_car(pos: Vector2, delay: float, damage: float, owner_node: Variant) -> void:
	_zone("car_toss", _inside_map(pos), CAR_R, delay, damage, owner_node)


func bungee_drop(pos: Vector2, delay: float, spawn_kind: String, owner_node: Variant) -> void:
	var at: Vector2 = map.unstick(_inside_map(pos), 5.0, map.BLOCK_ZOMBIE)
	_zone("bungee", at, BUNGEE_R, delay, 0.0, owner_node).spawn_kind = spawn_kind


func emp_pulse(pos: Vector2, r: float, delay: float, owner_node: Variant) -> void:
	_zone("emp_pulse", pos, r, delay, 16.0, owner_node)


func emp_pending(owner_node: Variant) -> bool:
	for z: Zone in zones:
		if z.owner_ref == owner_node and z.kind == "emp_pulse":
			return true
	return false


func frost_ring(pos: Vector2, r: float, delay: float, damage: float, owner_node: Variant) -> void:
	_zone("frost_ring", pos, r, delay, damage, owner_node)


func thaw_turrets() -> void:
	_frozen_turrets.clear()


func _inside_map(pos: Vector2) -> Vector2:
	return pos.clamp(Vector2(8, 8), Vector2(map.PIXEL_W - 8.0, map.PIXEL_H - 8.0))


## 只是预警圈（比如冲击波起手），落地时什么都不做。
func warn_ring(pos: Vector2, r: float, windup: float, owner_node: Variant, tone := "") -> void:
	_zone("warn", pos, r, windup, 0.0, owner_node).tone = tone


## 返回通道本身，蓄力被打断时施法者可以把它撤掉。
func lane(from: Vector2, dir: Vector2, length: float, width: float, dur: float) -> Lane:
	var l := Lane.new()
	l.from = from
	l.to = from + dir * length
	l.width = width
	l.t = dur
	l.dur = dur
	lanes.append(l)
	return l


func shockwave(pos: Vector2, max_r: float, speed: float, damage: float) -> void:
	var s := Shock.new()
	s.pos = pos
	s.r = 6.0
	s.max_r = max_r
	s.speed = speed
	s.damage = damage
	s.hit = false
	shocks.append(s)


## 给机器人用：这个位置上有没有马上要炸的东西，返回危险中心。
func threat_at(pos: Vector2, margin: float) -> Variant:
	for z in zones:
		if z.kind != "spawn" and z.kind != "warn" and pos.distance_to(z.pos) < z.r + margin:
			return z.pos
	for c in clouds:
		if pos.distance_to(c.pos) < c.r + margin:
			return c.pos
	for l in lanes:
		var closest := Geometry2D.get_closest_point_to_segment(pos, l.from, l.to)
		if pos.distance_to(closest) < l.width * 0.5 + margin:
			return closest
	for orb in orbs:
		var landing := orb.pos + orb.dir * orb.speed * 0.3
		var closest := Geometry2D.get_closest_point_to_segment(pos, orb.pos, landing)
		if pos.distance_to(closest) < ORB_R + margin:
			return closest
	return null


func _physics_process(dt: float) -> void:
	_dot_note -= dt
	var pending := zones.duplicate()
	pending.reverse()
	for z: Zone in pending:
		z.t -= dt
		# 落点击毁炮塔时的连锁爆炸可能让 Boss 阶段切换或死亡。
		if z.t <= 0.0 and zones.has(z):
			zones.erase(z)
			_land(z)
	var i := lanes.size() - 1
	while i >= 0:
		lanes[i].t -= dt
		if lanes[i].t <= 0.0:
			lanes.remove_at(i)
		i -= 1
	_update_clouds(dt)
	_update_shocks(dt)
	_update_orbs(dt)
	_update_orb_effects(dt)
	queue_redraw()
	_top.queue_redraw()


func _update_orbs(dt: float) -> void:
	var bounds := Rect2(0, 0, map.PIXEL_W, map.PIXEL_H)
	for orb: Orb in orbs.duplicate():
		if not orbs.has(orb):
			continue
		orb.age += dt
		orb.pos += orb.dir * orb.speed * dt
		if orb.age >= ORB_LIFE or not bounds.has_point(orb.pos):
			orbs.erase(orb)
			continue
		orb.trail_t -= dt
		if orb.trail_t <= 0.0:
			orb.trail_t = 0.13
			var trail := OrbTrail.new()
			trail.pos = orb.pos
			trail.fire = orb.kind == "fire_orb"
			_orb_trail.append(trail)
		_orb_contact(orb, dt)


func _orb_contact(orb: Orb, dt: float) -> void:
	var fire := orb.kind == "fire_orb"
	var player: Variant = game.player
	if player != null and player.alive and player.invuln <= 0.0 and not game.god_mode and not orb.targets.has(player):
		if player.position.distance_to(orb.pos) <= ORB_R + 4.0:
			orb.targets[player] = true
			player.take_damage(orb.damage, orb.pos - orb.dir * 4.0)
			if player.alive:
				if fire:
					_player_burn_t = maxf(_player_burn_t, 0.8)
				else:
					_chill_player(player)
	for s: Variant in game._structures_in(orb.pos, ORB_R + 4.0):
		if not is_instance_valid(s) or orb.targets.has(s):
			continue
		orb.targets[s] = true
		if s.kind == "barrel":
			s.take_damage.call_deferred(1000.0)
			continue
		if fire and s.kind != "base":
			var burn: StructureBurn = _structure_burns.get(s)
			if burn == null:
				burn = StructureBurn.new()
				_structure_burns[s] = burn
			burn.damage += orb.damage * 0.25
			game.fx.ember(s.position + ORB_HEIGHT)
		elif not fire and s.kind == "turret":
			_frozen_turrets[s] = ICE_FREEZE
			s._cooldown = maxf(s._cooldown, dt + 0.001)
			game.fx.frost(s.position + ORB_HEIGHT)
		s.take_damage(orb.damage * (1.25 if fire else 1.0))


func _chill_player(player: Variant) -> void:
	if _chilled_player != player:
		_end_player_chill()
		_chilled_player = player
		player.speed_mult *= ICE_SLOW
	_player_chill_t = 1.6
	game.fx.frost(player.position + ORB_HEIGHT)


func _end_player_chill() -> void:
	if is_instance_valid(_chilled_player):
		_chilled_player.speed_mult /= ICE_SLOW
	_chilled_player = null
	_player_chill_t = 0.0


func _update_orb_effects(dt: float) -> void:
	if _player_chill_t > 0.0:
		_player_chill_t -= dt
		if _player_chill_t <= 0.0 or not is_instance_valid(_chilled_player) or not _chilled_player.alive:
			_end_player_chill()
	for turret: Variant in _frozen_turrets.keys():
		var left: float = _frozen_turrets[turret] - dt
		if left <= 0.0 or not is_instance_valid(turret) or not turret.alive:
			_frozen_turrets.erase(turret)
		else:
			_frozen_turrets[turret] = left
			turret._cooldown = maxf(turret._cooldown, dt + 0.001)
	for structure: Variant in _structure_burns.keys():
		var burn: StructureBurn = _structure_burns.get(structure)
		if burn == null:
			continue
		burn.t -= dt
		if not is_instance_valid(structure) or not structure.alive:
			_structure_burns.erase(structure)
		elif burn.t <= 0.0:
			_structure_burns.erase(structure)
			game.fx.ember(structure.position + ORB_HEIGHT)
			structure.take_damage(burn.damage)
	var player: Variant = game.player
	_player_burn_t = maxf(_player_burn_t - dt, 0.0)
	for i in range(_orb_trail.size() - 1, -1, -1):
		var trail := _orb_trail[i]
		trail.t -= dt
		if trail.t <= 0.0:
			_orb_trail.remove_at(i)
		elif trail.fire and player != null and player.alive and player.position.distance_to(trail.pos) < 8.0:
			_player_burn_t = maxf(_player_burn_t, 0.35)
	if _player_burn_t > 0.0 and player != null and player.alive and not game.god_mode and player.dash_t <= 0.0:
		player.take_dot(5.0 * dt)
		_burn_fx_t -= dt
		if _burn_fx_t <= 0.0:
			_burn_fx_t = 0.16
			game.fx.ember(player.position + ORB_HEIGHT)


func _update_clouds(dt: float) -> void:
	var player: Variant = game.player
	var i := clouds.size() - 1
	while i >= 0:
		var c := clouds[i]
		c.t -= dt
		if c.t <= 0.0:
			clouds.remove_at(i)
		elif player != null and player.alive and player.position.distance_squared_to(c.pos) < c.r * c.r:
			player.take_dot(FOG_DPS * dt)
		i -= 1


func _update_shocks(dt: float) -> void:
	var player: Variant = game.player
	var i := shocks.size() - 1
	while i >= 0:
		var s := shocks[i]
		s.r += s.speed * dt
		if s.r >= s.max_r:
			shocks.remove_at(i)
		elif not s.hit and player != null and player.alive and absf(player.position.distance_to(s.pos) - s.r) < 7.0:
			# 冲刺的无敌帧可以穿过去，这是设计好的躲法
			if player.dash_t <= 0.0:
				s.hit = true
				player.take_damage(s.damage, s.pos)
		i -= 1


func _land(z: Zone) -> void:
	match z.kind:
		"slam":
			game.damage_area(z.pos, z.r, z.damage, 2.0)
			game.add_shake(0.7)
			game.fx.dust(z.pos, 18)
			game.fx.ring(z.pos, z.r, 0.25, Color("#ffd0a0"))
			game.decals.stamp(Art.scorch, z.pos + Vector2(0, 2))
			Sfx.play("slam")
		"rock":
			game.damage_area(z.pos, z.r, z.damage, 1.5)
			game.add_shake(0.25)
			game.fx.dust(z.pos, 10)
			game.fx.debris(z.pos, "rock")
			game.decals.stamp(Art.rubble[randi() % Art.rubble.size()], z.pos + Vector2(-8, -8))
			Sfx.play("rock_fall", -4.0, 0.12)
		"bomb", "acid":
			game.damage_area(z.pos, z.r, z.damage, 0.8)
			if z.kind == "acid":
				game.soak_area(z.pos, z.r, GameData.WET_SPLASH)
			game.fx.acid_burst(z.pos)
			game.decals.stamp(Art.acid_splat, z.pos)
			game.bullets.add_pool(z.pos, 14.0, 2.6)
			Sfx.play("splat", -4.0)
		"fog":
			if clouds.size() >= MAX_CLOUDS:
				clouds.remove_at(0)
			var c := Cloud.new()
			c.pos = z.pos
			c.r = z.r
			c.t = z.damage
			c.seed_a = randf() * TAU
			clouds.append(c)
			Sfx.play("fog_hiss", -6.0, 0.1)
		"spawn":
			game.spawn_minion(z.spawn_kind, z.pos, z.owner_ref)
			game.fx.dust(z.pos, 8)
			Sfx.play("summon_pop", -5.0, 0.15)
		"car_toss":
			game.damage_area(z.pos, z.r, z.damage, 2.0)
			game.fx.dust(z.pos, 28)
			game.fx.ring(z.pos, z.r, 0.35, Color("#ffd080"))
			game.fx.debris(z.pos, "wall")
			game.decals.stamp(Art.scorch, z.pos)
			game.add_shake(0.85)
			Sfx.play("slam")
		"bungee":
			if game.spawn_minion(z.spawn_kind, z.pos, z.owner_ref) != null:
				game.fx.dust(z.pos, 10)
				if not Harness.automated():
					game.fx.text(z.pos + Vector2(0, -20), "空降突袭！", Color("#fff0d0"))
				Sfx.play("summon_pop", -2.0, 0.15)
		"emp_pulse", "frost_ring":
			_land_element_ring(z)


func _land_element_ring(z: Zone) -> void:
	var emp := z.kind == "emp_pulse"
	var player: Variant = game.player
	if player != null and player.alive and player.position.distance_to(z.pos) <= z.r:
		var can_chill: bool = not emp and player.invuln <= 0.0 and not game.god_mode
		player.take_damage(z.damage, z.pos)
		if can_chill and player.alive:
			_chill_player(player)
	game.fx.ring(z.pos, z.r, 0.45, EMP_COLOR if emp else FROST_COLOR)
	for i in 8:
		var at := z.pos + Vector2.from_angle(i * TAU / 8.0) * z.r * 0.78
		if emp:
			game.fx.zap(at)
		else:
			game.fx.frost(at)
	if emp:
		if game.has_method("jam_turrets_near"):
			game.jam_turrets_near(z.pos, z.r, 3.5)
		Sfx.play("arc")
	else:
		if game.has_method("freeze_turrets_near"):
			game.freeze_turrets_near(z.pos, z.r, 3.0)
		Sfx.play("cryo")


func _draw() -> void:
	for c in clouds:
		_draw_cloud(c)
	for trail in _orb_trail:
		var fade := trail.t / EMBER_LIFE
		var color := Color(1.0, 0.38, 0.12, fade * 0.78) if trail.fire else Color(0.52, 0.88, 1.0, fade * 0.42)
		var at := trail.pos.round()
		draw_circle(at, 3.0 + 4.0 * fade, Color(color, color.a * 0.48))
		draw_rect(Rect2(at + Vector2(-3, -2), Vector2(3, 2)), color)
		draw_rect(Rect2(at + Vector2(3, 1), Vector2(2, 2)), color)
	for l in lanes:
		_draw_lane(l)
	for z in zones:
		_draw_zone(z)
	for s in shocks:
		var fade := 1.0 - s.r / s.max_r
		draw_arc(s.pos.round(), s.r, 0.0, TAU, 48, Color(1.0, 0.75, 0.4, fade), 3.0)
		draw_arc(s.pos.round(), s.r - 3.0, 0.0, TAU, 48, Color(0.9, 0.2, 0.12, fade * 0.7), 2.0)


## 红圈：边框常亮，内圈随蓄力涨满，快落地时高频闪。
func _draw_zone(z: Zone) -> void:
	var ratio := 1.0 - clampf(z.t / maxf(z.dur, 0.001), 0.0, 1.0)
	var at := z.pos.round()
	var edge := Color("#ff3020")
	var fill := Color(1.0, 0.15, 0.1, 0.1 + ratio * 0.2)
	match z.kind:
		"emp_pulse", "frost_ring":
			_draw_element_ring(z, ratio)
			return
		"bungee":
			_draw_bungee_target(at, z.r, ratio)
			return
		"car_toss":
			edge = Color("#ffde54") if int(z.t * 9.0) % 2 == 0 else Color("#ff4330")
			fill = Color(1.0, 0.13, 0.05, 0.22 + ratio * 0.18)
			var shadow_size := Vector2(17, 6) * lerpf(0.35, 1.0, ratio)
			draw_rect(Rect2(at - shadow_size, shadow_size * 2.0), Color(0.09, 0.04, 0.08, 0.6))
			for corner: Vector2 in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
				var p := at + corner * Vector2(23, 17)
				draw_line(p, p - Vector2(corner.x * 8, 0), edge, 2.0)
				draw_line(p, p - Vector2(0, corner.y * 7), edge, 2.0)
		"spawn":
			edge = Color("#c070ff")
			fill = Color(0.7, 0.3, 1.0, 0.1 + ratio * 0.2)
		"fog":
			fill = Color(0.5, 0.9, 0.2, 0.1 + ratio * 0.25)
		"acid", "bomb":
			fill = Color(0.6, 0.9, 0.2, 0.12 + ratio * 0.22)
	if z.tone == "dig":
		# 断电时颜色超过 1，被全局变暗后依然是亮黄
		var k := 2.1 if GameData.wave_special(game.wave) == "blackout" else 1.0
		edge = Color(1.0 * k, 0.87 * k, 0.12 * k)
		fill = Color(1.0, 0.85, 0.1, 0.14 + ratio * 0.24)
	if ratio > 0.7 and int(z.t * 18.0) % 2 == 0:
		edge = Color("#fff0c0")
	draw_circle(at, z.r, fill)
	draw_circle(at, z.r * ratio, Color(fill.r, fill.g, fill.b, fill.a + 0.15))
	draw_arc(at, z.r, 0.0, TAU, maxi(20, int(z.r)), edge, 1.0)


func _draw_element_ring(z: Zone, ratio: float) -> void:
	var emp := z.kind == "emp_pulse"
	var color := EMP_COLOR if emp else FROST_COLOR
	var pulse := sin(ratio * TAU * 4.0) * 0.5 + 0.5
	var at := z.pos.round()
	draw_circle(at, z.r, Color(color, 0.08 + ratio * 0.12))
	draw_arc(at, z.r, 0.0, TAU, 72, Color(color, 0.7 + pulse * 0.3), 2.0)
	draw_arc(at, z.r * lerpf(0.1, 1.0, ratio), 0.0, TAU, 64, Color(FROST_COLOR, 0.35 + pulse * 0.5), 1.0)
	for i in 8:
		var dir := Vector2.from_angle(i * TAU / 8.0)
		var tip := at + dir * (z.r - 3.0)
		var foot := tip - dir * 9.0
		if emp:
			var bend := tip - dir * 5.0 + dir.orthogonal() * 4.0
			draw_polyline(PackedVector2Array([foot, bend, tip]), FROST_COLOR, 1.0)
		else:
			draw_line(foot, tip, color, 1.0)
			draw_line(tip - dir * 4.0 - dir.orthogonal() * 3.0, tip - dir * 4.0 + dir.orthogonal() * 3.0, color, 1.0)


func _draw_bungee_target(at: Vector2, radius: float, ratio: float) -> void:
	var red := Color("#ff4638")
	var white := Color("#fff3df")
	draw_circle(at, radius, Color(0.32, 0.04, 0.05, 0.72))
	draw_arc(at, radius - 1.0, 0.0, TAU, 28, red, 3.0)
	draw_arc(at, radius * 0.64, 0.0, TAU, 24, white, 2.0)
	draw_arc(at, radius * 0.36, 0.0, TAU, 16, red, 2.0)
	draw_circle(at, 2.0 + ratio * 2.0, white)


func _draw_lane(l: Lane) -> void:
	var ratio := 1.0 - clampf(l.t / l.dur, 0.0, 1.0)
	var dir := l.from.direction_to(l.to)
	var side := dir.orthogonal() * l.width * 0.5
	var far := l.from.lerp(l.to, clampf(ratio * 1.6, 0.0, 1.0))
	var pts := PackedVector2Array([l.from + side, far + side, far - side, l.from - side])
	draw_colored_polygon(pts, Color(1.0, 0.15, 0.1, 0.16 + ratio * 0.16))
	var edge := Color("#fff0c0") if ratio > 0.7 and int(l.t * 18.0) % 2 == 0 else Color("#ff3020")
	draw_line(l.from + side, l.to + side, edge, 1.0)
	draw_line(l.from - side, l.to - side, edge, 1.0)
	# 指向箭头顺着冲撞方向流动
	var length := l.from.distance_to(l.to)
	for k in range(0, int(length), 32):
		var at: Vector2 = l.from + dir * fmod(k + ratio * 96.0, length)
		var tip: Vector2 = at + dir * 6.0
		draw_line(at + side * 0.4, tip, edge, 1.0)
		draw_line(at - side * 0.4, tip, edge, 1.0)


func _draw_cloud(c: Cloud) -> void:
	var fade := clampf(c.t, 0.0, 1.0)
	draw_circle(c.pos.round(), c.r, Color(0.42, 0.7, 0.16, 0.2 * fade))
	draw_arc(c.pos.round(), c.r, 0.0, TAU, 24, Color(0.7, 1.0, 0.3, 0.5 * fade), 1.0)
	var step := int(c.t * 5.0)
	for k in 9:
		var a := c.seed_a + k * 2.399
		var d := c.r * (0.25 + 0.7 * fmod(k * 0.37, 1.0))
		var at: Vector2 = c.pos + Vector2(cos(a + c.t * 0.5), sin(a + c.t * 0.5) * 0.7) * d
		var size := 2.0 + float((step + k) % 3)
		draw_rect(Rect2(at.round(), Vector2(size, size)), Color(0.6, 0.9, 0.25, 0.5 * fade))


func _draw_top() -> void:
	for orb in orbs:
		var fire := orb.kind == "fire_orb"
		var at := (orb.pos + ORB_HEIGHT).round()
		draw_element_orb(_top, at, ORB_R, orb.kind, orb.age * orb.speed / ORB_R)
		_top.draw_rect(Rect2(at + Vector2(-11, -21), Vector2(22, 4)), Art.OUTLINE)
		_top.draw_rect(Rect2(at + Vector2(-10, -20), Vector2(20 * clampf(orb.hp / orb.max_hp, 0.0, 1.0), 2)), Color("#ffb048") if fire else Color("#8cf0ff"))
		Art.draw_text(_top, "冰克" if fire else "火克", at + Vector2(0, -33), 10, Color("#b0f5ff") if fire else Color("#ffe060"), 1)
	for turret: Variant in _frozen_turrets:
		if is_instance_valid(turret) and turret.alive:
			var at: Vector2 = turret.position + Vector2(0, -8)
			_top.draw_rect(Rect2(at - Vector2(8, 7), Vector2(16, 14)), Color(0.42, 0.86, 1.0, 0.32))
			_top.draw_arc(at, 10.0, 0.0, TAU, 20, Color("#a8f4ff"), 1.0)
	for z in zones:
		var ratio := 1.0 - clampf(z.t / z.dur, 0.0, 1.0)
		var at := _falling_pos(z, ratio)
		match z.kind:
			"car_toss":
				_draw_car(at, ratio)
				Art.draw_text(_top, "废车空投！", z.pos + Vector2(0, 33), 10, Color("#ffe080"), 1)
			"bungee":
				_draw_bungee(z, ratio)
			"rock":
				_top.draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), Art.OUTLINE)
				_top.draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color("#8a8880"))
				_top.draw_rect(Rect2(at - Vector2(4, 4), Vector2(4, 3)), Color("#b0aea4"))
				_top.draw_rect(Rect2(at + Vector2(1, 1), Vector2(3, 3)), Color("#5e5c56"))
			"bomb":
				_top.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 7)), Art.OUTLINE)
				_top.draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 5)), Color("#70a828"))
				_top.draw_rect(Rect2(at - Vector2(1, 3), Vector2(2, 1)), Color("#c8ff70"))
			"acid":
				_top.draw_rect(Rect2(at - Vector2(1, 3), Vector2(2, 5)), Color("#a8e040"))
				_top.draw_rect(Rect2(at - Vector2(0, 5), Vector2(1, 2)), Color("#e8ff90"))


## 蓄力和滚动共用球体画法。亮斑绕核心转动，冰火用不同的外沿形状。
func draw_element_orb(canvas: CanvasItem, pos: Vector2, r: float, kind: String, angle: float) -> void:
	var fire := kind == "fire_orb"
	var edge := Color("#ff7828") if fire else Color("#70e8ff")
	var light := Color("#ffe060") if fire else Color("#e8ffff")
	canvas.draw_circle(pos, r + 4.0, Color(edge, 0.23))
	canvas.draw_circle(pos, r, Art.OUTLINE)
	canvas.draw_circle(pos, r - 1.0, edge.darkened(0.28))
	canvas.draw_circle(pos + Vector2(-1, -2), r * 0.74, edge)
	canvas.draw_circle(pos + Vector2(-2, -3), r * 0.43, light)
	for k in 7:
		var arm := Vector2.from_angle(angle + k * TAU / 7.0)
		var at := (pos + arm * (r + float(k % 3))).round()
		var ray := (at + (Vector2(0, -4) if fire else arm * 4.0)).round()
		canvas.draw_line(at, ray, edge if k % 2 == 0 else light, 2.0)
		var fleck := (pos + arm * r * 0.6).round()
		canvas.draw_rect(Rect2(fleck, Vector2(2, 2)), light if k % 2 == 0 else edge.darkened(0.25))


func _draw_car(at: Vector2, ratio: float) -> void:
	_top.draw_set_transform(at, sin(ratio * TAU) * 0.3)
	_top.draw_rect(Rect2(-20, -18, 36, 17), Art.OUTLINE)
	_top.draw_rect(Rect2(-18, -16, 31, 10), Color("#cbd2b4"))
	_top.draw_rect(Rect2(-17, -8, 36, 8), Color("#a54f32"))
	_top.draw_rect(Rect2(-19, -9, 38, 2), Color("#e1af65"))
	_top.draw_rect(Rect2(-20, -2, 41, 3), Color("#46363b"))
	_top.draw_rect(Rect2(-14, -14, 10, 6), Color("#364d60"))
	_top.draw_rect(Rect2(4, -14, 9, 6), Color("#364d60"))
	_top.draw_line(Vector2(5, -14), Vector2(11, -9), Color("#83a7a7"), 1.0)
	_top.draw_rect(Rect2(-14, -5, 5, 2), Color("#7d3d2f"))
	_top.draw_rect(Rect2(16, -6, 3, 2), Color("#fff08a"))
	for x: int in [-12, 12]:
		_top.draw_rect(Rect2(x - 4, -3, 8, 7), Art.OUTLINE)
		_top.draw_rect(Rect2(x - 2, -1, 4, 3), Color("#7d7777"))
	_top.draw_set_transform(Vector2.ZERO)


func _draw_bungee(z: Zone, ratio: float) -> void:
	var height := FALL_H * (1.0 - ratio * ratio)
	var sway := sin(ratio * TAU * 1.5) * 7.0 * (1.0 - ratio)
	var at := (z.pos + Vector2(sway, -height - 14.0)).round()
	var size := Art.char_size(z.spawn_kind)
	var visible_top := (_top.get_canvas_transform().affine_inverse() * Vector2.ZERO).y
	var rope_start := Vector2(roundf(z.pos.x), minf(visible_top, at.y - 25.0))
	var hook := at - Vector2(0, size.y * 0.4)
	_top.draw_line(rope_start, hook, Art.OUTLINE, 3.0)
	_top.draw_line(rope_start, hook, Color("#e2c8a0"), 1.0)
	_top.draw_set_transform(at, PI + sway * 0.06)
	_top.draw_texture(Art.frame(z.spawn_kind, Art.DIR_DOWN, 0, false), -Vector2(size) * 0.5)
	_top.draw_set_transform(Vector2.ZERO)


func _falling_pos(z: Zone, ratio: float) -> Vector2:
	if z.from != null:
		# 抛物线：从 Boss 手里飞过来
		var from: Vector2 = z.from
		return (from.lerp(z.pos, ratio) + Vector2(0, -sin(ratio * PI) * 46.0)).round()
	return (z.pos + Vector2(0, -FALL_H * (1.0 - ratio * ratio))).round()
