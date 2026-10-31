extends Node2D
## 僵尸：顺着流场走向基地，近距离看见玩家就扑过去，被建筑挡住就啃。

const BOX_R := 5.0

var game: Node
var map: Node2D
var kind := "walker"
var hp := 1.0
var max_hp := 1.0
var dead := false
var hit_r := 6.0
var center_h := 7.0
## 核弹清场时置位，死后不再二次爆炸。
var no_blast := false

var _speed := 30.0
var _damage := 5.0
var _attack_cd := 1.0
var _knock_res := 0.0
var _aggro := 80.0
var _spit_range := 0.0
var _stat: Dictionary = {}

var _knock := Vector2.ZERO
var _sep := Vector2.ZERO
var _attack_t := 0.0
var _think_t := 0.0
var _flash_t := 0.0
var _stagger_t := 0.0
var _lunge := Vector2.ZERO
var _chasing := false
var _dir := 0
var _dir_hold := 0.0
var _walk := 0.0
var _frame_key := -1
var _phase := 0
var _stuck_t := 0.0
var _recenter_t := 0.0

# 自爆僵尸
var _fuse := -1.0
# Boss 冲锋
var _charge_cd := 6.0
var _charge_t := 0.0
var _charge_dir := Vector2.ZERO
# 喷吐僵尸的蓄力
var _windup := -1.0
var _spit_target := Vector2.ZERO
# 状态异常：减速、冰冻、眩晕、燃烧
var _chill := 0.0
var _chill_t := 0.0
var _frozen_t := 0.0
var _stun_t := 0.0
var _burn_t := 0.0
var _dot_shown := 0.0
var _ember_t := 0.0
var _status_key := 0
# 诱饵
var _lure: Variant = null

@onready var body: Sprite2D = $Body
@onready var shadow: Sprite2D = $Shadow


func setup(g: Node, m: Node2D, zombie_kind: String, pos: Vector2, wave: int) -> void:
	game = g
	map = m
	kind = zombie_kind
	position = pos
	_stat = GameData.ZOMBIES[kind]
	max_hp = float(_stat["hp"]) * GameData.hp_scale(wave)
	hp = max_hp
	_speed = float(_stat["speed"]) * randf_range(0.88, 1.12) * (1.0 + (wave - 1) * 0.012)
	_damage = float(_stat["damage"]) * GameData.damage_scale(wave)
	_attack_cd = float(_stat["attack_cd"])
	_knock_res = float(_stat["knock_res"])
	_aggro = float(_stat["aggro"])
	_spit_range = float(_stat.get("range", 0.0))
	hit_r = float(_stat["hit_r"])
	center_h = float(_stat["center"])
	_phase = randi() % 64
	_think_t = randf() * 0.2
	_attack_t = randf() * 0.4
	var size := Art.char_size(kind)
	body.offset = Vector2(-size.x / 2, -size.y + 1)
	match kind:
		"tank":
			shadow.texture = Art.shadow_medium
		"boss":
			shadow.texture = Art.shadow_big
		_:
			shadow.texture = Art.shadow_small
	shadow.position = Vector2(0, -1)
	_apply_frame()


func center() -> Vector2:
	return position + Vector2(0, -center_h)


func _physics_process(dt: float) -> void:
	if dead:
		return
	_attack_t -= dt
	_flash_t -= dt
	_stagger_t -= dt
	_think_t -= dt
	_lunge = _lunge.lerp(Vector2.ZERO, clampf(16.0 * dt, 0.0, 1.0))
	_tick_status(dt)
	if dead:
		return
	if _frozen_t > 0.0 or _stun_t > 0.0:
		# 冻住和眩晕时站着不动，只吃击退
		position = map.move_box(position, _knock * dt, BOX_R, map.BLOCK_ZOMBIE)
		_knock = _knock.lerp(Vector2.ZERO, clampf(9.0 * dt, 0.0, 1.0))
		_animate(dt, Vector2.ZERO, 0.0)
		return
	if _think_t <= 0.0:
		_think_t = randf_range(0.16, 0.3)
		_think()
	if (Engine.get_physics_frames() + _phase) % 3 == 0:
		_update_separation()

	var move_dir := _decide(dt)
	var spd := _speed
	if _stagger_t > 0.0:
		spd *= 0.45
	if _chill_t > 0.0:
		spd *= GameData.CHILL_SLOW_BOSS if kind == "boss" else GameData.CHILL_SLOW
	if _charge_t > 0.0:
		spd = _speed * 4.2
	var motion: Vector2 = move_dir * spd + _sep * 34.0 + _knock
	var before := position
	position = map.move_box(position, motion * dt, BOX_R, map.BLOCK_ZOMBIE)
	_knock = _knock.lerp(Vector2.ZERO, clampf(9.0 * dt, 0.0, 1.0))
	var moved := (position - before).length()
	_check_stuck(dt, move_dir, moved, spd)
	_animate(dt, move_dir, moved)

	if _fuse >= 0.0:
		_fuse -= dt
		if _fuse < 0.0:
			_explode_now()


## 防软锁：连续走不动时先回到格子中心重走，还不行就直接挪到下一格。
func _check_stuck(dt: float, move_dir: Vector2, moved: float, spd: float) -> void:
	_recenter_t -= dt
	var trying := move_dir.length_squared() > 0.25 and _charge_t <= 0.0
	if trying and moved < spd * dt * 0.25:
		_stuck_t += dt
	else:
		_stuck_t = maxf(_stuck_t - dt * 2.0, 0.0)
	if _stuck_t > 0.4:
		_recenter_t = 2.0
		_chasing = false
	if _stuck_t > 3.0:
		_stuck_t = 0.0
		var nxt: int = map.next_cell[map.cell_of(position)]
		if nxt >= 0 and not map.blocks(nxt, map.BLOCK_ZOMBIE):
			position = map.cell_center(nxt)


func _think() -> void:
	var player: Variant = game.player
	_chasing = false
	_lure = null
	if _recenter_t > 0.0:
		return
	var decoy: Variant = game.ordnance.nearest_decoy(position, float(GameData.ITEMS["decoy"]["radius"]))
	if decoy != null and map.line_clear(position, decoy.pos, map.BLOCK_ZOMBIE):
		_lure = decoy
		return
	if player != null and player.alive:
		var d: float = position.distance_to(player.position)
		if d < _aggro and map.line_clear(position, player.position, map.BLOCK_ZOMBIE):
			_chasing = true


func _update_separation() -> void:
	var push := Vector2.ZERO
	var near: Array = game.zombies_near(position, 15.0)
	for other: Variant in near:
		if other == self:
			continue
		var diff: Vector2 = position - other.position
		var min_d: float = hit_r + other.hit_r - 2.0
		var d2 := diff.length_squared()
		if d2 < min_d * min_d and d2 > 0.01:
			push += diff / sqrt(d2) * (1.0 - sqrt(d2) / min_d)
	_sep = push.limit_length(1.0)


## 决定本帧往哪走，顺带处理攻击；返回单位方向或零向量。
func _decide(dt: float) -> Vector2:
	var player: Variant = game.player
	var player_ok: bool = player != null and player.alive

	if _fuse >= 0.0:
		return Vector2.ZERO

	# 喷吐蓄力中站定
	if _windup >= 0.0:
		_windup -= dt
		if _windup < 0.0:
			game.bullets.spit(center(), _spit_target, _damage)
			Sfx.play("spit", -3.0)
			_lunge = (_spit_target - position).normalized() * 3.0
		return Vector2.ZERO

	if kind == "boss":
		_charge_cd -= dt
		if _charge_t > 0.0:
			_charge_t -= dt
			if _charge_t <= 0.0 or _charge_impact(player_ok):
				_end_charge()
				return Vector2.ZERO
			return _charge_dir
		if _charge_cd <= 0.0 and player_ok and position.distance_to(player.position) < 220.0:
			_charge_t = 1.1
			_charge_dir = position.direction_to(player.position)
			Sfx.play("boss_roar", -1.0)
			game.add_shake(0.5)
			game.fx.dust(position, 10)
			return _charge_dir

	# 贴身打玩家
	if player_ok:
		var reach: float = hit_r + 9.0
		if position.distance_to(player.position) < reach:
			if kind == "exploder":
				_light_fuse()
				return Vector2.ZERO
			if _attack_t <= 0.0:
				_attack_player(player)
			return position.direction_to(player.position) * 0.2

	if _lure != null and not _lure.alive:
		_lure = null

	# 喷吐僵尸：优先吐诱饵，其次玩家，再其次基地和路上的建筑
	if _spit_range > 0.0 and _attack_t <= 0.0:
		var target: Variant = _pick_spit_target(player_ok)
		if target != null:
			_windup = 0.45
			_spit_target = target
			_attack_t = _attack_cd
			return Vector2.ZERO

	if _lure != null:
		var lure_d: float = position.distance_to(_lure.pos)
		if lure_d < hit_r + 9.0:
			if kind == "exploder":
				_light_fuse()
			elif _attack_t <= 0.0:
				_attack_t = _attack_cd
				_lunge = position.direction_to(_lure.pos) * 5.0
				_lure.hp -= _damage
			return Vector2.ZERO
		if _spit_range > 0.0 and lure_d < _spit_range * 0.7:
			return Vector2.ZERO
		return position.direction_to(_lure.pos)

	if _chasing and player_ok:
		if _spit_range > 0.0 and position.distance_to(player.position) < _spit_range * 0.7:
			return Vector2.ZERO
		return position.direction_to(player.position)

	# 跟着流场走
	var here: int = map.cell_of(position)
	var nxt: int = map.next_cell[here]
	if nxt < 0:
		return position.direction_to(game.base.position)
	if map.blocks(nxt, map.BLOCK_ZOMBIE):
		var blocker: Variant = map.structure_at(nxt)
		var touch: float = map.dist_to_cell(position, nxt)
		if blocker != null and touch <= BOX_R + 3.0:
			if kind == "exploder":
				_light_fuse()
				return Vector2.ZERO
			if _attack_t <= 0.0:
				_attack_structure(blocker, nxt)
			return Vector2.ZERO
	var target_pos: Vector2 = map.cell_center(nxt)
	# 每只僵尸在格子里有点偏移，队形不那么死板（幅度小于走廊余量，不会贴到墙角）
	if _recenter_t <= 0.0:
		target_pos += Vector2((_phase % 5) - 2, ((_phase >> 3) % 5) - 2)
	return position.direction_to(target_pos)


## 冲锋撞到玩家或建筑时结算伤害，返回是否撞上了。
func _charge_impact(player_ok: bool) -> bool:
	if player_ok and position.distance_to(game.player.position) < hit_r + 8.0:
		game.player.take_damage(_damage * 1.5, position)
		return true
	var ahead: int = map.cell_of(position + _charge_dir * (BOX_R + 4.0))
	if map.blocks(ahead, map.BLOCK_ZOMBIE):
		var s: Variant = map.structure_at(ahead)
		if s != null:
			var mult := 1.5 if s.kind == "base" else 4.0
			s.take_damage(_damage * mult, self)
		game.add_shake(0.6)
		game.fx.dust(position + _charge_dir * 8.0, 10)
		Sfx.play("wall_break", -3.0)
		return true
	return false


func _end_charge() -> void:
	_charge_t = 0.0
	_charge_cd = randf_range(6.0, 9.0)
	_attack_t = 0.6


func _pick_spit_target(player_ok: bool) -> Variant:
	if _lure != null and position.distance_to(_lure.pos) < _spit_range:
		return _lure.pos
	if player_ok:
		var p: Vector2 = game.player.position
		if position.distance_to(p) < _spit_range:
			return p + game.player.velocity * 0.45
	var base_pos: Vector2 = game.base.position + Vector2(0, -24)
	if position.distance_to(base_pos) < _spit_range:
		return base_pos
	var here: int = map.cell_of(position)
	var nxt: int = map.next_cell[here]
	if nxt >= 0 and map.blocks(nxt, map.BLOCK_ZOMBIE):
		return map.cell_center(nxt)
	return null


func _attack_player(player: Variant) -> void:
	_attack_t = _attack_cd
	_lunge = position.direction_to(player.position) * 5.0
	player.take_damage(_damage, position)


func _attack_structure(s: Variant, cell: int) -> void:
	_attack_t = _attack_cd
	_lunge = position.direction_to(map.cell_center(cell)) * 4.0
	var mult := 1.0
	if (kind == "tank" or kind == "boss") and s.kind != "base":
		mult = 2.0
	s.take_damage(_damage * mult, self)
	if randf() < 0.07:
		Sfx.play("groan", -14.0, 0.2)


func _light_fuse() -> void:
	if _fuse < 0.0:
		_fuse = 0.5
		Sfx.play("spit", -6.0, 0.3)


func _explode_now() -> void:
	if dead:
		return
	dead = true
	game.remove_zombie(self)
	game.explode(position + Vector2(0, -6), _damage, 48.0, false)
	game.credit_kill(self, false)
	queue_free()


## 冻住和减速时更吃伤害。
func vulnerability() -> float:
	if _frozen_t > 0.0:
		return GameData.FREEZE_VULN
	if _chill_t > 0.0:
		return GameData.CHILL_VULN
	return 1.0


func apply_chill(amount: float) -> void:
	if dead:
		return
	_burn_t = 0.0
	_chill_t = GameData.CHILL_TIME
	_chill += amount
	if _chill >= 1.0 and kind != "boss" and _frozen_t <= 0.0:
		_chill = 0.0
		_frozen_t = GameData.FREEZE_TIME * (0.5 if kind == "tank" else 1.0)
		_fuse = -1.0
		_windup = -1.0
		game.fx.frost(center())
		Sfx.play("cryo", 0.0, 0.2)


func stun(seconds: float) -> void:
	if dead:
		return
	_stun_t = maxf(_stun_t, seconds)
	_windup = -1.0
	if _charge_t > 0.0:
		_end_charge()


func ignite(seconds: float) -> void:
	if dead:
		return
	_burn_t = maxf(_burn_t, seconds)
	_chill = 0.0
	_chill_t = 0.0
	_frozen_t = 0.0


## 火焰这类高频小伤害：不飘血不出声，攒够才飘一次字。
func take_tick(amount: float) -> void:
	if dead:
		return
	var dealt := amount * vulnerability()
	hp -= dealt
	_dot_shown += dealt
	if _dot_shown >= 10.0:
		game.fx.number(center() + Vector2(randf_range(-3, 3), -6), roundi(_dot_shown), Color("#ff9040"))
		_dot_shown = 0.0
		_flash_t = 0.05
	if hp <= 0.0:
		_die(Vector2.UP)


func _tick_status(dt: float) -> void:
	_chill_t -= dt
	_frozen_t -= dt
	_stun_t -= dt
	if _chill_t <= 0.0:
		_chill = 0.0
	if _burn_t > 0.0:
		_burn_t -= dt
		_ember_t -= dt
		if _ember_t <= 0.0:
			_ember_t = 0.14
			game.fx.ember(center())
		take_tick(GameData.BURN_DPS * dt)
		if dead:
			return
	var key := 0
	if _frozen_t > 0.0:
		key = 1
	elif _stun_t > 0.0:
		key = 2
	elif _burn_t > 0.0:
		key = 3
	elif _chill_t > 0.0:
		key = 4
	if key != _status_key:
		_status_key = key
		body.modulate = [Color.WHITE, Color(0.55, 0.85, 1.7), Color(1.5, 1.45, 0.75), Color(1.6, 0.8, 0.5), Color(0.75, 0.95, 1.35)][key]
		queue_redraw()
	elif key == 2:
		queue_redraw()


## 子弹、爆炸都走这里。
func take_damage(amount: float, dir: Vector2, knock: float, show_number := true) -> void:
	if dead:
		return
	amount *= vulnerability()
	hp -= amount
	_flash_t = 0.07
	_stagger_t = 0.1
	_knock += dir * knock * (1.0 - _knock_res)
	var hit_pos := center()
	game.fx.blood_hit(hit_pos, dir, 3 + int(amount * 0.2), Color(String(_stat["blood"])))
	if show_number:
		game.fx.number(hit_pos + Vector2(randf_range(-3, 3), -6), roundi(amount), Color("#ffe080") if amount < 30.0 else Color("#ffa040"))
	if randf() < 0.3:
		game.decals.stamp_pixel_group(position + dir * randf_range(4, 14), Color("#7c1414"), 4)
	Sfx.play("hit", -8.0)
	if hp <= 0.0:
		_die(dir)


func _die(dir: Vector2) -> void:
	dead = true
	game.remove_zombie(self)
	var size := Art.char_size(kind)
	game.fx.ghost(Art.frame(kind, _dir, 0, true), position + body.offset, body.flip_h, Color.WHITE, 0.07)
	game.fx.gibs(kind, position, dir)
	var splats: Array[Image] = Art.blood_splats_dark
	game.decals.stamp(splats[randi() % splats.size()], position + Vector2(0, -2))
	if size.x >= 24:
		game.decals.stamp(splats[randi() % splats.size()], position + Vector2(randf_range(-10, 10), randf_range(-8, 6)))
	Sfx.play("zombie_die", -4.0 if kind != "boss" else 2.0, 0.12)
	if kind == "exploder" and not no_blast:
		# 打爆自爆僵尸有奖励：范围伤害会波及同类
		game.explode.call_deferred(position + Vector2(0, -6), _damage * 0.7, 42.0, false)
	if kind == "tank" or kind == "boss":
		game.hitstop(0.09 if kind == "tank" else 0.2)
		game.add_shake(0.5 if kind == "tank" else 0.9)
	else:
		game.hitstop(0.022)
	game.credit_kill(self, true)
	queue_free()


## 冰块和眩晕星星画在身体之外，不用跟动画帧打交道。
func _draw() -> void:
	match _status_key:
		1:
			var half := hit_r + 2.0
			var top := -center_h * 2.0 - 1.0
			draw_rect(Rect2(-half, top, half * 2.0, center_h * 2.0 + 2.0), Color(0.6, 0.9, 1.0, 0.35))
			for k: Vector2 in [Vector2(-half, top), Vector2(half - 2.0, top + 3.0), Vector2(-half + 1.0, -3.0), Vector2(half - 3.0, -2.0)]:
				draw_rect(Rect2(k, Vector2(2, 2)), Color("#e0f8ff"))
		2:
			var a := Time.get_ticks_msec() * 0.008
			var y := -center_h * 2.0 - 4.0
			for k in 3:
				var at := Vector2(cos(a + k * 2.1) * hit_r, y + sin(a + k * 2.1) * 2.0).round()
				draw_rect(Rect2(at, Vector2(2, 2)), Color("#fff060"))


func _animate(dt: float, move_dir: Vector2, moved: float) -> void:
	_dir_hold -= dt
	var face := move_dir if move_dir.length_squared() > 0.01 else Vector2.ZERO
	if face != Vector2.ZERO and _dir_hold <= 0.0:
		var nd := Art.DIR_DOWN
		if absf(face.x) > absf(face.y):
			nd = Art.DIR_SIDE
		elif face.y < 0.0:
			nd = Art.DIR_UP
		if nd != _dir:
			_dir = nd
			_dir_hold = 0.14
		if _dir == Art.DIR_SIDE:
			body.flip_h = face.x < 0.0
	_walk += moved * (0.24 if size_is_small() else 0.13)
	body.position = _lunge.round()
	_apply_frame()


func size_is_small() -> bool:
	return kind != "tank" and kind != "boss"


func _apply_frame() -> void:
	var f := int(_walk) % Art.FRAMES
	var white := _flash_t > 0.0
	# 引信和蓄力时高频闪白
	if _fuse >= 0.0 and int(_fuse * 22.0) % 2 == 0:
		white = true
	if _windup >= 0.0 and int(_windup * 20.0) % 2 == 0:
		white = true
	var key := _dir * 100 + f * 10 + (1 if white else 0)
	if key != _frame_key:
		_frame_key = key
		body.texture = Art.frame(kind, _dir, f, white)
