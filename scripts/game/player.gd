extends Node2D
## 玩家：移动、冲刺、瞄准射击、换弹、切枪。输入可以来自键鼠或测试机器人。

const SPEED := 96.0
const ACCEL := 16.0
const DASH_SPEED := 300.0
const DASH_TIME := 0.15
const BOX_R := 5.0
const HAND_H := 7.0

var game: Node
var map: Node2D
var bot: Variant = null

var hp := 100.0
var max_hp := 100.0
var alive := true
var speed_mult := 1.0
var dash_cd_base := 1.3
var magnet_range := 42.0

var weapon_id := "pistol"
var weapon_state := {
	"pistol": {"level": 1, "mag": 12, "reserve": -1},
	"shotgun": {"level": 1, "mag": 6, "reserve": 18},
	"smg": {"level": 1, "mag": 32, "reserve": 96},
}
var stats := {}
var cooldown := 0.0
var reload_t := 0.0
var reload_total := 1.0

var velocity := Vector2.ZERO
var aim := Vector2.RIGHT
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.RIGHT
var invuln := 0.0
var recoil_px := 0.0
var fired_kick := 0.0

var _knock := Vector2.ZERO
var _flash_t := 0.0
var _dir := 0
var _walk := 0.0
var _ghost_t := 0.0
var _no_ammo_note := 0.0
var _body_key := -1
# 单次按键用事件锁存，命中停顿拉慢物理帧时也不会丢
var _latch_dash := false
var _latch_reload := false
var _latch_weapon := -1

@onready var body: Sprite2D = $Body
@onready var gun: Sprite2D = $Gun
@onready var shadow: Sprite2D = $Shadow


func setup(g: Node, m: Node2D) -> void:
	game = g
	map = m
	shadow.texture = Art.shadow_small
	shadow.position = Vector2(0, -1)
	var size := Art.char_size("player")
	body.offset = Vector2(-size.x / 2, -size.y + 1)
	for id: String in GameData.WEAPON_ORDER:
		_refresh_stats(id)
	_set_gun_sprite()


func _refresh_stats(id: String) -> void:
	stats[id] = GameData.weapon_stats(id, int(weapon_state[id]["level"]))


func current_stats() -> Dictionary:
	return stats[weapon_id]


func upgrade_weapon(id: String) -> void:
	var st: Dictionary = weapon_state[id]
	st["level"] = int(st["level"]) + 1
	_refresh_stats(id)
	# 升级后顺手填满新增的弹匣容量
	st["mag"] = int(stats[id]["mag"]) if id == "pistol" else st["mag"]


func _set_gun_sprite() -> void:
	var g: Dictionary = Art.guns[weapon_id]
	gun.texture = g["tex"]
	gun.centered = false
	gun.offset = Vector2(-3, -int(g["h"]) / 2)


func _physics_process(dt: float) -> void:
	if not alive:
		return
	var control: bool = game.player_can_act()
	var move_input := Vector2.ZERO
	var firing := false
	var want_dash := false
	var want_reload := false
	var weapon_pick := -1
	if bot != null:
		move_input = bot.move
		aim = bot.aim_dir
		firing = bot.firing
		want_dash = bot.want_dash
		want_reload = bot.want_reload
		weapon_pick = bot.want_weapon
		bot.want_dash = false
		bot.want_reload = false
		bot.want_weapon = -1
	else:
		move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var mouse := get_global_mouse_position()
		var from := position + Vector2(0, -HAND_H)
		if mouse.distance_squared_to(from) > 4.0:
			aim = (mouse - from).normalized()
		firing = Input.is_action_pressed("fire")
		want_dash = _latch_dash
		want_reload = _latch_reload
		weapon_pick = _latch_weapon
		_latch_dash = false
		_latch_reload = false
		_latch_weapon = -1

	if not control:
		firing = false
		want_dash = false
		want_reload = false
		weapon_pick = -1
		if not game.player_can_walk():
			move_input = Vector2.ZERO

	_tick_timers(dt)
	if weapon_pick >= 0:
		switch_weapon(GameData.WEAPON_ORDER[weapon_pick])
	if want_reload:
		start_reload()
	if want_dash:
		_try_dash(move_input)
	if firing:
		_try_fire()
	_move(move_input, dt)
	_animate(dt, move_input)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("dash"):
		_latch_dash = true
	elif event.is_action_pressed("reload"):
		_latch_reload = true
	elif event.is_action_pressed("weapon_1"):
		_latch_weapon = 0
	elif event.is_action_pressed("weapon_2"):
		_latch_weapon = 1
	elif event.is_action_pressed("weapon_3"):
		_latch_weapon = 2
	elif event.is_action_pressed("weapon_next"):
		_latch_weapon = (GameData.WEAPON_ORDER.find(weapon_id) + 1) % 3
	elif event.is_action_pressed("weapon_prev"):
		_latch_weapon = (GameData.WEAPON_ORDER.find(weapon_id) + 2) % 3


func _tick_timers(dt: float) -> void:
	cooldown -= dt
	dash_cd -= dt
	invuln -= dt
	_flash_t -= dt
	_no_ammo_note -= dt
	recoil_px = move_toward(recoil_px, 0.0, dt * 22.0)
	fired_kick = move_toward(fired_kick, 0.0, dt * 3.5)
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			_finish_reload()
		queue_redraw()


func _move(move_input: Vector2, dt: float) -> void:
	if dash_t > 0.0:
		dash_t -= dt
		velocity = dash_dir * DASH_SPEED
		_ghost_t -= dt
		if _ghost_t <= 0.0:
			_ghost_t = 0.03
			game.fx.ghost(body.texture, position + body.offset, body.flip_h, Color(0.5, 0.85, 1.0, 0.55), 0.2)
		if dash_t <= 0.0:
			velocity *= 0.4
	else:
		var target: Vector2 = move_input.limit_length(1.0) * SPEED * speed_mult
		velocity = velocity.lerp(target, clampf(ACCEL * dt, 0.0, 1.0))
	_knock = _knock.lerp(Vector2.ZERO, clampf(10.0 * dt, 0.0, 1.0))
	position = map.move_box(position, (velocity + _knock) * dt, BOX_R, map.BLOCK_PLAYER)


func _animate(dt: float, _move_input: Vector2) -> void:
	# 身体朝向跟随准星，看起来更像在“边退边打”
	var dir := Art.DIR_DOWN
	if absf(aim.x) > absf(aim.y):
		dir = Art.DIR_SIDE
	elif aim.y < 0.0:
		dir = Art.DIR_UP
	_dir = dir
	body.flip_h = aim.x < 0.0 and dir == Art.DIR_SIDE
	var spd := velocity.length()
	if spd > 8.0:
		# 倒退时反向播放走路帧
		var back: float = -1.0 if velocity.dot(aim) < -5.0 else 1.0
		_walk += dt * spd * 0.14 * back
	else:
		_walk = 0.0
	var f := posmod(int(floorf(_walk)), Art.FRAMES)
	var white := _flash_t > 0.0
	var key := dir * 100 + f * 10 + (1 if white else 0)
	if key != _body_key:
		_body_key = key
		body.texture = Art.frame("player", dir, f, white)
	body.visible = not (invuln > 0.0 and _flash_t <= 0.0 and int(invuln * 24.0) % 2 == 0) or dash_t > 0.0
	# 枪
	gun.rotation = aim.angle()
	gun.flip_v = aim.x < 0.0
	gun.position = Vector2(0, -HAND_H) + aim * (3.0 - recoil_px)
	gun.show_behind_parent = false
	gun.z_index = -1 if dir == Art.DIR_UP else 0


func switch_weapon(id: String) -> void:
	if id == weapon_id:
		return
	weapon_id = id
	reload_t = 0.0
	cooldown = maxf(cooldown, 0.12)
	_set_gun_sprite()
	Sfx.play("reload", -6.0, 0.15)
	queue_redraw()


func mag_size() -> int:
	return int(stats[weapon_id]["mag"])


func start_reload() -> void:
	var st: Dictionary = weapon_state[weapon_id]
	if reload_t > 0.0 or int(st["mag"]) >= mag_size():
		return
	if int(st["reserve"]) == 0:
		if _no_ammo_note <= 0.0:
			_no_ammo_note = 0.8
			game.fx.text(position + Vector2(0, -22), "没有备弹！", Color("#ff8060"))
			Sfx.play("empty")
		return
	reload_total = float(stats[weapon_id]["reload"])
	reload_t = reload_total
	Sfx.play("reload")


func _finish_reload() -> void:
	reload_t = 0.0
	var st: Dictionary = weapon_state[weapon_id]
	var need := mag_size() - int(st["mag"])
	if int(st["reserve"]) < 0:
		st["mag"] = mag_size()
	else:
		var take := mini(need, int(st["reserve"]))
		st["mag"] = int(st["mag"]) + take
		st["reserve"] = int(st["reserve"]) - take
	Sfx.play("reload_done")


func _try_fire() -> void:
	if cooldown > 0.0 or reload_t > 0.0 or dash_t > 0.0:
		return
	var st: Dictionary = weapon_state[weapon_id]
	if int(st["mag"]) <= 0:
		cooldown = 0.18
		Sfx.play("empty")
		start_reload()
		return
	var s: Dictionary = stats[weapon_id]
	st["mag"] = int(st["mag"]) - 1
	cooldown = float(s["cooldown"])
	var muzzle: Vector2 = position + Vector2(0, -HAND_H) + aim * (float(Art.guns[weapon_id]["w"]) - 1.0)
	var spread := deg_to_rad(float(s["spread"]))
	for i in int(s["pellets"]):
		var d := aim.rotated(randf_range(-spread, spread))
		var bullet_speed := float(s["speed"]) * randf_range(0.92, 1.05)
		game.bullets.fire(muzzle, d * bullet_speed, float(s["damage"]), float(s["knock"]), float(s["life"]), int(s["pierce"]), Color(String(s["color"])), true)
	game.fx.muzzle_flash(muzzle, aim, weapon_id == "shotgun")
	game.fx.casing(position + Vector2(0, -HAND_H), aim, weapon_id == "shotgun")
	game.add_shake(float(s["shake"]))
	game.kick_camera(aim * float(s["recoil"]))
	recoil_px = float(s["recoil"])
	fired_kick = minf(fired_kick + 0.35, 1.0)
	velocity -= aim * float(s["recoil"]) * 6.0
	Sfx.play(String(s["sfx"]))
	if int(st["mag"]) <= 0:
		start_reload()


func _try_dash(move_input: Vector2) -> void:
	if dash_cd > 0.0 or dash_t > 0.0:
		return
	dash_dir = move_input.normalized() if move_input.length() > 0.1 else aim
	dash_t = DASH_TIME
	dash_cd = dash_cd_base
	invuln = maxf(invuln, DASH_TIME + 0.08)
	Sfx.play("dash")
	game.fx.dust(position, 6)


func take_damage(amount: float, attacker_pos: Variant = null) -> void:
	if not alive or invuln > 0.0 or game.god_mode:
		return
	hp -= amount
	invuln = 0.5
	_flash_t = 0.1
	if attacker_pos != null:
		var from: Vector2 = attacker_pos
		_knock += (position - from).normalized() * 150.0
	game.on_player_hurt(amount)
	game.fx.blood_hit(position + Vector2(0, -7), Vector2.UP, 6, Color("#a01c1c"))
	if hp <= 0.0:
		hp = 0.0
		alive = false
		visible = false
		game.fx.gibs("player", position, Vector2.UP)
		game.decals.stamp(Art.blood_splats_dark[randi() % Art.blood_splats_dark.size()], position)
		game.on_player_died()


## 酸液这类持续伤害不触发无敌帧。
func take_dot(amount: float) -> void:
	if not alive or game.god_mode or dash_t > 0.0:
		return
	hp -= amount
	game.hud.flash_dot()
	if hp <= 0.0:
		hp = 0.0
		invuln = 0.0
		take_damage(1.0)


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)


func _draw() -> void:
	if reload_t > 0.0:
		var ratio := 1.0 - reload_t / reload_total
		draw_rect(Rect2(-8, -22, 16, 3), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(-7, -21, 14.0 * ratio, 1), Color("#f0d050"))
