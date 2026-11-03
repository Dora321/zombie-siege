extends Node2D
## 敌人的范围攻击：落石、重砸、毒弹、毒雾、召唤、冲撞预警、冲击波。
## 全部先在地上亮红圈，圈内的光环涨满才结算。画在实体下面，空中的石头画在最上层。

const FOG_DPS := 7.0
const FALL_H := 110.0
const MAX_CLOUDS := 10
const BOMB_R := 24.0
const ROCK_R := 21.0
const ACID_R := 20.0

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

var _top: Node2D
var _dot_note := 0.0


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


## 施法者死了，它还没落地的招式也作废。
func clear_owner(owner_node: Variant) -> void:
	var i := zones.size() - 1
	while i >= 0:
		if zones[i].owner_ref == owner_node:
			zones.remove_at(i)
		i -= 1


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


func slam(pos: Vector2, r: float, damage: float, windup: float, owner_node: Variant) -> void:
	_zone("slam", pos, r, windup, damage, owner_node)


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


## 只是预警圈（比如冲击波起手），落地时什么都不做。
func warn_ring(pos: Vector2, r: float, windup: float, owner_node: Variant) -> void:
	_zone("warn", pos, r, windup, 0.0, owner_node)


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
	return null


func _physics_process(dt: float) -> void:
	_dot_note -= dt
	var i := zones.size() - 1
	while i >= 0:
		var z := zones[i]
		z.t -= dt
		if z.t <= 0.0:
			zones.remove_at(i)
			_land(z)
		i -= 1
	i = lanes.size() - 1
	while i >= 0:
		lanes[i].t -= dt
		if lanes[i].t <= 0.0:
			lanes.remove_at(i)
		i -= 1
	_update_clouds(dt)
	_update_shocks(dt)
	queue_redraw()
	_top.queue_redraw()


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


func _draw() -> void:
	for c in clouds:
		_draw_cloud(c)
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
	var ratio := 1.0 - clampf(z.t / z.dur, 0.0, 1.0)
	var at := z.pos.round()
	var edge := Color("#ff3020")
	var fill := Color(1.0, 0.15, 0.1, 0.1 + ratio * 0.2)
	match z.kind:
		"spawn":
			edge = Color("#c070ff")
			fill = Color(0.7, 0.3, 1.0, 0.1 + ratio * 0.2)
		"fog":
			fill = Color(0.5, 0.9, 0.2, 0.1 + ratio * 0.25)
		"acid", "bomb":
			fill = Color(0.6, 0.9, 0.2, 0.12 + ratio * 0.22)
	if ratio > 0.7 and int(z.t * 18.0) % 2 == 0:
		edge = Color("#fff0c0")
	draw_circle(at, z.r, fill)
	draw_circle(at, z.r * ratio, Color(fill.r, fill.g, fill.b, fill.a + 0.15))
	draw_arc(at, z.r, 0.0, TAU, maxi(20, int(z.r)), edge, 1.0)


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
	for z in zones:
		if z.kind != "rock" and z.kind != "bomb" and z.kind != "acid":
			continue
		var ratio := 1.0 - clampf(z.t / z.dur, 0.0, 1.0)
		var at := _falling_pos(z, ratio)
		match z.kind:
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


func _falling_pos(z: Zone, ratio: float) -> Vector2:
	if z.from != null:
		# 抛物线：从 Boss 手里飞过来
		var from: Vector2 = z.from
		return (from.lerp(z.pos, ratio) + Vector2(0, -sin(ratio * PI) * 46.0)).round()
	return (z.pos + Vector2(0, -FALL_H * (1.0 - ratio * ratio))).round()
