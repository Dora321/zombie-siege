extends RefCounted
## 精英僵尸：潜伏者、护盾兵、分裂体、召唤者、尖叫者、气球僵尸。数值都在 GameData.ZOMBIES。


## 潜伏者：半透明摸过来，贴近后现身蓄力，再猛扑一口。被打中会暴露。
class Stalker extends "res://scripts/game/zombie_brain.gd":
	const REVEAL_R := 50.0
	const WARN_T := 0.42
	const POUNCE_T := 0.3
	const OPEN_T := 2.4
	const POUNCE_SPEED := 4.2
	enum {HIDE, WARN, POUNCE, OPEN}

	var state := HIDE
	var _t := 0.0
	var _dir := Vector2.RIGHT

	func setup(z: Variant) -> void:
		z.modulate.a = 0.16

	func cloaked() -> bool:
		return state == HIDE

	func on_hit(z: Variant) -> void:
		if state == HIDE:
			_expose(z, OPEN, OPEN_T)

	func on_stun(z: Variant) -> void:
		z._speed_mult = 1.0
		if state != HIDE:
			_expose(z, OPEN, OPEN_T)

	func _expose(z: Variant, next: int, seconds: float) -> void:
		state = next
		_t = seconds
		z._pose = -1
		z.modulate.a = 1.0
		z._speed_mult = 1.0
		z.idle_anim = 0.0
		if not z.dead:
			Sfx.play("stalker_hiss", -3.0, 0.1)
			z.game.fx.dust(z.position, 5)

	func decide(z: Variant, dt: float, player_ok: bool) -> Variant:
		_t -= dt
		match state:
			HIDE:
				# 空气里有一点扭曲，留心还是看得出来
				z.modulate.a = 0.12 + (sin(_t * 5.0 + z._phase) * 0.5 + 0.5) * 0.1
				if player_ok:
					var p: Variant = z.game.player
					if z.position.distance_to(p.position) < REVEAL_R and z.map.line_clear(z.position, p.position, z.map.BLOCK_ZOMBIE):
						_expose(z, WARN, WARN_T)
						z.flash_warn(WARN_T)
						z._pose = 2
						_dir = z.position.direction_to(p.position)
						return Vector2.ZERO
			WARN:
				if player_ok:
					_dir = z.position.direction_to(z.game.player.position)
				if _t <= 0.0:
					state = POUNCE
					_t = POUNCE_T
					z._speed_mult = POUNCE_SPEED
					z._pose = -1
					z.game.fx.dust(z.position, 6)
				return _dir * 0.01
			POUNCE:
				if player_ok and z.position.distance_to(z.game.player.position) < z.hit_r + 9.0:
					z.game.player.take_damage(z._damage, z.position)
					Sfx.play("stalker_hiss", 0.0, 0.2)
					_t = 0.0
				if _t <= 0.0:
					z._speed_mult = 1.0
					state = OPEN
					_t = OPEN_T
					z._attack_t = 0.7
					return Vector2.ZERO
				return _dir
			OPEN:
				if _t <= 0.0:
					# 玩家还贴着就不隐身了，只有拉开距离才重新潜伏
					if player_ok and z.position.distance_to(z.game.player.position) < REVEAL_R * 1.6:
						_t = 0.8
					else:
						state = HIDE
						Sfx.play("stalker_hiss", -12.0, 0.2)
		return null


## 护盾兵：盾慢慢转向玩家，正面子弹全挡（盾有耐久）。绕后、爆炸、火焰、电弧、眩晕都能克制。
class Shielder extends "res://scripts/game/zombie_brain.gd":
	const TURN := 1.9
	const FRONT := -0.28

	var face := Vector2.DOWN
	var up := true
	var shield_hp := 0.0
	var _flash_t := 0.0

	func setup(z: Variant) -> void:
		redraw = true
		shield_hp = float(z._stat["shield"]) * GameData.hp_scale(z.game.wave)

	func decide(z: Variant, dt: float, player_ok: bool) -> Variant:
		_flash_t -= dt
		var to_base: Vector2 = z.position.direction_to(z.game.base.position)
		var want: Vector2 = to_base
		if player_ok and z.position.distance_to(z.game.player.position) < 180.0:
			want = z.position.direction_to(z.game.player.position)
		face = face.rotated(clampf(face.angle_to(want), -TURN * dt, TURN * dt))
		return null

	func blocks(z: Variant, dir: Vector2) -> bool:
		return up and not z.incapacitated() and dir.dot(face) < FRONT

	## 举着盾还挨了打：绕后或盾放下了的直射，或者不看朝向的爆炸、火焰、电弧。狙击穿盾的半伤不算。
	func weak_hit(z: Variant, src: String, dir: Vector2) -> bool:
		if not up:
			return false
		if src == "blast" or src == "tick" or src == "arc":
			return true
		return (src == "bullet" or src == "buckshot" or src == "beam" or src == "rang") and not blocks(z, dir)

	func shield_hit(z: Variant, amount: float) -> void:
		if not up:
			return
		shield_hp -= amount
		_flash_t = 0.07
		Sfx.play("shield_block", -5.0, 0.12)
		if shield_hp <= 0.0:
			up = false
			z._stagger_t = 0.6
			z.game.fx.debris(z.center() + face * 8.0, "wall")
			z.game.fx.text(z.position + Vector2(0, -28), "盾碎了", Color("#a0d8ff"))
			Sfx.play("shield_break", -2.0)

	func draw(z: Variant) -> void:
		if not up:
			return
		var side := face.orthogonal()
		var mid: Vector2 = Vector2(0, -z.center_h) + face * (z.hit_r + 2.0)
		# 被晕或冻住时盾垂到地上，这时候挡不了子弹
		if z.incapacitated():
			mid += Vector2(0, 6)
		var plate := Color("#f0f8ff") if _flash_t > 0.0 else Color("#7c8ca8")
		var edge := Color("#28303c")
		for k in range(-7, 8):
			var at: Vector2 = (mid + side * k).round()
			z.draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), edge)
		for k in range(-6, 7):
			var at: Vector2 = (mid + side * k).round()
			z.draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), plate)
		# 耐久越低，盾上的裂痕越多
		var ratio: float = shield_hp / (float(z._stat["shield"]) * GameData.hp_scale(z.game.wave))
		var crack := Color("#28303c")
		if ratio < 0.66:
			z.draw_rect(Rect2((mid + side * 3.0).round(), Vector2(1, 1)), crack)
		if ratio < 0.33:
			z.draw_rect(Rect2((mid - side * 3.0).round(), Vector2(1, 1)), crack)
			z.draw_rect(Rect2(mid.round(), Vector2(1, 1)), crack)
		z.draw_rect(Rect2((mid + side * 5.0).round(), Vector2(1, 1)), Color("#e0b830"))
		z.draw_rect(Rect2((mid - side * 5.0).round(), Vector2(1, 1)), Color("#e0b830"))


## 分裂体：死后裂成几只跑得飞快的小怪。核弹和脚本清场不触发。
class Splitter extends "res://scripts/game/zombie_brain.gd":
	func on_die(z: Variant) -> void:
		if z.no_blast:
			return
		Sfx.play("split", 0.0, 0.1)
		z.game.fx.acid_burst(z.position)
		var n: int = randi_range(2, int(z._stat["split"]))
		for i in n:
			var a := TAU * i / n + randf() * 0.6
			var at: Vector2 = z.position + Vector2.from_angle(a) * 8.0
			var kid: Variant = z.game.spawn_minion("splitling", at, z.master)
			if kid != null:
				kid._knock = Vector2.from_angle(a) * 120.0


## 召唤者：站得远远的吟唱，把小怪直接叫到玩家身边。杀了它小怪一起散。
class Summoner extends "res://scripts/game/zombie_brain.gd":
	const CAST_T := 1.1
	const CAST_CD := 5.5
	const CAST_RANGE := 240.0
	const KEEP_AWAY := 90.0
	const STAND_OFF := 150.0
	const MAX_CASTS := 7
	const CAP := 4

	var casts := 0
	var _cd := 2.0
	var _cast_t := -1.0

	func setup(_z: Variant) -> void:
		redraw = true

	func on_stun(z: Variant) -> void:
		_cast_t = -1.0
		z._pose = -1

	func decide(z: Variant, dt: float, player_ok: bool) -> Variant:
		_cd -= dt
		if _cast_t >= 0.0:
			_cast_t -= dt
			z.idle_anim = 7.0
			if _cast_t < 0.0:
				z.idle_anim = 0.0
				_finish_cast(z, player_ok)
			return Vector2.ZERO
		if not player_ok:
			return null
		var p: Variant = z.game.player
		var d: float = z.position.distance_to(p.position)
		var seen: bool = z.map.line_clear(z.position, p.position, z.map.BLOCK_ZOMBIE)
		if _cd <= 0.0 and d < CAST_RANGE and casts < MAX_CASTS and _minions(z) < CAP:
			_cast_t = CAST_T
			casts += 1
			z.flash_warn(CAST_T)
			Sfx.play("summon", -2.0, 0.08)
			z.game.fx.ring(z.center(), 26.0, CAST_T, Color("#c070ff"))
			return Vector2.ZERO
		if seen and d < KEEP_AWAY:
			return p.position.direction_to(z.position)
		if seen and d < STAND_OFF:
			return Vector2.ZERO
		return null

	func _minions(z: Variant) -> int:
		var n := 0
		for other: Variant in z.game.zombies:
			if other.master == z:
				n += 1
		return n

	func _finish_cast(z: Variant, player_ok: bool) -> void:
		_cd = CAST_CD
		if not player_ok:
			return
		var p: Variant = z.game.player
		for i in 2:
			var a := randf() * TAU
			var at: Vector2 = p.position + Vector2.from_angle(a) * randf_range(38.0, 58.0)
			z.game.hazards.spawn_circle("imp", at, z, 0.7)

	func draw(z: Variant) -> void:
		if _cast_t < 0.0:
			return
		var ratio := 1.0 - _cast_t / CAST_T
		for k in 4:
			var a := ratio * 9.0 + k * TAU / 4.0
			var at: Vector2 = Vector2(cos(a), sin(a) * 0.5) * (12.0 - ratio * 5.0) + Vector2(0, -z.center_h)
			z.draw_rect(Rect2(at.round(), Vector2(2, 2)), Color("#e0a0ff"))


## 尖叫者：看见玩家或走近基地就站定蓄力，一声尖叫让周围僵尸加速冲锋。
class Screamer extends "res://scripts/game/zombie_brain.gd":
	const WARN_T := 0.95
	const CD := 8.5
	const SIGHT := 150.0
	const BASE_SIGHT := 110.0
	const RADIUS := 150.0
	const RALLY_T := 4.0

	var screams := 0
	var _cd := 1.5
	var _warn := -1.0

	func on_stun(z: Variant) -> void:
		_warn = -1.0
		z._pose = -1

	func decide(z: Variant, dt: float, player_ok: bool) -> Variant:
		_cd -= dt
		if _warn >= 0.0:
			_warn -= dt
			z._pose = 2
			# 蓄力时浑身发抖
			z._lunge = Vector2(randf_range(-1.0, 1.0), 0.0)
			if _warn < 0.0:
				z._pose = -1
				_scream(z)
			return Vector2.ZERO
		if _cd > 0.0:
			return null
		var near_player: bool = player_ok and z.position.distance_to(z.game.player.position) < SIGHT and z.map.line_clear(z.position, z.game.player.position, z.map.BLOCK_ZOMBIE)
		if near_player or z.position.distance_to(z.game.base.position) < BASE_SIGHT:
			_warn = WARN_T
			z.flash_warn(WARN_T)
			z.game.fx.ring(z.center(), RADIUS, WARN_T, Color("#ff5070"))
			Sfx.play("charge_warn", -6.0)
			return Vector2.ZERO
		return null

	func _scream(z: Variant) -> void:
		_cd = CD
		screams += 1
		Sfx.play("scream", 0.0, 0.08)
		z.game.add_shake(0.3)
		z.game.rally(z.position, RADIUS, RALLY_T, z)
		z.game.fx.ring(z.center(), RADIUS * 0.6, 0.35, Color("#ffb0c0"))


## 气球僵尸：吊在气球下飘，无视围墙，飞到头顶投毒弹。打爆气球会摔下一只半血僵尸。
class Balloon extends "res://scripts/game/zombie_brain.gd":
	const HOVER_R := 16.0
	const BASE_HOVER_R := 40.0
	const DROP_R := 28.0

	var _bob := 0.0
	var _drop_cd := 1.5

	func setup(z: Variant) -> void:
		z.idle_anim = 3.0
		_bob = randf() * TAU

	func on_die(z: Variant) -> void:
		Sfx.play("balloon_pop", 0.0, 0.1)
		z.game.fx.spark(z.center() + Vector2(0, -8))
		if z.no_blast:
			return
		var ground: Vector2 = z.map.unstick(z.position, 5.0, z.map.BLOCK_ZOMBIE)
		var fallen: Variant = z.game.spawn_minion("walker", ground, z.master)
		if fallen != null:
			fallen.hp = fallen.max_hp * 0.5
			fallen.stun(0.6)
			z.game.fx.dust(ground, 8)

	func decide(z: Variant, dt: float, player_ok: bool) -> Variant:
		_bob += dt * 2.4
		z.lift = 11.0 + sin(_bob) * 2.0
		_drop_cd -= dt
		var target: Vector2 = z.game.base.position + Vector2.from_angle(z._phase * 0.7) * BASE_HOVER_R
		var stop := 6.0
		if player_ok and z.position.distance_to(z.game.player.position) < z._aggro:
			target = z.game.player.position
			stop = HOVER_R
		if _drop_cd <= 0.0 and z.position.distance_to(target) < DROP_R + stop:
			_drop_cd = z._attack_cd
			z._attack_t = z._attack_cd
			z.game.hazards.bomb(z.position, z._damage)
			Sfx.play("bomb_whistle", -4.0, 0.08)
		if z.position.distance_to(target) < stop:
			return Vector2.ZERO
		return z.position.direction_to(target)
