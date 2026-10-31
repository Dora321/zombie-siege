extends Node2D
## 玩家：移动、冲刺、瞄准射击、换弹、切枪、道具。输入可以来自键鼠或测试机器人。

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
## 每把枪的等级和弹药；level 为 0 表示还没解锁。
var weapon_state := {}
var stats := {}
var cooldown := 0.0
var reload_t := 0.0
var reload_total := 1.0

var velocity := Vector2.ZERO
var aim := Vector2.RIGHT
var aim_point := Vector2.ZERO
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.RIGHT
var invuln := 0.0
## 持续伤害系数，母体血清减半。
var dot_mult := 1.0
var recoil_px := 0.0
var fired_kick := 0.0

var armor := 0.0
var items := {}
var selected_item := "frag"
var buff_speed_t := 0.0
var buff_damage_t := 0.0
var buff_ammo_t := 0.0

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
var _latch_item := ""
var _latch_item_next := false
var _buff_tint := false

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
		var spec: Dictionary = GameData.WEAPONS[id]
		var start_level := 1 if int(spec["unlock_cost"]) == 0 else 0
		weapon_state[id] = {"level": start_level, "mag": 0, "reserve": spec["start_reserve"]}
		_refresh_stats(id)
		weapon_state[id]["mag"] = int(stats[id]["mag"])
	for id: String in GameData.ITEM_ORDER:
		items[id] = int(GameData.ITEMS[id]["start"])
	_set_gun_sprite()


func _refresh_stats(id: String) -> void:
	stats[id] = GameData.weapon_stats(id, maxi(int(weapon_state[id]["level"]), 1))


func owns_weapon(id: String) -> bool:
	return int(weapon_state[id]["level"]) > 0


func owned_weapons() -> Array[String]:
	var out: Array[String] = []
	for id: String in GameData.WEAPON_ORDER:
		if owns_weapon(id):
			out.append(id)
	return out


func damage_mult() -> float:
	return GameData.DAMAGE_BUFF if buff_damage_t > 0.0 else 1.0


func muzzle_pos() -> Vector2:
	return position + Vector2(0, -HAND_H) + aim * (float(Art.guns[weapon_id]["w"]) - 1.0)


## 抛物线的落点：准星位置，超出射程就落在射程边缘。
func lob_target(max_range: float) -> Vector2:
	var hand := position + Vector2(0, -HAND_H)
	var to := aim_point - hand
	if to.length() < 1.0:
		to = aim
	return hand + to.limit_length(max_range)


func current_stats() -> Dictionary:
	return stats[weapon_id]


func upgrade_weapon(id: String) -> void:
	var st: Dictionary = weapon_state[id]
	var unlocking := int(st["level"]) == 0
	var old_mag := int(stats[id]["mag"])
	st["level"] = int(st["level"]) + 1
	_refresh_stats(id)
	# 升级后顺手填满新增的弹匣容量
	if id == "pistol" or unlocking:
		st["mag"] = int(stats[id]["mag"])
	elif bool(stats[id].get("returns", false)):
		st["mag"] = int(st["mag"]) + int(stats[id]["mag"]) - old_mag


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
	var item_pick := ""
	if bot != null:
		move_input = bot.move
		aim = bot.aim_dir
		aim_point = bot.aim_point
		firing = bot.firing
		want_dash = bot.want_dash
		want_reload = bot.want_reload
		weapon_pick = bot.want_weapon
		bot.want_dash = false
		bot.want_reload = false
		bot.want_weapon = -1
		item_pick = bot.want_item
		bot.want_item = ""
	else:
		move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var mouse := get_global_mouse_position()
		aim_point = mouse
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
		item_pick = _latch_item
		_latch_item = ""
		if _latch_item_next:
			_latch_item_next = false
			cycle_item()

	if not control:
		item_pick = ""
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
	if item_pick != "":
		use_item(item_pick)
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
	elif event.is_action_pressed("weapon_next"):
		_latch_weapon = _next_owned(1)
	elif event.is_action_pressed("weapon_prev"):
		_latch_weapon = _next_owned(-1)
	elif event.is_action_pressed("item_use"):
		_latch_item = selected_item
	elif event.is_action_pressed("item_next"):
		_latch_item_next = true
	elif event.is_action_pressed("item_medkit"):
		_latch_item = "medkit"
	elif event.is_action_pressed("item_frag"):
		_latch_item = "frag"
	elif event.is_action_pressed("item_nuke"):
		_latch_item = "nuke"
	else:
		for i in GameData.WEAPON_ORDER.size():
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				_latch_weapon = i
				break


## 滚轮只在已解锁的枪之间切换。
func _next_owned(step: int) -> int:
	var order := GameData.WEAPON_ORDER
	var i := order.find(weapon_id)
	for k in order.size():
		i = posmod(i + step, order.size())
		if owns_weapon(order[i]):
			return i
	return order.find(weapon_id)


func _tick_timers(dt: float) -> void:
	cooldown -= dt
	dash_cd -= dt
	invuln -= dt
	_flash_t -= dt
	_no_ammo_note -= dt
	if game.player_can_act():
		buff_speed_t = maxf(buff_speed_t - dt, 0.0)
		buff_damage_t = maxf(buff_damage_t - dt, 0.0)
		buff_ammo_t = maxf(buff_ammo_t - dt, 0.0)
	var tinted := buff_damage_t > 0.0
	if tinted != _buff_tint:
		_buff_tint = tinted
		body.modulate = Color(1.5, 0.85, 0.8) if tinted else Color.WHITE
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
		var target: Vector2 = move_input.limit_length(1.0) * move_speed()
		velocity = velocity.lerp(target, clampf(ACCEL * game.events.traction_at(position) * dt, 0.0, 1.0))
	_knock = _knock.lerp(Vector2.ZERO, clampf(10.0 * dt, 0.0, 1.0))
	position = map.move_box(position, (velocity + _knock) * dt, BOX_R, map.BLOCK_PLAYER)


func move_speed() -> float:
	return SPEED * speed_mult * game.events.player_speed * (GameData.SPEED_BUFF if buff_speed_t > 0.0 else 1.0)


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
	# 回旋镖扔出去后手里是空的
	gun.visible = not bool(stats[weapon_id].get("returns", false)) or int(weapon_state[weapon_id]["mag"]) > 0


func switch_weapon(id: String) -> void:
	if id == weapon_id:
		return
	if not owns_weapon(id):
		if _no_ammo_note <= 0.0:
			_no_ammo_note = 0.8
			game.fx.text(position + Vector2(0, -22), "%s 未解锁" % GameData.WEAPONS[id]["name"], Color("#ff8060"))
			Sfx.play("deny")
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
	if reload_t > 0.0 or int(st["mag"]) >= mag_size() or buff_ammo_t > 0.0:
		return
	if bool(stats[weapon_id].get("returns", false)):
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
	var s: Dictionary = stats[weapon_id]
	var returns := bool(s.get("returns", false))
	# 无限弹药对回旋镖无效：手里没镖就是没镖
	var free_shot := buff_ammo_t > 0.0 and not returns
	if int(st["mag"]) <= 0 and not free_shot:
		cooldown = 0.18
		if not returns:
			Sfx.play("empty")
			start_reload()
		return
	if not free_shot:
		st["mag"] = int(st["mag"]) - 1
	cooldown = float(s["cooldown"])
	var muzzle := muzzle_pos()
	_fire_mode(s, muzzle, float(s["damage"]) * damage_mult())
	if s.has("casing"):
		game.fx.casing(position + Vector2(0, -HAND_H), aim, s["casing"] == "red")
	game.add_shake(float(s["shake"]))
	game.kick_camera(aim * float(s["recoil"]))
	recoil_px = float(s["recoil"])
	fired_kick = minf(fired_kick + 0.35, 1.0)
	velocity -= aim * float(s["recoil"]) * 6.0
	Sfx.play(String(s["sfx"]))
	if int(st["mag"]) <= 0:
		start_reload()


func _fire_mode(s: Dictionary, muzzle: Vector2, damage: float) -> void:
	var mode := String(s.get("mode", "bullet"))
	var flash := String(s.get("flash", ""))
	if flash != "none" and flash != "flame":
		game.fx.muzzle_flash(muzzle, aim, bool(s.get("big_flash", false)), flash)
	match mode:
		"beam":
			game.ordnance.beam(muzzle, aim, float(s["range"]), damage, float(s["knock"]), int(s["pierce"]))
		"flame":
			game.ordnance.flame(muzzle, aim, float(s["range"]), float(s["cone"]), damage)
		"lob":
			game.ordnance.lob("grenade", muzzle, lob_target(float(s["range"])), damage, float(s["radius"]))
		"arc":
			game.ordnance.arc(muzzle, aim, float(s["range"]), damage, int(s["chain"]), float(s["jump"]), float(s["knock"]))
		"boomerang":
			game.ordnance.boomerang(muzzle, aim, float(s["speed"]), float(s["range"]), damage, float(s["knock"]))
		_:
			var spread := deg_to_rad(float(s["spread"]))
			for i in int(s["pellets"]):
				var d := aim.rotated(randf_range(-spread, spread))
				var bullet_speed := float(s["speed"]) * randf_range(0.92, 1.05)
				var b: Variant = game.bullets.fire(muzzle, d * bullet_speed, damage, float(s["knock"]), float(s["life"]), int(s["pierce"]), Color(String(s["color"])), true)
				b.chill = float(s.get("chill", 0.0))


## 回旋镖飞回手里。
func catch_boomerang() -> void:
	var st: Dictionary = weapon_state["boomerang"]
	st["mag"] = mini(int(st["mag"]) + 1, int(stats["boomerang"]["mag"]))


# ---------------------------------------------------------------------------
# 道具
# ---------------------------------------------------------------------------

func use_item(id: String) -> bool:
	if int(items.get(id, 0)) <= 0:
		if _no_ammo_note <= 0.0:
			_no_ammo_note = 0.8
			game.fx.text(position + Vector2(0, -22), "没有%s" % GameData.ITEMS[id]["name"] if id != "" else "没有道具", Color("#ff8060"))
			Sfx.play("deny")
		return false
	if not game.ordnance.use_item(id, self):
		Sfx.play("deny")
		return false
	items[id] = int(items[id]) - 1
	if id == selected_item and int(items[id]) <= 0:
		cycle_item()
	return true


## 切到下一种还有存货的道具；全都没有就不动。
func cycle_item() -> void:
	var order := GameData.ITEM_ORDER
	var i := order.find(selected_item)
	for k in order.size():
		i = (i + 1) % order.size()
		if int(items[order[i]]) > 0:
			if order[i] != selected_item:
				selected_item = order[i]
				Sfx.play("ui_click", -6.0)
			return


## 捡到或买到道具。已带满时返回 false。
func add_item(id: String, amount: int) -> bool:
	var cap := int(GameData.ITEMS[id]["max"])
	if int(items[id]) >= cap:
		return false
	items[id] = mini(int(items[id]) + amount, cap)
	if int(items[selected_item]) <= 0:
		selected_item = id
	return true


func refill_all(ammo_drops: int) -> void:
	reload_t = 0.0
	for id: String in owned_weapons():
		var st: Dictionary = weapon_state[id]
		if bool(stats[id].get("returns", false)):
			continue
		st["mag"] = int(stats[id]["mag"])
		if int(st["reserve"]) >= 0:
			st["reserve"] = int(st["reserve"]) + int(GameData.WEAPONS[id].get("ammo_drop", 0)) * ammo_drops


func start_inf_ammo(seconds: float) -> void:
	buff_ammo_t = seconds
	reload_t = 0.0
	queue_redraw()


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
	var soaked := minf(armor, amount)
	armor -= soaked
	hp -= amount - soaked
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
	hp -= amount * dot_mult
	game.hud.flash_dot()
	if hp <= 0.0:
		hp = 0.0
		invuln = 0.0
		take_damage(1.0)


## Boss 战利品：捡到立刻生效。
func apply_trophy(id: String) -> void:
	match id:
		"heart":
			max_hp += GameData.TROPHY_HP
			hp = max_hp
		"serum":
			dot_mult = GameData.TROPHY_DOT
		"crown":
			game.score += GameData.TROPHY_SCORE


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)


func _draw() -> void:
	if reload_t > 0.0:
		var ratio := 1.0 - reload_t / reload_total
		draw_rect(Rect2(-8, -22, 16, 3), Color(0, 0, 0, 0.85))
		draw_rect(Rect2(-7, -21, 14.0 * ratio, 1), Color("#f0d050"))
