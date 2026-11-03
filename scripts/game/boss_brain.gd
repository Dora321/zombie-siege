extends "res://scripts/game/zombie_brain.gd"
## Boss：按 GameData.BOSSES 的配置分阶段出招。血量跌到阈值就锁血换阶段，一刀也跳不过去。
## 所有招式都先蓄力亮危险提示，时间到才结算。
## 专属机制也在这里：覆甲阈值（hit_floor）、再生（regen）、钻地（burrow）、镜面反弹（reflect）。

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
	"burrow": 0.5, "emerge_slam": 0.7, "reflect_aura": 1.0,
}
## 覆甲阈值不管这些来源：爆炸、狙击、回旋镖、霰弹（整枪算一次爆发）、核弹、脚本直接扣血。
const FLOOR_EXEMPT: Array[String] = ["blast", "beam", "rang", "buckshot", "nuke", ""]
## 钻在地下时，这些直射打不到它（子弹从土堆上飞过去）。
const DIRECT: Array[String] = ["bullet", "buckshot", "beam", "rang", "arc"]
## 镜面的克制：这些不看朝向；直射从背后打进来也算。
const MIRROR_WEAK: Array[String] = ["arc", "blast", "tick"]
const MIRROR_BACK: Array[String] = ["bullet", "buckshot", "beam"]
const BURROW_SPEED := 1.3
const BURROW_REACH := 400.0
## 地下离玩家这么近就出土砸人。
const EMERGE_REACH := 16.0
## 被爆炸、火或闪光逼出地面后的硬直。
const EMERGE_STUN := 1.0
const TRAIL_GAP := 0.2
const TRAIL_LIFE := 2.4
## 镜面：盾面转向玩家的速度，正面判定和护盾兵一样。出招蓄力时转得慢，这是绕后的窗口。
const MIRROR_TURN := 1.8
const MIRROR_CAST_TURN := 0.35
const MIRROR_FRONT := -0.28
const REFLECT_MULT := 0.25
const REFLECT_CAP := 12.0
const AURA_T := 1.5
const AURA_MULT := 0.5
const AURA_CAP := 20.0
const AURA_REACH := 260.0
## 机制日志的节流间隔，免得机器人日志被刷屏。
const NOTE_GAP := 5.0

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
# 配了 once 的招式本阶段放过没有
var _phase_used := {}
# 机制统计，死时打进机器人日志；_notes 记每类日志上次打印的时间
var stats := {}
var _clock := 0.0
var _notes := {}
var _text_t := 0.0
# 再生
var _regen_shown := 0.0
var _regen_state := ""
# 钻地：_trail 是地下走过的土堆，出土后慢慢消失
var _burrow_t := 0.0
var _trail: Array = []
var _trail_t := 0.0
# 镜面：盾面朝向和反射光环剩余时间
var face := Vector2.DOWN
var aura_t := 0.0


func setup(z: Variant) -> void:
	redraw = true
	spec = GameData.BOSSES[z.kind]
	phases = spec["phases"]
	_apply_phase(z)


func info(z: Variant = null) -> Dictionary:
	return {"title": spec["title"], "phase": phase, "count": phases.size(), "name": phases[phase]["name"], "shield": shield / shield_max if shield > 0.0 else 0.0, "status": status(z)}


## 血条旁边的状态字：地下、淬火、再生、反弹。
func status(z: Variant = null) -> String:
	if underground():
		return "在地下"
	if z != null and z.quenched() and has_armor(z):
		return "淬火破甲"
	if aura_t > 0.0:
		return "反弹光环"
	if _regen_state == "on":
		return "再生中"
	if _regen_state == "off":
		return "再生被压住"
	return ""


## 阶段切换和护盾期间打不动，HUD 和飘字都要用到。
func untouchable() -> bool:
	return changing_t > 0.0


func guarded() -> bool:
	return _guard < 1.0


func underground() -> bool:
	return _burrow_t > 0.0


## 钻在地下时炮塔和雷达都看不到它，只剩土堆和黄圈。
func cloaked() -> bool:
	return underground()


## 有甲（覆甲巨像裸核之前）；淬火期间甲照样在，只是阈值不生效。
func has_armor(_z: Variant) -> bool:
	return float(spec.get("hit_floor", 0.0)) > 0.0 and not bool(phases[phase].get("bare", false))


func _armored(z: Variant) -> bool:
	return has_armor(z) and not z.quenched()


func _count(key: String, amount := 1.0) -> void:
	stats[key] = float(stats.get(key, 0.0)) + amount


## 同一类机制日志 NOTE_GAP 秒内只打一条。
func _note(key: String, text: String) -> void:
	if _clock - float(_notes.get(key, -INF)) < NOTE_GAP:
		return
	_notes[key] = _clock
	Harness.note(text)


func _say(z: Variant, text: String, color: Color) -> void:
	if _text_t > 0.0:
		return
	_text_t = 1.2
	z.game.fx.text(z.position + Vector2(0, -z.center_h * 2.0 - 8.0), text, color)


func _apply_phase(z: Variant) -> void:
	var p: Dictionary = phases[phase]
	z._speed_mult = float(p.get("speed", 1.0))
	z.set_tint(Color(String(p.get("tint", "#ffffff"))))
	_guard = 1.0
	_enter = String(p.get("enter", ""))


## src 是伤害来源：bullet/buckshot/beam/arc/rang/blast/tick/nuke，脚本直接扣血是空串。
func absorb(z: Variant, amount: float, src := "") -> float:
	if changing_t > 0.0:
		return 0.0
	if underground():
		if DIRECT.has(src):
			return 0.0
		_force_out(z, {"blast": "爆炸", "tick": "火焰"}.get(src, "重击"))
	# 覆甲：小伤害只结算一成。先看原始伤害，护盾照常全额吃
	var light := _armored(z) and not FLOOR_EXEMPT.has(src) and amount < float(spec["hit_floor"])
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
	if light:
		amount *= float(spec.get("floor_mult", 0.1))
		_count("floor")
		z.cue("叮", z.CUE_DING)
		_note("floor", "%s 的装甲挡下小伤害（累计 %d 次，来源 %s）" % [spec["title"], int(stats["floor"]), src])
	amount *= _guard
	if phase + 1 < phases.size():
		var floor_hp: float = float(phases[phase + 1]["at"]) * z.max_hp
		if z.hp - amount <= floor_hp:
			amount = maxf(z.hp - floor_hp, 0.0)
			_begin_change(z)
	return amount


## 覆甲被霰弹、狙击、榴弹、回旋镖打出满额（淬火时什么都算满额）；镜面被电弧、爆炸、火焰或从背后打中。
func weak_hit(z: Variant, src: String, dir: Vector2) -> bool:
	if has_armor(z) and src != "" and (FLOOR_EXEMPT.has(src) or z.quenched()):
		_count("weak")
		return true
	if bool(spec.get("reflect", false)) and (MIRROR_WEAK.has(src) or (MIRROR_BACK.has(src) and dir.dot(face) >= MIRROR_FRONT)):
		_count("weak")
		return true
	return false


func _begin_change(z: Variant) -> void:
	phase += 1
	changing_t = CHANGE_T
	_act = ""
	_chain = 0
	_breakable = false
	_phase_used.clear()
	aura_t = 0.0
	_surface(z)
	_drop_lane(z)
	z._charge_t = 0.0
	z._pose = -1
	shield = 0.0
	_apply_phase(z)
	z.flash_warn(CHANGE_T)
	z.game.on_boss_phase(z, phases[phase], phase, phases.size())


func on_stun(z: Variant) -> void:
	if underground():
		_force_out(z, "闪光")
		return
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
	if not stats.is_empty():
		var parts: Array[String] = []
		for key: String in stats.keys():
			parts.append("%s=%d" % [key, roundi(float(stats[key]))])
		Harness.note("%s 机制统计：%s" % [spec["title"], " ".join(parts)])
	z.game.dismiss_minions(z)
	z.game.on_boss_down(z)


## 不受晕眩影响、每帧都走的计时：再生、反射光环、土堆、镜面转向。
func tick(z: Variant, dt: float) -> void:
	_clock += dt
	_text_t -= dt
	aura_t -= dt
	_tick_regen(z, dt)
	var i := _trail.size() - 1
	while i >= 0:
		_trail[i]["t"] = float(_trail[i]["t"]) - dt
		if float(_trail[i]["t"]) <= 0.0:
			_trail.remove_at(i)
		i -= 1
	if bool(spec.get("reflect", false)) and not z.incapacitated():
		var player: Variant = z.game.player
		var want: Vector2 = z.position.direction_to(player.position if player.alive else z.game.base.position)
		var turn := MIRROR_TURN * (MIRROR_CAST_TURN if _act != "" else 1.0) * dt
		face = face.rotated(clampf(face.angle_to(want), -turn, turn))


## 再生坟主：没挂冰也没着火时按比例回血，最多回到本阶段的上限，跨不回上一阶段。
func _tick_regen(z: Variant, dt: float) -> void:
	var rate := float(phases[phase].get("regen", spec.get("regen", 0.0)))
	if rate <= 0.0:
		return
	if z._chill_t > 0.0 or z._burn_t > 0.0:
		_regen_state = "off"
		_count("regen_blocked_s", dt)
		_note("regen_off", "%s 的再生被%s压住" % [spec["title"], "冰" if z._chill_t > 0.0 else "火"])
		return
	_regen_state = "on"
	var cap: float = float(phases[phase]["at"]) * z.max_hp
	if changing_t > 0.0 or z.hp >= cap:
		return
	var gain: float = minf(rate * z.max_hp * dt, cap - z.hp)
	z.hp += gain
	_count("regen_hp", gain)
	_regen_shown += gain
	if _regen_shown >= 15.0:
		z.game.fx.number(z.center() + Vector2(randf_range(-4, 4), -10), roundi(_regen_shown), Color("#80ff70"))
		_regen_shown = 0.0
		_note("regen_on", "%s 在再生（累计回了 %d 血）" % [spec["title"], roundi(float(stats["regen_hp"]))])


## 镜面女皇：正面的子弹和狙击弹回去，反射光环期间连背后的直射也弹。返回 true 表示这一发被弹掉了。
func reflect_shot(z: Variant, dir: Vector2, damage: float, src: String, from_player: bool) -> bool:
	if not bool(spec.get("reflect", false)) or changing_t > 0.0 or z.incapacitated() or not DIRECT.has(src) or src == "arc":
		return false
	var aura := aura_t > 0.0
	if not aura and (src == "rang" or dir.dot(face) >= MIRROR_FRONT):
		return false
	var player: Variant = z.game.player
	z.game.fx.spark(z.center() - dir * float(z.hit_r))
	Sfx.play("shield_block", -4.0, 0.15)
	if from_player and player.alive:
		var back: float = minf(damage * (AURA_MULT if aura else REFLECT_MULT), AURA_CAP if aura else REFLECT_CAP) * float(player.reflect_mult)
		player.take_damage(back, z.center())
	_count("reflect")
	_say(z, "弹回来了！", Color("#d0f0ff"))
	_note("reflect", "%s %s弹回了%s（累计 %d 次）" % [spec["title"], "用光环" if aura else "正面", src, int(stats["reflect"])])
	return true


func _dig_in(z: Variant) -> void:
	var range_t: Array = phases[phase].get("burrow", spec["burrow"])
	_burrow_t = randf_range(float(range_t[0]), float(range_t[1]))
	_trail_t = 0.0
	z.burrowed = true
	z.body.visible = false
	z.shadow.visible = false
	z.game.fx.dust(z.position, 14)
	Sfx.play("rock_fall", -2.0)
	_count("burrow")
	_note("burrow", "%s 钻进地下（%.1f 秒）" % [spec["title"], _burrow_t])


## 看 burrowed 而不是计时：计时自然走完时 _burrow_t 已经扣到 0，再看计时就会留在地下隐身。
func _surface(z: Variant) -> void:
	if not z.burrowed:
		return
	_burrow_t = 0.0
	z.burrowed = false
	z.body.visible = true
	z.shadow.visible = true
	z.game.fx.dust(z.position, 16)
	z.game.add_shake(0.4)
	Sfx.play("wall_break", -2.0)


## 地下挨了爆炸、火或闪光：强行出土，硬直一下，这是打它的窗口。
func _force_out(z: Variant, by: String) -> void:
	if not underground():
		return
	_surface(z)
	_act = ""
	z._pose = -1
	z.stun(EMERGE_STUN)
	_count("forced_out")
	z.game.fx.text(z.position + Vector2(0, -z.center_h * 2.0 - 8.0), "逼出来了！", Color("#ffe060"))
	Harness.note("%s 被%s逼出地面（第 %d 次）" % [spec["title"], by, int(stats["forced_out"])])


## 地下赶路：看得见玩家就直奔玩家，否则顺着流场走；前面是墙就在墙边出土。
func _burrow_dir(z: Variant, player_ok: bool) -> Vector2:
	var map: Variant = z.map
	if player_ok and map.line_clear(z.position, z.game.player.position, map.BLOCK_ZOMBIE):
		return z.position.direction_to(z.game.player.position)
	var nxt: int = map.next_cell[map.cell_of(z.position)]
	if nxt < 0:
		return z.position.direction_to(z.game.base.position)
	if map.blocks(nxt, map.BLOCK_ZOMBIE):
		return Vector2.ZERO
	return z.position.direction_to(map.cell_center(nxt))


func decide(z: Variant, dt: float, player_ok: bool) -> Variant:
	if changing_t > 0.0:
		changing_t -= dt
		z._lunge = Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0))
		if changing_t <= 0.0 and _enter != "":
			_begin_move(z, _enter)
		return Vector2.ZERO
	if underground():
		_burrow_t -= dt
		_trail_t -= dt
		if _trail_t <= 0.0:
			_trail_t = TRAIL_GAP
			_trail.append({"pos": z.position, "t": TRAIL_LIFE})
		var dir := _burrow_dir(z, player_ok)
		var close: bool = player_ok and z.position.distance_to(z.game.player.position) < EMERGE_REACH
		if _burrow_t <= 0.0 or close or dir == Vector2.ZERO:
			_surface(z)
			_begin_move(z, "emerge_slam")
			return Vector2.ZERO
		z._speed_mult = float(phases[phase].get("speed", 1.0)) * BURROW_SPEED
		return dir
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
	if (phases[phase].get("once", []) as Array).has(move) and _phase_used.has(move):
		return false
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
		"burrow":
			return d < BURROW_REACH
		"emerge_slam":
			return d < SLAM_REACH
		"reflect_aura":
			return d < AURA_REACH and aura_t <= 0.0
	return false


## 蓄力开始：亮红圈和闪光，招式的落点此时就定了，玩家有时间躲。
## follow 表示这是连冲的第二段蓄力。
func _begin_move(z: Variant, move: String, follow := false) -> void:
	var warn: float = MOVE_WARN[move]
	_act = move
	_act_t = warn
	_last = move
	moves_used[move] = true
	_phase_used[move] = true
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
			# 掘地领主的预警全用高对比的黄圈，断电时也看得清
			hazards.warn_ring(z.position, 34.0, warn, z, "dig" if spec.has("burrow") else "")
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
		"burrow":
			hazards.warn_ring(z.position, 24.0, warn, z, "dig")
			z.game.fx.dust(z.position, 8)
			Sfx.play("rock_fall", -6.0)
		"emerge_slam":
			hazards.slam(z.position, SLAM_R * float(spec.get("slam_scale", 1.0)), z._damage * 1.3, warn, z, "dig")
			Sfx.play("charge_warn", 0.0)
		"reflect_aura":
			z.game.fx.ring(z.center(), 30.0, warn, Color("#ff4060"))
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
		"burrow":
			_dig_in(z)
		"emerge_slam":
			z._lunge = Vector2(0, 4)
			game.add_shake(0.3)
		"reflect_aura":
			aura_t = AURA_T
			Sfx.play("armor", 0.0)
			_count("aura")
			Harness.note("%s 张开反射光环（第 %d 次）" % [spec["title"], int(stats["aura"])])


func _summon(z: Variant, kinds: Array) -> void:
	var n := kinds.size()
	for i in n:
		var at: Vector2 = z.position + Vector2.from_angle(TAU * i / n + randf() * 0.4) * randf_range(36.0, 56.0)
		z.game.hazards.spawn_circle(String(kinds[i]), at, z, 0.8)


func draw(z: Variant) -> void:
	var mid := Vector2(0, -z.center_h)
	var r: float = z.hit_r + 6.0
	_draw_trail(z)
	if underground():
		_draw_mound(z)
		return
	if bool(spec.get("reflect", false)):
		_draw_mirror(z, mid)
	if z.quenched() and has_armor(z):
		# 淬火：甲缝里往外冒白汽
		var k := int(Time.get_ticks_msec() / 90) % 8
		for j in 3:
			var at := Vector2(-6 + j * 6, -z.center_h * 2.0 + 2.0 - float((k + j * 3) % 8)).round()
			z.draw_rect(Rect2(at, Vector2(2, 1)), Color(0.92, 0.94, 1.0, 0.8))
	if _regen_state == "on" and z.hp < z.max_hp:
		# 头顶往上冒的绿色小十字
		var k := int(Time.get_ticks_msec() / 120) % 6
		for j in 2:
			var at := Vector2(-5 + j * 9, -z.center_h * 2.0 - 2.0 - float((k + j * 3) % 6) * 1.5).round()
			z.draw_rect(Rect2(at + Vector2(-1, 0), Vector2(3, 1)), Color("#80ff70"))
			z.draw_rect(Rect2(at + Vector2(0, -1), Vector2(1, 3)), Color("#80ff70"))
	if changing_t > 0.0:
		z.draw_arc(mid, r + changing_t * 10.0, 0.0, TAU, 28, Color(1.0, 0.9, 0.5, 0.9), 2.0)
	if shield > 0.0:
		var pulse := sin(Time.get_ticks_msec() * 0.008) * 0.5 + 0.5
		z.draw_circle(mid, r, Color(0.5, 1.0, 0.3, 0.12 + pulse * 0.1))
		z.draw_arc(mid, r, 0.0, TAU, 28, Color("#b0ff70"), 1.0)
	elif guarded():
		z.draw_arc(mid, r, 0.0, TAU, 28, Color(0.8, 0.5, 1.0, 0.7), 1.0)


## 断电时土堆和黄圈要更亮：颜色超过 1 再被全局变暗，结果仍然显眼。
func _glow(z: Variant) -> float:
	return 2.1 if GameData.wave_special(z.game.wave) == "blackout" else 1.0


func _bright(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


func _draw_trail(z: Variant) -> void:
	var k := _glow(z)
	for m: Dictionary in _trail:
		var fade := clampf(float(m["t"]) / TRAIL_LIFE, 0.0, 1.0)
		var at: Vector2 = (m["pos"] - z.position).round()
		z.draw_rect(Rect2(at + Vector2(-3, -1), Vector2(6, 2)), Color(0.42, 0.3, 0.18, 0.75 * fade))
		z.draw_rect(Rect2(at + Vector2(-2, -2), Vector2(3, 1)), _bright(Color(0.95, 0.82, 0.25, 0.8 * fade), k))


## 地下的样子：一个拱起的土包，外面一圈跳动的黄圈。
func _draw_mound(z: Variant) -> void:
	var k := _glow(z)
	var w: float = z.hit_r + 3.0
	var pulse := sin(Time.get_ticks_msec() * 0.012) * 0.5 + 0.5
	z.draw_circle(Vector2.ZERO, w, Color(0.3, 0.2, 0.12, 0.85))
	z.draw_circle(Vector2(-2, -2), w * 0.6, Color(0.5, 0.36, 0.22, 0.9))
	for j in 5:
		var a := float(j) * 1.3 + _clock * 2.0
		z.draw_rect(Rect2((Vector2(cos(a), sin(a) * 0.6) * w * 0.7).round(), Vector2(2, 1)), Color(0.66, 0.5, 0.32))
	z.draw_arc(Vector2.ZERO, w + 5.0 + pulse * 3.0, 0.0, TAU, 28, _bright(Color(1.0, 0.86, 0.15, 0.9), k), 1.0)
	z.draw_arc(Vector2.ZERO, w + 2.0, 0.0, TAU, 28, _bright(Color(1.0, 0.95, 0.5, 0.5), k), 1.0)


## 身前一面镜子，朝向就是会反弹的正面；光环期间整个人罩着红光。
func _draw_mirror(z: Variant, mid: Vector2) -> void:
	var side := face.orthogonal()
	var at: Vector2 = mid + face * (z.hit_r + 3.0)
	var glint := int(Time.get_ticks_msec() / 70) % 15 - 7
	var dim: bool = z.incapacitated()
	for j in range(-6, 7):
		var p: Vector2 = (at + side * j).round()
		z.draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Color("#3a3050"))
	for j in range(-5, 6):
		var p: Vector2 = (at + side * j).round()
		var c := Color("#f8fcff") if j == glint and not dim else (Color("#6c7488") if dim else Color("#b8e8ff"))
		z.draw_rect(Rect2(p, Vector2(1, 1)), c)
	if aura_t > 0.0:
		var pulse := sin(Time.get_ticks_msec() * 0.02) * 0.5 + 0.5
		z.draw_circle(mid, z.hit_r + 9.0, Color(1.0, 0.25, 0.35, 0.1 + pulse * 0.08))
		z.draw_arc(mid, z.hit_r + 9.0, 0.0, TAU, 28, Color("#ff5070"), 1.0)
