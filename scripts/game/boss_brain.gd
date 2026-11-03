extends "res://scripts/game/zombie_brain.gd"
## Boss：按 GameData.BOSSES 的配置分阶段出招。血量跌到阈值就锁血换阶段，一刀也跳不过去。
## 所有招式都先蓄力亮危险提示，时间到才结算。

const CHANGE_T := 1.8
const CHARGE_T := 1.0
const CHARGE_WARN := 0.8
const SLAM_R := 50.0
const SLAM_REACH := 84.0
const CHARGE_REACH := 240.0
const ROCK_REACH := 260.0
const FAN_REACH := 170.0
const WAVE_REACH := 150.0
const FAR := 260.0
const MINION_CAP := 6
## 连冲被闪光或霰弹打断后的硬直。
const BREAK_STUN := 0.8
const MOVE_WARN := {
	"charge": CHARGE_WARN, "charge2": CHARGE_WARN, "slam": 0.9, "rocks": 0.55, "storm": 0.7, "fog": 0.6,
	"fogring": 0.7, "fan": 0.6, "wave": 0.9, "call": 0.8, "elites": 1.0, "shield": 0.7, "scream": 0.9,
}

var spec: Dictionary
var phases: Array
var phase := 0
var changing_t := 0.0
var shield := 0.0
var shield_max := 1.0
var moves_used := {}

var _gap := 2.2
var _act := ""
var _act_t := 0.0
var _last := ""
var _chain := 0
var _enter := ""
var _guard := 1.0
# 阶段配了 break 时，连冲的蓄力能被打断；_brace 是这次蓄力已经吃到的霰弹击退
var _breakable := false
var _brace := 0.0
var _lane: Variant = null


func setup(z: Variant) -> void:
	redraw = true
	spec = GameData.BOSSES[z.kind]
	phases = spec["phases"]
	_apply_phase(z)


func info() -> Dictionary:
	return {"title": spec["title"], "phase": phase, "count": phases.size(), "name": phases[phase]["name"], "shield": shield / shield_max if shield > 0.0 else 0.0}


## 阶段切换和护盾期间打不动，HUD 和飘字都要用到。
func untouchable() -> bool:
	return changing_t > 0.0


func guarded() -> bool:
	return _guard < 1.0


func _apply_phase(z: Variant) -> void:
	var p: Dictionary = phases[phase]
	z._speed_mult = float(p.get("speed", 1.0))
	z.set_tint(Color(String(p.get("tint", "#ffffff"))))
	_guard = 1.0
	_enter = String(p.get("enter", ""))


func absorb(z: Variant, amount: float) -> float:
	if changing_t > 0.0:
		return 0.0
	if shield > 0.0:
		var soaked := minf(shield, amount)
		shield -= soaked
		amount -= soaked
		if shield <= 0.0:
			shield = 0.0
			z.game.fx.debris(z.center(), "wall")
			z.game.fx.text(z.position + Vector2(0, -z.center_h * 2.0 - 8.0), "护盾破了", Color("#c0ff80"))
			Sfx.play("shield_break", 0.0)
		if amount <= 0.0:
			return 0.0
	amount *= _guard
	if phase + 1 < phases.size():
		var floor_hp: float = float(phases[phase + 1]["at"]) * z.max_hp
		if z.hp - amount <= floor_hp:
			amount = maxf(z.hp - floor_hp, 0.0)
			_begin_change(z)
	return amount


func _begin_change(z: Variant) -> void:
	phase += 1
	changing_t = CHANGE_T
	_act = ""
	_chain = 0
	_breakable = false
	_drop_lane(z)
	z._charge_t = 0.0
	z._pose = -1
	shield = 0.0
	_apply_phase(z)
	z.flash_warn(CHANGE_T)
	z.game.on_boss_phase(z, phases[phase], phase, phases.size())


func on_stun(z: Variant) -> void:
	# 被晕打断蓄力，闪光弹是正经的反制手段
	if _breakable and _act != "":
		_interrupt(z, "闪光")
	_act = ""
	_chain = 0
	z._pose = -1
	_drop_lane(z)


## 霰弹的击退 Boss 几乎不吃，但连冲蓄力时按原始击退累计，攒够就打断。
func on_buckshot(z: Variant, knock: float) -> void:
	if not _breakable or _act == "":
		return
	_brace += knock
	if _brace >= float(phases[phase]["break"]):
		_interrupt(z, "霰弹")
		z.stun(BREAK_STUN)


func _interrupt(z: Variant, by: String) -> void:
	_breakable = false
	z._stun_t = maxf(z._stun_t, BREAK_STUN)
	z.game.fx.text(z.position + Vector2(0, -z.center_h * 2.0 - 8.0), "打断！", Color("#ffe060"))
	Sfx.play("shield_break", 0.0)
	Harness.note("%s 的连冲被%s打断（第 %d 阶段）" % [spec["title"], by, phase + 1])


## 蓄力被取消时，地上的冲撞通道也一起撤掉。
func _drop_lane(z: Variant) -> void:
	if _lane != null:
		z.game.hazards.lanes.erase(_lane)
		_lane = null


func on_die(z: Variant) -> void:
	z.game.dismiss_minions(z)
	z.game.on_boss_down(z)


func decide(z: Variant, dt: float, player_ok: bool) -> Variant:
	if changing_t > 0.0:
		changing_t -= dt
		z._lunge = Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0))
		if changing_t <= 0.0 and _enter != "":
			_begin_move(z, _enter)
		return Vector2.ZERO
	# 号令护甲：叫来的精英还活着，本体就很难打动
	if phases[phase].has("guard"):
		_guard = float(phases[phase]["guard"]) if _minions(z) > 0 else 1.0
	if z._charge_t > 0.0:
		z._charge_t -= dt
		if z._charge_t <= 0.0 or z._charge_impact(player_ok):
			z._end_charge()
			if _chain > 0:
				_chain -= 1
				_begin_move(z, "charge", true)
			return Vector2.ZERO
		return z._charge_dir
	if _act != "":
		_act_t -= dt
		if _act_t <= 0.0:
			var act := _act
			_act = ""
			z._pose = -1
			_fire_move(z, act, player_ok)
			if z._charge_t > 0.0:
				return z._charge_dir
		return Vector2.ZERO
	_gap -= dt
	if _gap <= 0.0:
		var next := _pick(z, player_ok)
		if next == "":
			_gap = 0.35
		else:
			_begin_move(z, next)
			var range_gap: Array = phases[phase]["gap"]
			_gap = randf_range(float(range_gap[0]), float(range_gap[1]))
			return Vector2.ZERO
	# 隔得太远就赶路，不让玩家干等
	var mult := float(phases[phase].get("speed", 1.0))
	if player_ok and z.position.distance_to(z.game.player.position) > FAR:
		mult *= 1.6
	z._speed_mult = mult
	return null


func _minions(z: Variant) -> int:
	var n := 0
	for other: Variant in z.game.zombies:
		if other.master == z:
			n += 1
	return n


## 当前位置能放的招里挑一个，不连续重复。
func _pick(z: Variant, player_ok: bool) -> String:
	var options: Array[String] = []
	var moves: Array = phases[phase]["moves"]
	var d: float = z.position.distance_to(z.game.player.position) if player_ok else INF
	for m: String in moves:
		if _can_use(z, m, d):
			options.append(m)
	if options.size() > 1:
		options.erase(_last)
	if options.is_empty():
		return ""
	return options[randi() % options.size()]


func _can_use(z: Variant, move: String, d: float) -> bool:
	match move:
		"charge", "charge2":
			return d < CHARGE_REACH
		"slam":
			return d < SLAM_REACH
		"rocks", "storm", "fog":
			return d < ROCK_REACH or z.position.distance_to(z.game.base.position) < ROCK_REACH * 0.7
		"fogring":
			return d < ROCK_REACH and z.game.hazards.clouds.size() < 6
		"fan":
			return d < FAN_REACH
		"wave":
			return d < WAVE_REACH
		"call", "elites":
			return _minions(z) < MINION_CAP and z.game.zombies.size() < z.game.MAX_ALIVE
		"shield":
			return shield <= 0.0
		"scream":
			return z.game.zombies.size() > 1
	return false


## 蓄力开始：亮红圈和闪光，招式的落点此时就定了，玩家有时间躲。
## follow 表示这是连冲的第二段蓄力。
func _begin_move(z: Variant, move: String, follow := false) -> void:
	var warn: float = MOVE_WARN[move]
	_act = move
	_act_t = warn
	_last = move
	moves_used[move] = true
	_breakable = phases[phase].has("break") and (move == "charge2" or follow)
	_brace = 0.0
	z.flash_warn(warn)
	z._pose = 2
	var hazards: Variant = z.game.hazards
	match move:
		"charge", "charge2":
			if move == "charge2":
				_chain = 1
			var player: Variant = z.game.player
			z._charge_dir = z.position.direction_to(player.position if player.alive else z.game.base.position)
			_lane = hazards.lane(z.position, z._charge_dir, z.charge_speed() * CHARGE_T, 16.0, warn)
			Sfx.play("charge_warn", 0.0)
		"slam":
			hazards.slam(z.position, SLAM_R * float(spec.get("slam_scale", 1.0)), z._damage * 1.2, warn, z)
			Sfx.play("charge_warn", -2.0)
		"wave":
			hazards.warn_ring(z.position, 34.0, warn, z)
			Sfx.play("charge_warn", 0.0)
		"shield":
			z.game.fx.ring(z.center(), 36.0, warn, Color("#a0ff70"))
			Sfx.play("summon", -2.0)
		"call", "elites":
			z.game.fx.ring(z.center(), 40.0, warn, Color("#c070ff"))
			Sfx.play("summon", 0.0)
		"scream":
			z.game.fx.ring(z.center(), 200.0, warn, Color("#ff5070"))
			Sfx.play("charge_warn", -2.0)
		_:
			Sfx.play("charge_warn", -6.0)


func _aim_point(z: Variant) -> Vector2:
	var player: Variant = z.game.player
	if player.alive and z.position.distance_to(player.position) < ROCK_REACH:
		return player.position
	return z.game.base.position + Vector2(0, -8)


func _fire_move(z: Variant, move: String, player_ok: bool) -> void:
	var game: Variant = z.game
	var hazards: Variant = game.hazards
	var aim := _aim_point(z)
	match move:
		"charge", "charge2":
			z._charge_t = CHARGE_T
			Sfx.play("boss_roar", -1.0)
			game.add_shake(0.5)
			game.fx.dust(z.position, 10)
		"slam":
			z._lunge = Vector2(0, 4)
		"rocks":
			var count := int(phases[phase].get("rocks", 3))
			var lead: Vector2 = game.player.velocity * 0.5 if player_ok else Vector2.ZERO
			for i in count:
				var at: Vector2 = aim + lead + (Vector2.ZERO if i == 0 else Vector2.from_angle(TAU * i / maxf(count - 1, 1.0)) * 34.0)
				hazards.rock(at, z._damage * 0.8, 1.0 + i * 0.12, z.center(), z)
			Sfx.play("throw", 0.0)
		"storm":
			for i in 11:
				var at: Vector2 = aim + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 90.0)
				hazards.rock(at, z._damage * 0.7, 0.8 + i * 0.22, null, z)
			Sfx.play("boss_roar", -3.0)
		"fog":
			var lead: Vector2 = game.player.velocity * 0.8 if player_ok else Vector2.ZERO
			hazards.fog(aim, 32.0, 6.0, z)
			hazards.fog(aim + lead + Vector2(randf_range(-40, 40), randf_range(-30, 30)), 26.0, 6.0, z)
			Sfx.play("fog_hiss", 0.0)
		"fogring":
			for i in 6:
				hazards.fog(z.position + Vector2.from_angle(TAU * i / 6.0) * 78.0, 26.0, 5.0, z)
			Sfx.play("fog_hiss", 0.0)
		"fan":
			var base_a: float = z.position.angle_to_point(aim)
			var reach: float = minf(z.position.distance_to(aim), 170.0)
			for i in 5:
				var a: float = base_a + (i - 2) * 0.3
				game.bullets.spit(z.center(), z.position + Vector2.from_angle(a) * reach, z._damage * 0.5)
			Sfx.play("spit", 0.0)
		"wave":
			hazards.shockwave(z.position, 190.0, 150.0, z._damage * 0.7)
			Sfx.play("slam", 0.0)
			game.add_shake(0.5)
		"call":
			_summon(z, phases[phase]["call"])
		"elites":
			var pool: Array = spec["elites"].duplicate()
			pool.shuffle()
			_summon(z, pool.slice(0, 3))
		"shield":
			shield_max = z.max_hp * float(spec.get("shield", 0.15))
			shield = shield_max
			Sfx.play("armor", 0.0)
		"scream":
			Sfx.play("scream", 2.0)
			game.add_shake(0.5)
			game.rally(z.position, 260.0, 5.0, z)


func _summon(z: Variant, kinds: Array) -> void:
	var n := kinds.size()
	for i in n:
		var at: Vector2 = z.position + Vector2.from_angle(TAU * i / n + randf() * 0.4) * randf_range(36.0, 56.0)
		z.game.hazards.spawn_circle(String(kinds[i]), at, z, 0.8)


func draw(z: Variant) -> void:
	var mid := Vector2(0, -z.center_h)
	var r: float = z.hit_r + 6.0
	if changing_t > 0.0:
		z.draw_arc(mid, r + changing_t * 10.0, 0.0, TAU, 28, Color(1.0, 0.9, 0.5, 0.9), 2.0)
	if shield > 0.0:
		var pulse := sin(Time.get_ticks_msec() * 0.008) * 0.5 + 0.5
		z.draw_circle(mid, r, Color(0.5, 1.0, 0.3, 0.12 + pulse * 0.1))
		z.draw_arc(mid, r, 0.0, TAU, 28, Color("#b0ff70"), 1.0)
	elif guarded():
		z.draw_arc(mid, r, 0.0, TAU, 28, Color(0.8, 0.5, 1.0, 0.7), 1.0)
