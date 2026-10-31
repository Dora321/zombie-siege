extends Node2D
## 子弹、毒液弹和酸液池。全部用数组管理并集中绘制，比一颗子弹一个节点省很多。

## 子弹在“手的高度”飞行，判定障碍时把坐标投影回地面。
const GROUND_OFFSET := Vector2(0, 7)
const ACID_DPS := 6.0

class Bullet:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var damage: float
	var knock: float
	var pierce: int
	var color: Color
	var from_player: bool
	var chill := 0.0
	var hits: Array = []


class Spit:
	var from: Vector2
	var to: Vector2
	var t: float
	var dur: float
	var damage: float


class Pool:
	var pos: Vector2
	var r: float
	var t: float


var game: Node
var map: Node2D
var bullets: Array[Bullet] = []
var spits: Array[Spit] = []
var pools: Array[Pool] = []
var shots_fired := 0
var shots_hit := 0


func setup(g: Node, m: Node2D) -> void:
	game = g
	map = m


func fire(pos: Vector2, vel: Vector2, damage: float, knock: float, life: float, pierce: int, color: Color, from_player: bool) -> Bullet:
	var b := Bullet.new()
	b.pos = pos
	b.vel = vel
	b.damage = damage
	b.knock = knock
	b.life = life
	b.pierce = pierce
	b.color = color
	b.from_player = from_player
	bullets.append(b)
	if from_player:
		shots_fired += 1
	return b


func spit(from: Vector2, to: Vector2, damage: float) -> void:
	var s := Spit.new()
	s.from = from
	s.to = to
	s.t = 0.0
	s.dur = clampf(from.distance_to(to) / 150.0, 0.3, 1.1)
	s.damage = damage
	spits.append(s)


func _physics_process(dt: float) -> void:
	_update_bullets(dt)
	_update_spits(dt)
	_update_pools(dt)
	queue_redraw()


func _update_bullets(dt: float) -> void:
	var i := bullets.size() - 1
	while i >= 0:
		var b := bullets[i]
		if not _step_bullet(b, dt):
			bullets[i] = bullets[bullets.size() - 1]
			bullets.pop_back()
		i -= 1


## 返回 false 表示子弹消失。
func _step_bullet(b: Bullet, dt: float) -> bool:
	b.life -= dt
	if b.life <= 0.0:
		return false
	var end: Vector2 = b.pos + b.vel * dt
	# 地形：两段采样，防止穿过树木和炸药桶
	for k in 2:
		var probe: Vector2 = b.pos.lerp(end, (k + 1) * 0.5) + GROUND_OFFSET
		if probe.x < 0.0 or probe.y < 0.0 or probe.x >= map.PIXEL_W or probe.y >= map.PIXEL_H:
			return false
		var cell: int = map.cell_of(probe)
		if map.blocks(cell, map.BLOCK_BULLET):
			var s: Variant = map.structure_at(cell)
			if s != null and b.from_player:
				s.take_damage(b.damage)
			game.fx.spark(b.pos.lerp(end, (k + 1) * 0.5))
			return false
	# 僵尸：线段对圆
	var seg := end - b.pos
	var seg_len := seg.length()
	var mid: Vector2 = b.pos + seg * 0.5
	var best: Variant = null
	var best_t := 2.0
	for z: Variant in game.zombies_near(mid, seg_len * 0.5 + 24.0):
		if z.dead or b.hits.has(z):
			continue
		var c: Vector2 = z.center()
		var t := clampf((c - b.pos).dot(seg) / maxf(seg_len * seg_len, 0.001), 0.0, 1.0)
		var closest: Vector2 = b.pos + seg * t
		var r: float = z.hit_r
		if closest.distance_squared_to(c) <= r * r and t < best_t:
			best_t = t
			best = z
	if best != null:
		var dir := b.vel.normalized()
		var damage: float = b.damage
		# 护盾兵正面：子弹停在盾上，只磨耐久
		if best.blocks_shot(dir):
			best.shield_hit(damage)
			game.fx.spark(best.center() - dir * float(best.hit_r))
			return false
		# 炮塔打被冻僵尸有额外加成，鼓励玩家先控场再让炮塔收割
		if not b.from_player:
			damage *= best.vulnerability()
		best.take_damage(damage, dir, b.knock)
		if b.chill > 0.0:
			best.apply_chill(b.chill)
			game.fx.frost(best.center())
		if b.from_player:
			shots_hit += 1
		game.on_bullet_hit()
		b.pierce -= 1
		if b.pierce < 0:
			return false
		b.hits.append(best)
	b.pos = end
	return true


func _update_spits(dt: float) -> void:
	var i := spits.size() - 1
	while i >= 0:
		var s := spits[i]
		s.t += dt
		if s.t >= s.dur:
			_spit_land(s)
			spits[i] = spits[spits.size() - 1]
			spits.pop_back()
		i -= 1


func _spit_land(s: Spit) -> void:
	game.fx.acid_burst(s.to)
	game.decals.stamp(Art.acid_splat, s.to)
	Sfx.play("splat", -8.0)
	var p := Pool.new()
	p.pos = s.to
	p.r = 12.0
	p.t = 2.8
	pools.append(p)
	var player: Variant = game.player
	if player != null and player.alive and player.position.distance_to(s.to) < 14.0:
		player.take_damage(s.damage, s.to)
	game.ordnance.hurt_decoys(s.to, s.damage, 14.0)
	var cell: int = map.cell_of(s.to)
	var target: Variant = map.structure_at(cell)
	if target != null and map.blocks(cell, map.BLOCK_ZOMBIE):
		target.take_damage(s.damage * 1.5)


func _update_pools(dt: float) -> void:
	var player: Variant = game.player
	var i := pools.size() - 1
	while i >= 0:
		var p := pools[i]
		p.t -= dt * game.events.pool_decay
		if p.t <= 0.0:
			pools[i] = pools[pools.size() - 1]
			pools.pop_back()
		elif player != null and player.alive and player.position.distance_squared_to(p.pos) < p.r * p.r:
			player.take_dot(ACID_DPS * dt)
		i -= 1


func add_pool(pos: Vector2, r: float, seconds: float) -> void:
	var p := Pool.new()
	p.pos = pos
	p.r = r
	p.t = seconds
	pools.append(p)


func clear_hazards() -> void:
	spits.clear()
	pools.clear()


func _draw() -> void:
	for p in pools:
		var frame := int(p.t * 7.0)
		var alpha := clampf(p.t, 0.0, 1.0) * 0.5
		draw_circle(p.pos.round(), p.r * 0.75, Color(0.47, 0.8, 0.2, alpha * 0.55))
		for k in 3:
			var a := (frame + k * 3) * 1.7
			var at: Vector2 = p.pos + Vector2(cos(a), sin(a) * 0.7) * p.r * 0.6
			draw_rect(Rect2(at.round(), Vector2(1, 1)), Color(0.8, 1.0, 0.4, alpha * 1.6))
	for b in bullets:
		var dir: Vector2 = b.vel.normalized()
		var head: Vector2 = b.pos.round()
		var trail := dir * 5.0
		draw_line(head - trail, head, Color(b.color.r, b.color.g, b.color.b, 0.55), 1.0)
		draw_rect(Rect2(head - Vector2(1, 1), Vector2(2, 2)), b.color)
	for s in spits:
		var t := s.t / s.dur
		var ground: Vector2 = s.from.lerp(s.to, t)
		var h := sin(t * PI) * 22.0
		draw_rect(Rect2(ground.round() + Vector2(-1, 0), Vector2(3, 1)), Color(0, 0, 0, 0.35))
		var at := (ground + Vector2(0, -h)).round()
		draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), Color("#a8e040"))
		draw_rect(Rect2(at - Vector2(1, 2), Vector2(2, 1)), Color("#e8ff90"))
		draw_rect(Rect2(at - dir_of(s) * 4.0, Vector2(2, 2)), Color("#70a828"))


func dir_of(s: Spit) -> Vector2:
	return s.from.direction_to(s.to)
