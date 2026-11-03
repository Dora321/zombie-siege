extends Node2D
## 特种武器和道具：激光、火焰、榴弹、电弧、回旋镖、投掷物、诱饵、核弹。
## 和 bullet_system 一样用数组集中模拟、集中绘制。

## 投掷物和榴弹在“手的高度”瞄准，判定地形时投影回地面。
const GROUND_OFFSET := Vector2(0, 7)
const MAX_FIRES := 32
const FIRE_TICK := 0.2
const FIRE_DPS := 14.0
const FIRE_TIME := 2.4
const FIRE_R := 11.0
const FUSE := {"frag": 0.55, "sticky": 1.5, "flash": 0.35}
const STICK_R := 20.0
const DECOY_HP := 160.0
const NUKE_SPEED := 720.0
const NUKE_END_R := 1250.0
const NUKE_BOSS_HIT := 0.35
const NUKE_TANK_HIT := 0.6
const STUN_TANK := 0.6
const STUN_BOSS := 0.3
const RANG_LIFE := 6.0
const SHIELD_PIERCE := 0.5

class Lob:
	var from: Vector2
	var to: Vector2
	var t: float
	var dur: float
	var height: float
	var kind: String
	var damage: float
	var radius: float


class Bomb:
	var pos: Vector2
	var target: Variant
	var fuse: float
	var kind: String
	var damage: float
	var radius: float


class Fire:
	var pos: Vector2
	var t: float


class Rang:
	var pos: Vector2
	var dir: Vector2
	var speed: float
	var left: float
	var damage: float
	var knock: float
	var age: float
	var returning: bool
	var hits: Array = []


class Decoy:
	var pos: Vector2
	var hp: float
	var t: float
	var alive := true


class Trace:
	var points: PackedVector2Array
	var t: float
	var dur: float
	var core: Color
	var edge: Color
	var width: float


var game: Node
var map: Node2D
var lobs: Array[Lob] = []
var bombs: Array[Bomb] = []
var fires: Array[Fire] = []
var rangs: Array[Rang] = []
var decoys: Array[Decoy] = []
var traces: Array[Trace] = []
var nuke_r := -1.0

var _nuke_pos := Vector2.ZERO
var _nuke_hit := {}
var _fire_tick := 0.0
var _flame_count := 0


func setup(g: Node, m: Node2D) -> void:
	game = g
	map = m


## 波次结束时打扫战场；回旋镖留着，让它飞回来。
func clear_field() -> void:
	lobs.clear()
	bombs.clear()
	fires.clear()
	for d in decoys:
		d.alive = false
	decoys.clear()


func nuke_active() -> bool:
	return nuke_r >= 0.0


# ---------------------------------------------------------------------------
# 狙击枪：瞬间命中的光束，穿透僵尸和障碍
# ---------------------------------------------------------------------------

func beam(from: Vector2, dir: Vector2, length: float, damage: float, knock: float, pierce: int) -> void:
	game.bullets.shots_fired += 1
	var to := from + dir * length
	var hit_list: Array = []
	for z: Variant in game.zombies_near(from.lerp(to, 0.5), length * 0.5 + 24.0):
		if z.dead or z.burrowed:
			continue
		var c: Vector2 = z.center()
		var along := (c - from).dot(dir)
		if along < 0.0 or along > length:
			continue
		var r: float = z.hit_r
		if (from + dir * along).distance_squared_to(c) <= r * r:
			hit_list.append({"z": z, "d": along})
	hit_list.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	for i in mini(hit_list.size(), pierce + 1):
		var z: Variant = hit_list[i]["z"]
		var at: Vector2 = z.center()
		# 镜面女皇正面：光束被弹回去，后面的也打不到了
		if z.reflect_shot(dir, damage, "beam", true):
			to = from + dir * float(hit_list[i]["d"])
			break
		# 狙击枪能打穿护盾，但伤害减半
		if z.blocks_shot(dir):
			z.shield_hit(damage)
			z.take_damage(damage * SHIELD_PIERCE, dir, knock, true, "beam")
		else:
			z.take_damage(damage, dir, knock, true, "beam")
		game.fx.spark(at)
		game.bullets.shots_hit += 1
		game.on_bullet_hit()
	_detonate_barrels(from, to)
	_add_trace([from, to], 0.14, Color("#fff4e8"), Color("#ff5040"), 2.0)


## 沿线段引爆炸药桶。在 explode 里也是延迟调用，避免一帧内连锁改动建筑表。
func _detonate_barrels(from: Vector2, to: Vector2) -> void:
	var seen := {}
	var steps := int(from.distance_to(to) / 8.0) + 1
	for k in steps + 1:
		var cell: int = map.cell_of(from.lerp(to, float(k) / steps) + GROUND_OFFSET)
		if seen.has(cell):
			continue
		seen[cell] = true
		var s: Variant = map.structure_at(cell)
		if s != null and s.kind == "barrel":
			s.take_damage.call_deferred(1000.0)


# ---------------------------------------------------------------------------
# 火焰喷射器：锥形范围内持续伤害，隔几帧在地上留一团火
# ---------------------------------------------------------------------------

func flame(from: Vector2, dir: Vector2, length: float, cone_deg: float, damage: float) -> void:
	game.bullets.shots_fired += 1
	game.fx.flame(from, dir, length, deg_to_rad(cone_deg))
	var ground: Vector2 = from + GROUND_OFFSET
	var cone_slope := tan(deg_to_rad(cone_deg))
	var hit_any := false
	for z: Variant in game.zombies_near(from, length + 16.0):
		if z.dead:
			continue
		var to: Vector2 = z.center() - from
		var d := to.length()
		if d > length + float(z.hit_r):
			continue
		# 算上身体半径：大块头半边身子在火里也烧得到
		var along := to.dot(dir)
		if d > 4.0 and (along <= 0.0 or absf(to.cross(dir)) > along * cone_slope + float(z.hit_r)):
			continue
		if not map.line_clear(ground, z.position, map.BLOCK_BULLET):
			continue
		z.take_tick(damage)
		z.ignite(1.6)
		hit_any = true
	if hit_any:
		game.bullets.shots_hit += 1
		game.on_bullet_hit()
	_detonate_barrels(from, from + dir * length)
	_flame_count += 1
	if _flame_count % 3 == 0:
		add_fire(ground + dir * length * randf_range(0.55, 1.0) + dir.orthogonal() * randf_range(-8.0, 8.0))


func add_fire(pos: Vector2) -> void:
	if map.blocks(map.cell_of(pos), map.BLOCK_BULLET):
		return
	for f in fires:
		if f.pos.distance_squared_to(pos) < 36.0:
			f.t = FIRE_TIME
			return
	if fires.size() >= MAX_FIRES:
		fires.remove_at(0)
	var f := Fire.new()
	f.pos = pos
	f.t = FIRE_TIME
	fires.append(f)
	game.decals.stamp_pixel_group(pos, Color(0.09, 0.08, 0.08, 0.7), 5)


# ---------------------------------------------------------------------------
# 榴弹和投掷物：同一条抛物线，落地后的表现看 kind
# ---------------------------------------------------------------------------

func lob(kind: String, from: Vector2, to: Vector2, damage: float, radius: float) -> void:
	var l := Lob.new()
	l.from = from
	l.to = to
	l.t = 0.0
	l.dur = clampf(from.distance_to(to) / 210.0, 0.22, 0.85)
	l.height = clampf(from.distance_to(to) * 0.22, 8.0, 34.0)
	l.kind = kind
	l.damage = damage
	l.radius = radius
	lobs.append(l)


func _lob_land(l: Lob) -> void:
	match l.kind:
		"grenade":
			game.explode(l.to, l.damage, l.radius, true, true)
		"decoy":
			var d := Decoy.new()
			d.pos = l.to + GROUND_OFFSET
			d.hp = DECOY_HP
			d.t = l.damage
			decoys.append(d)
			game.fx.dust(d.pos, 6)
			Sfx.play("decoy", -2.0)
		_:
			var b := Bomb.new()
			b.pos = l.to
			b.fuse = float(FUSE[l.kind])
			b.kind = l.kind
			b.damage = l.damage
			b.radius = l.radius
			if l.kind == "sticky":
				b.target = _nearest_zombie(l.to, STICK_R)
				if b.target != null:
					Sfx.play("splat", -6.0)
			bombs.append(b)


func _nearest_zombie(pos: Vector2, radius: float) -> Variant:
	var best: Variant = null
	var best_d := INF
	for z: Variant in game.zombies_near(pos, radius + 16.0):
		if z.dead:
			continue
		var d: float = z.center().distance_to(pos) - float(z.hit_r)
		if d < radius and d < best_d:
			best_d = d
			best = z
	return best


func _bomb_go_off(b: Bomb) -> void:
	if b.kind == "flash":
		_flash_burst(b.pos, b.radius, b.damage)
	else:
		game.explode(b.pos, b.damage, b.radius, true, true)


## 闪光弹：范围内僵尸眩晕，坦克和 Boss 时间打折。b.damage 存的是眩晕秒数。
func _flash_burst(pos: Vector2, radius: float, seconds: float) -> void:
	Sfx.play("flashbang")
	game.add_shake(0.3)
	game.fx.ring(pos, radius, 0.3, Color("#fffbe0"))
	if pos.distance_to(game.camera.position) < 260.0:
		game.hud.screen_flash(0.8, Color("#fffbe0"))
	for z: Variant in game.zombies_near(pos, radius + 12.0):
		if z.dead or z.center().distance_to(pos) > radius + float(z.hit_r):
			continue
		var mult := 1.0
		if z.kind == "tank":
			mult = STUN_TANK
		elif z.is_boss:
			mult = STUN_BOSS
		z.stun(seconds * mult)


# ---------------------------------------------------------------------------
# 电弧枪：打中第一只后在附近连跳
# ---------------------------------------------------------------------------

func arc(from: Vector2, dir: Vector2, length: float, base_damage: float, chain: int, jump: float, knock: float) -> void:
	var damage: float = base_damage * game.events.arc_mult
	game.bullets.shots_fired += 1
	var first: Variant = _arc_first(from, dir, length)
	if first == null:
		_add_bolt([from, from + dir * length * 0.45], 0.08)
		return
	var points: Array[Vector2] = [from]
	var done: Array = []
	var cur: Variant = first
	var dmg := damage
	for i in chain + 1:
		var c: Vector2 = cur.center()
		points.append(c)
		cur.take_damage(dmg, points[points.size() - 2].direction_to(c), knock, true, "arc")
		done.append(cur)
		game.fx.zap(c)
		dmg *= 0.8
		cur = _arc_next(c, jump, done)
		if cur == null:
			break
	game.bullets.shots_hit += 1
	game.on_bullet_hit()
	_add_bolt(points, 0.13)


## 第一跳选准星锥形内最近的；角度偏得越多越不优先。
func _arc_first(from: Vector2, dir: Vector2, length: float) -> Variant:
	var ground := from + GROUND_OFFSET
	var best: Variant = null
	var best_score := INF
	for z: Variant in game.zombies_near(from, length + 16.0):
		if z.dead or z.burrowed:
			continue
		var to: Vector2 = z.center() - from
		var d := to.length()
		if d > length + float(z.hit_r) or d < 0.01:
			continue
		var off := absf(dir.angle_to(to))
		if off > 0.5 or not map.line_clear(ground, z.position, map.BLOCK_BULLET):
			continue
		var score := d + off * 90.0
		if score < best_score:
			best_score = score
			best = z
	return best


func _arc_next(from: Vector2, jump: float, done: Array) -> Variant:
	var best: Variant = null
	var best_d := jump
	for z: Variant in game.zombies_near(from, jump + 8.0):
		if z.dead or done.has(z) or z.burrowed:
			continue
		var d: float = z.center().distance_to(from)
		if d < best_d:
			best_d = d
			best = z
	return best


# ---------------------------------------------------------------------------
# 回旋镖：飞出去再飞回来，每程每只僵尸只打一次；接住才能再扔
# ---------------------------------------------------------------------------

func boomerang(from: Vector2, dir: Vector2, speed: float, length: float, damage: float, knock: float) -> void:
	var r := Rang.new()
	r.pos = from
	r.dir = dir
	r.speed = speed
	r.left = length
	r.damage = damage
	r.knock = knock
	r.age = 0.0
	r.returning = false
	rangs.append(r)
	game.bullets.shots_fired += 1


## 返回 true 表示这把回旋镖已回到手里。
func _step_rang(r: Rang, dt: float) -> bool:
	var p: Variant = game.player
	r.age += dt
	if p == null or not p.alive:
		return true
	var hand: Vector2 = p.position + Vector2(0, -p.HAND_H)
	if r.age > RANG_LIFE:
		p.catch_boomerang()
		return true
	var step := r.speed * dt
	if r.returning:
		var to := hand - r.pos
		if to.length() < maxf(step, 10.0):
			p.catch_boomerang()
			Sfx.play("reload_done", -5.0)
			return true
		r.dir = to.normalized()
		r.pos += r.dir * step * 1.15
	else:
		var nxt := r.pos + r.dir * step
		r.left -= step
		var probe := nxt + GROUND_OFFSET
		var outside: bool = probe.x < 0.0 or probe.y < 0.0 or probe.x >= map.PIXEL_W or probe.y >= map.PIXEL_H
		if outside or map.blocks(map.cell_of(probe), map.BLOCK_BULLET):
			# 撞到障碍折返，炸药桶顺手引爆
			var s: Variant = null if outside else map.structure_at(map.cell_of(probe))
			if s != null and s.kind == "barrel":
				s.take_damage.call_deferred(1000.0)
			game.fx.spark(r.pos)
			r.left = 0.0
		else:
			r.pos = nxt
		if r.left <= 0.0:
			r.returning = true
			r.hits.clear()
	for z: Variant in game.zombies_near(r.pos, 24.0):
		if z.dead or r.hits.has(z) or z.burrowed:
			continue
		var reach: float = float(z.hit_r) + 5.0
		if z.center().distance_squared_to(r.pos) <= reach * reach:
			r.hits.append(z)
			if z.reflect_shot(r.dir, r.damage, "rang", true):
				continue
			if z.blocks_shot(r.dir):
				z.shield_hit(r.damage)
				game.fx.spark(r.pos)
				continue
			z.take_damage(r.damage, r.dir, r.knock, true, "rang")
			game.bullets.shots_hit += 1
			game.on_bullet_hit()
	return false


# ---------------------------------------------------------------------------
# 诱饵：僵尸优先扑向它
# ---------------------------------------------------------------------------

func nearest_decoy(pos: Vector2, radius: float) -> Variant:
	if decoys.is_empty():
		return null
	var best: Variant = null
	var best_d := radius
	for d in decoys:
		var dist: float = d.pos.distance_to(pos)
		if d.alive and dist < best_d:
			best_d = dist
			best = d
	return best


func hurt_decoys(pos: Vector2, damage: float, radius: float) -> void:
	for d in decoys:
		if d.pos.distance_to(pos) < radius:
			d.hp -= damage


# ---------------------------------------------------------------------------
# 核弹：冲击波从玩家向外扩散，一路清场
# ---------------------------------------------------------------------------

func start_nuke(pos: Vector2) -> void:
	nuke_r = 0.0
	_nuke_pos = pos
	_nuke_hit.clear()
	game.bullets.clear_hazards()
	game.hazards.clear()
	game.hud.screen_flash(1.0, Color.WHITE)
	game.add_shake(1.0)
	Sfx.play("nuke")


func _step_nuke(dt: float) -> void:
	nuke_r += NUKE_SPEED * dt
	var r2 := nuke_r * nuke_r
	for z: Variant in game.zombies.duplicate():
		if z.dead or _nuke_hit.has(z) or z.position.distance_squared_to(_nuke_pos) > r2:
			continue
		_nuke_hit[z] = true
		var dir: Vector2 = _nuke_pos.direction_to(z.position)
		if z.is_boss:
			z.take_damage(z.max_hp * NUKE_BOSS_HIT, dir, 200.0, true, "nuke")
		elif z.kind == "tank":
			z.take_damage(z.max_hp * NUKE_TANK_HIT, dir, 200.0, true, "nuke")
		else:
			# 核弹清掉的自爆僵尸不再二次爆炸，分裂体也不再分裂
			z.no_blast = true
			z.take_damage(99999.0, dir, 200.0, false)
	if nuke_r >= NUKE_END_R:
		nuke_r = -1.0
		_nuke_hit.clear()


# ---------------------------------------------------------------------------
# 道具效果。返回 false 表示这次没用上，不扣数量。
# ---------------------------------------------------------------------------

func use_item(id: String, p: Variant) -> bool:
	var spec: Dictionary = GameData.ITEMS[id]
	var power := float(spec["power"])
	var hand: Vector2 = p.position + Vector2(0, -p.HAND_H)
	var over: Vector2 = p.position + Vector2(0, -22)
	match id:
		"medkit":
			if p.hp >= p.max_hp:
				game.fx.text(over, "生命已满", Color("#ff8060"))
				return false
			p.heal(power)
			game.fx.text(over, "生命 +%d" % int(power), Color("#ff8080"))
			Sfx.play("potion")
		"armor":
			if p.armor >= GameData.ARMOR_MAX:
				game.fx.text(over, "护甲已满", Color("#ff8060"))
				return false
			p.armor = minf(p.armor + power, GameData.ARMOR_MAX)
			game.fx.text(over, "护甲 +%d" % int(power), Color("#c8d4e8"))
			Sfx.play("armor")
		"frag", "sticky":
			var mult: float = p.sticky_mult if id == "sticky" else 1.0
			_throw(id, hand, p, power * p.damage_mult() * mult, float(spec["radius"]))
		"flash":
			_throw(id, hand, p, power, float(spec["radius"]))
		"decoy":
			_throw(id, hand, p, power, 0.0)
		"ammo_crate":
			p.refill_all(int(power))
			game.fx.text(over, "弹药补满", Color("#c8e070"))
			Sfx.play("reload_done")
		"inf_ammo":
			p.start_inf_ammo(power)
			game.fx.text(over, "无限弹药", Color("#ffe060"))
			Sfx.play("potion")
		"speed":
			p.buff_speed_t = power
			game.fx.text(over, "移速提升", Color("#70d8ff"))
			Sfx.play("potion")
		"damage":
			p.buff_damage_t = power
			game.fx.text(over, "伤害提升", Color("#ff7060"))
			Sfx.play("potion")
		"nuke":
			if game.nuke_wave == game.wave:
				game.fx.text(over, "本波已用过核弹", Color("#ff8060"))
				return false
			if game.zombies.is_empty():
				game.fx.text(over, "还没有目标", Color("#ff8060"))
				return false
			game.nuke_wave = game.wave
			start_nuke(p.position)
		_:
			return false
	return true


func _throw(kind: String, hand: Vector2, p: Variant, damage: float, radius: float) -> void:
	lob(kind, hand, p.lob_target(GameData.THROW_RANGE), damage, radius)
	Sfx.play("throw")


# ---------------------------------------------------------------------------
# 模拟
# ---------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_update_lobs(dt)
	_update_bombs(dt)
	_update_fires(dt)
	_update_rangs(dt)
	_update_decoys(dt)
	_update_traces(dt)
	if nuke_active():
		_step_nuke(dt)
	queue_redraw()


func _update_lobs(dt: float) -> void:
	var i := lobs.size() - 1
	while i >= 0:
		var l := lobs[i]
		l.t += dt
		if l.t >= l.dur:
			lobs.remove_at(i)
			_lob_land(l)
		i -= 1


func _update_bombs(dt: float) -> void:
	var i := bombs.size() - 1
	while i >= 0:
		var b := bombs[i]
		b.fuse -= dt
		if b.target != null:
			if is_instance_valid(b.target) and not b.target.dead:
				b.pos = b.target.center()
			else:
				b.target = null
		if b.kind == "sticky" and int(b.fuse * 8.0) != int((b.fuse + dt) * 8.0):
			Sfx.play("beep", -9.0)
		if b.fuse <= 0.0:
			bombs.remove_at(i)
			_bomb_go_off(b)
		i -= 1


func _update_fires(dt: float) -> void:
	_fire_tick -= dt
	var tick := _fire_tick <= 0.0
	if tick:
		_fire_tick = FIRE_TICK
	var i := fires.size() - 1
	while i >= 0:
		var f := fires[i]
		f.t -= dt
		if f.t <= 0.0:
			fires.remove_at(i)
		elif tick:
			for z: Variant in game.zombies_near(f.pos, FIRE_R + 16.0):
				if not z.dead and z.position.distance_squared_to(f.pos) < FIRE_R * FIRE_R:
					z.take_tick(FIRE_DPS * FIRE_TICK)
					z.ignite(1.0)
		i -= 1


func _update_rangs(dt: float) -> void:
	var i := rangs.size() - 1
	while i >= 0:
		if _step_rang(rangs[i], dt):
			rangs.remove_at(i)
		i -= 1


func _update_decoys(dt: float) -> void:
	var i := decoys.size() - 1
	while i >= 0:
		var d := decoys[i]
		d.t -= dt
		if d.t <= 0.0 or d.hp <= 0.0:
			d.alive = false
			decoys.remove_at(i)
			game.fx.debris(d.pos + Vector2(0, -8), "barricade")
			Sfx.play("wall_break", -6.0)
		i -= 1


func _update_traces(dt: float) -> void:
	var i := traces.size() - 1
	while i >= 0:
		traces[i].t -= dt
		if traces[i].t <= 0.0:
			traces.remove_at(i)
		i -= 1


func _add_trace(points: Array, dur: float, core: Color, edge: Color, width: float) -> void:
	var t := Trace.new()
	t.points = PackedVector2Array(points)
	t.t = dur
	t.dur = dur
	t.core = core
	t.edge = edge
	t.width = width
	traces.append(t)


## 闪电：把每段折线加上随机抖动。
func _add_bolt(points: Array, dur: float) -> void:
	var jag: Array[Vector2] = []
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var segs := maxi(int(a.distance_to(b) / 9.0), 2)
		var side := a.direction_to(b).orthogonal()
		jag.append(a)
		for k in range(1, segs):
			jag.append(a.lerp(b, float(k) / segs) + side * randf_range(-4.0, 4.0))
	jag.append(points[points.size() - 1])
	_add_trace(jag, dur, Color("#f0faff"), Color("#60a8ff"), 1.0)


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	for f in fires:
		_draw_fire(f)
	for d in decoys:
		_draw_decoy(d)
	_draw_aim_guides()
	for l in lobs:
		_draw_lob(l)
	for b in bombs:
		_draw_bomb(b)
	for r in rangs:
		var tex: Texture2D = Art.boomerang_tex
		draw_set_transform(r.pos.round(), r.age * 18.0)
		draw_texture(tex, -tex.get_size() * 0.5)
	draw_set_transform(Vector2.ZERO)
	for t in traces:
		var c := t.edge
		c.a = t.t / t.dur
		var core := t.core
		core.a = c.a
		draw_polyline(t.points, c, t.width + 1.0)
		draw_polyline(t.points, core, maxf(t.width - 1.0, 1.0))
	if nuke_active():
		var fade := 1.0 - nuke_r / NUKE_END_R
		draw_arc(_nuke_pos, nuke_r, 0.0, TAU, 72, Color(1.0, 0.95, 0.75, fade), 5.0)
		draw_arc(_nuke_pos, nuke_r * 0.92, 0.0, TAU, 72, Color(1.0, 0.55, 0.2, fade * 0.7), 3.0)


## 狙击枪的激光瞄准线和榴弹的落点圈。
func _draw_aim_guides() -> void:
	var p: Variant = game.player
	if p == null or not p.alive or not game.player_can_act():
		return
	var s: Dictionary = p.current_stats()
	match String(s.get("mode", "")):
		"beam":
			var from: Vector2 = p.muzzle_pos()
			var ready: bool = p.cooldown <= 0.0 and p.reload_t <= 0.0
			var c := Color(1.0, 0.2, 0.15, 0.55 if ready else 0.22)
			draw_line(from, from + p.aim * float(s["range"]), c, 1.0)
			var tip: Vector2 = (from + p.aim * minf(from.distance_to(p.aim_point), float(s["range"]))).round()
			draw_rect(Rect2(tip - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 0.3, 0.2, c.a + 0.3))
		"lob":
			var at: Vector2 = p.lob_target(float(s["range"]))
			draw_arc(at.round(), float(s["radius"]), 0.0, TAU, 28, Color(1.0, 0.8, 0.3, 0.45), 1.0)


func _draw_fire(f: Fire) -> void:
	var fade := clampf(f.t, 0.0, 1.0)
	draw_circle(f.pos.round(), FIRE_R * 0.8, Color(0.9, 0.3, 0.05, 0.16 * fade))
	var frame := int(f.t * 12.0)
	for k in 5:
		var a := float(k) * 2.4 + f.pos.x
		var at: Vector2 = f.pos + Vector2(cos(a), sin(a) * 0.6) * FIRE_R * 0.7
		var h := 2 + (frame + k) % 3
		draw_rect(Rect2(at.round() - Vector2(0, h), Vector2(2, h)), Color("#ff9030") if k % 2 == 0 else Color("#ffd050"))
		draw_rect(Rect2(at.round() - Vector2(0, h + 1), Vector2(1, 1)), Color("#fff0a0"))


func _draw_decoy(d: Decoy) -> void:
	var tex: Texture2D = Art.decoy_tex
	var wobble := 1.0 if int(d.t * 6.0) % 2 == 0 else -1.0
	draw_texture(tex, (d.pos + Vector2(wobble - tex.get_width() * 0.5, -tex.get_height() + 1.0)).round())
	# 喇叭声波
	var pulse := fmod(d.t, 0.6) / 0.6
	draw_arc((d.pos + Vector2(0, -10)).round(), 6.0 + (1.0 - pulse) * 14.0, 0.0, TAU, 16, Color(1.0, 0.85, 0.3, pulse * 0.6), 1.0)


func _draw_lob(l: Lob) -> void:
	var t := l.t / l.dur
	var ground := l.from.lerp(l.to, t)
	var at: Vector2 = (ground + Vector2(0, -sin(t * PI) * l.height)).round()
	draw_rect(Rect2(ground.round() + Vector2(-1, 7), Vector2(3, 1)), Color(0, 0, 0, 0.35))
	var color: Color
	match l.kind:
		"grenade":
			color = Color("#c8c070")
		"sticky":
			color = Color("#70d040")
		"flash":
			color = Color("#f0f0e0")
		"decoy":
			color = Color("#e0a050")
		_:
			color = Color("#6c7a3c")
	draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), Art.OUTLINE)
	draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), color)


func _draw_bomb(b: Bomb) -> void:
	var at := b.pos.round()
	var blink := int(b.fuse * 10.0) % 2 == 0
	match b.kind:
		"sticky":
			draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), Color("#3c7a20"))
			draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), Color("#ff4030") if blink else Color("#a0ff60"))
		"flash":
			draw_rect(Rect2(at - Vector2(1, 1), Vector2(3, 3)), Color.WHITE if blink else Color("#b0b0a8"))
		_:
			draw_rect(Rect2(at - Vector2(2, 1), Vector2(4, 3)), Color("#48522c"))
			draw_rect(Rect2(at - Vector2(0, 2), Vector2(1, 1)), Color("#ff5030") if blink else Color("#f0d050"))
