extends Node2D
## 随机事件：天气（夜战、暴雨、大雾）持续整波，突发（补给空投、先遣尸群、电磁干扰）一次性触发。
## 每波开打前定好有什么事件，数值表在 GameData.EVENTS，别的系统只读这里的倍率。

class Crate:
	var pos: Vector2
	var fall: float
	var life: float
	var age: float


const FALL_TIME := 2.6
const FADE_SPEED := 0.8
const PICKUP_R := 14.0
const INCIDENT_DELAY := Vector2(9.0, 18.0)
const WET_BLOBS := 16
const WET_RANGE := 16
const VEIL_SIZE := Vector2(512, 302)
const SIDES := {"top": "北面", "bottom": "南面", "left": "西面", "right": "东面"}
## 像素化的遮罩：最多三个光圈，光圈外按 veil 着色；drift 让大雾缓缓飘动。
const VEIL_SHADER := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(512.0, 302.0);
uniform vec4 veil = vec4(0.0);
uniform vec3 lights[3];
uniform float drift = 0.0;
uniform float clock = 0.0;
void fragment() {
	vec2 p = floor(UV * rect_size / 2.0) * 2.0 + 1.0;
	float a = 1.0;
	for (int i = 0; i < 3; i++) {
		if (lights[i].z > 0.0) {
			a = min(a, smoothstep(0.55, 1.0, distance(p, lights[i].xy) / lights[i].z));
		}
	}
	float dither = mod(p.x + p.y, 4.0) / 4.0;
	a = floor(a * 5.0 + dither) / 5.0;
	float wave = sin(p.x * 0.031 + clock * 0.33) + sin(p.y * 0.047 - clock * 0.21) + sin((p.x + p.y) * 0.019 + clock * 0.13);
	a *= 1.0 - drift * (0.2 + 0.066 * wave);
	COLOR = vec4(veil.rgb, veil.a * a);
}
"""
const VEILS := {
	"night": {"color": Color(0.02, 0.03, 0.1, 0.9), "player": 96.0, "aim": 58.0, "base": 66.0, "drift": 0.0},
	"storm": {"color": Color(0.08, 0.12, 0.22, 0.26), "player": 0.0, "aim": 0.0, "base": 0.0, "drift": 0.0},
	"fog": {"color": Color(0.66, 0.7, 0.72, 0.94), "player": 165.0, "aim": 0.0, "base": 0.0, "drift": 1.0},
}

var game: Node
var map: Node2D
var enabled := true
## 测试用：每波固定触发这个事件。
var forced := ""
var weather := ""
var crates: Array[Crate] = []
var jam_t := 0.0
var overclock_t := 0.0

var zombie_speed := 1.0
var player_speed := 1.0
var splash_mult := 1.0
var arc_mult := 1.0
var pool_decay := 1.0
var aggro_mult := 1.0
var turret_range := 1.0
var coin_mult := 1.0

var _rng: RandomNumberGenerator
var _plan_wave := 0
var _plan_weather := ""
var _plan_incident := ""
var _last_weather := ""
var _last_incident := ""
var _quiet_waves := 0
var _incident := ""
var _incident_t := -1.0
var _warn_t := -1.0
var _wet := PackedByteArray()
var _wet_on := false
var _veil_id := ""
var _veil_fade := 0.0
var _clock := 0.0
var _thunder_t := 7.0
var _plane_t := -1.0
var _plane_dur := 1.0
var _plane_y := 0.0
var _plane_x0 := 0.0
var _vanguard_side := ""
var _veil: ColorRect
var _veil_mat: ShaderMaterial
var _sky: Node2D


func setup(g: Node, m: Node2D, rng: RandomNumberGenerator) -> void:
	game = g
	map = m
	_rng = rng
	_wet.resize(m.W * m.H)
	_wet.fill(0)
	var shader := Shader.new()
	shader.code = VEIL_SHADER
	_veil_mat = ShaderMaterial.new()
	_veil_mat.shader = shader
	_veil_mat.set_shader_parameter("rect_size", VEIL_SIZE)
	_veil = ColorRect.new()
	_veil.size = VEIL_SIZE
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.material = _veil_mat
	_veil.z_index = 3
	_veil.visible = false
	add_child(_veil)
	# 雨丝、降落伞和运输机盖在遮罩上面（Boss 红圈所在的层 z=5 也在遮罩之上）
	_sky = Node2D.new()
	_sky.z_index = 4
	add_child(_sky)
	_sky.draw.connect(_draw_sky)


# ---------------------------------------------------------------------------
# 排期
# ---------------------------------------------------------------------------

## 给某一波定事件：连续两波没事件就保底一个；同类事件不连着重复。
func plan_wave(wave: int) -> void:
	_plan_wave = wave
	_plan_weather = ""
	_plan_incident = ""
	if not enabled:
		return
	if forced != "":
		if GameData.EVENTS[forced]["slot"] == "weather":
			_plan_weather = forced
		else:
			_plan_incident = forced
		return
	if _rng.randf() < GameData.EVENT_WEATHER_CHANCE:
		_plan_weather = _pick("weather", wave, _last_weather)
	if _rng.randf() < GameData.EVENT_INCIDENT_CHANCE or (_quiet_waves >= 1 and _plan_weather == ""):
		_plan_incident = _pick("incident", wave, _last_incident)
	if _plan_weather != "":
		_last_weather = _plan_weather
	if _plan_incident != "":
		_last_incident = _plan_incident
	_quiet_waves = 0 if _plan_weather != "" or _plan_incident != "" else _quiet_waves + 1


func _pick(slot: String, wave: int, last: String) -> String:
	var pool: Array[String] = []
	for id: String in GameData.EVENT_ORDER:
		if GameData.EVENTS[id]["slot"] == slot and GameData.event_allowed(id, wave):
			pool.append(id)
	if pool.size() > 1:
		pool.erase(last)
	return "" if pool.is_empty() else pool[_rng.randi() % pool.size()]


func planned_weather() -> String:
	return _plan_weather


func planned_incident() -> String:
	return _plan_incident


## 商店里的预报：只报天气和先遣尸群，空投和干扰算突发。
func forecast_text() -> String:
	var parts: Array[String] = []
	if _plan_weather != "":
		parts.append(String(GameData.EVENTS[_plan_weather]["name"]))
	if _plan_incident == "vanguard":
		parts.append(String(GameData.EVENTS[_plan_incident]["name"]))
	return "" if parts.is_empty() else "  预报：" + "、".join(parts)


func on_countdown(wave: int) -> void:
	if _plan_wave != wave:
		plan_wave(wave)
	_incident = _plan_incident
	_incident_t = -1.0
	_warn_t = -1.0
	if _plan_weather != "":
		_start_weather(_plan_weather)
	if _incident == "vanguard":
		_warn_vanguard()


func on_combat() -> void:
	if _incident != "" and _incident != "vanguard":
		_incident_t = _rng.randf_range(INCIDENT_DELAY.x, INCIDENT_DELAY.y)


## 波次结束：天气散去、没发生的突发取消。地上的补给箱留着，商店里不计时。
func on_wave_cleared() -> void:
	_incident = ""
	_incident_t = -1.0
	_warn_t = -1.0
	jam_t = 0.0
	overclock_t = 0.0
	_clear_weather()
	plan_wave(game.wave + 1)


# ---------------------------------------------------------------------------
# 天气
# ---------------------------------------------------------------------------

func _start_weather(id: String) -> void:
	var spec: Dictionary = GameData.EVENTS[id]
	weather = id
	zombie_speed = float(spec.get("zombie_speed", 1.0))
	player_speed = float(spec.get("player_speed", 1.0))
	splash_mult = float(spec.get("splash", 1.0))
	arc_mult = float(spec.get("arc", 1.0))
	pool_decay = float(spec.get("pool_decay", 1.0))
	aggro_mult = float(spec.get("aggro", 1.0))
	turret_range = float(spec.get("turret_range", 1.0))
	coin_mult = float(spec.get("coin_mult", 1.0))
	_veil_id = id
	_veil.visible = true
	if id == "storm":
		_lay_puddles()
	_warn(id, String(spec["sub"]))
	Harness.note("事件：第 %d 波 %s" % [game.wave, spec["name"]])


func _clear_weather() -> void:
	weather = ""
	zombie_speed = 1.0
	player_speed = 1.0
	splash_mult = 1.0
	arc_mult = 1.0
	pool_decay = 1.0
	aggro_mult = 1.0
	turret_range = 1.0
	coin_mult = 1.0
	if _wet_on:
		_wet.fill(0)
		_wet_on = false
		queue_redraw()


## 在基地周围铺水洼，只铺在空地上。
func _lay_puddles() -> void:
	_wet.fill(0)
	var center: Vector2i = Vector2i(map.base_x0 + 2, map.base_y0 + 1)
	for blob in WET_BLOBS:
		var at := center + Vector2i(_rng.randi_range(-WET_RANGE, WET_RANGE), _rng.randi_range(-WET_RANGE, WET_RANGE))
		var rx := _rng.randi_range(1, 3)
		var ry := _rng.randi_range(1, 2)
		for y in range(at.y - ry, at.y + ry + 1):
			for x in range(at.x - rx, at.x + rx + 1):
				if map.in_bounds(x, y) and map.flags[map.idx(x, y)] == 0 and Vector2(float(x - at.x) / (rx + 0.5), float(y - at.y) / (ry + 0.5)).length() <= 1.0:
					_wet[map.idx(x, y)] = 1
	_wet_on = true
	queue_redraw()


func is_wet(pos: Vector2) -> bool:
	return _wet_on and _wet[map.cell_of(pos)] == 1


func traction_at(pos: Vector2) -> float:
	return GameData.WET_TRACTION if is_wet(pos) else 1.0


func zombie_speed_at(pos: Vector2) -> float:
	return zombie_speed * GameData.WET_ZOMBIE_SPEED if is_wet(pos) else zombie_speed


func tint_color() -> Color:
	if weather == "":
		return Color.WHITE
	return Color(String(GameData.EVENTS[weather].get("tint", "#ffffff")))


# ---------------------------------------------------------------------------
# 突发事件
# ---------------------------------------------------------------------------

func _warn(id: String, sub: String) -> void:
	var spec: Dictionary = GameData.EVENTS[id]
	game.hud.event_warn(String(spec["name"]), sub, 4.0, Color(String(spec["color"])))
	Sfx.play("charge_warn", -6.0, 0.0)


func _warn_vanguard() -> void:
	var sides: Array = SIDES.keys()
	_vanguard_side = sides[_rng.randi() % sides.size()]
	var spec: Dictionary = GameData.EVENTS["vanguard"]
	_warn("vanguard", String(spec["sub"]) % SIDES[_vanguard_side])
	_warn_t = float(spec["warn_t"])
	game.extend_countdown(GameData.VANGUARD_EXTRA_TIME)
	Harness.note("事件：第 %d 波 先遣尸群，从%s来" % [game.wave, SIDES[_vanguard_side]])


## 开始预警，warn_t 秒后真正触发。测试也从这里进。
func begin_incident(id: String) -> void:
	# 没有炮塔时电磁干扰没意义，换成补给空投
	if id == "emp" and game.turrets.is_empty():
		id = "airdrop"
	_incident = id
	_incident_t = -1.0
	var spec: Dictionary = GameData.EVENTS[id]
	_warn_t = float(spec["warn_t"])
	_warn(id, String(spec["sub"]))
	Harness.note("事件：第 %d 波 %s" % [game.wave, spec["name"]])
	if id == "airdrop":
		_start_plane()


func _fire_incident() -> void:
	match _incident:
		"airdrop":
			for i in 1 + int(game.wave >= 8):
				drop_crate(map.edge_spot(_rng, game.player.position))
		"emp":
			jam_t = GameData.EMP_JAM_TIME
			game.add_shake(0.4)
			game.hud.screen_flash(0.25, Color("#a0e8ff"))
			Sfx.play("arc", -3.0)
		"vanguard":
			game.spawn_vanguard(_vanguard_side, GameData.VANGUARD_COUNT + game.wave / 4)
	_incident = ""


func drop_crate(at: Vector2) -> void:
	var c := Crate.new()
	c.pos = at
	c.fall = FALL_TIME
	c.life = GameData.CRATE_LIFE
	crates.append(c)


func _start_plane() -> void:
	_plane_dur = float(GameData.EVENTS["airdrop"]["warn_t"]) + 2.0
	_plane_t = 0.0
	_plane_x0 = -80.0
	_plane_y = game.player.position.y - 60.0
	Sfx.play("siren", -14.0, 0.0)


func jammed() -> bool:
	return jam_t > 0.0


func turret_rate() -> float:
	return GameData.EMP_OVERCLOCK_RATE if overclock_t > 0.0 else 1.0


## 最近的补给箱（已落地的），测试机器人用。
func nearest_crate(pos: Vector2) -> Variant:
	var best: Variant = null
	var best_d := 1e9
	for c in crates:
		var d := c.pos.distance_to(pos)
		if c.fall <= 0.0 and d < best_d:
			best_d = d
			best = c
	return best


func _open_crate(c: Crate) -> void:
	var total: int = GameData.CRATE_COINS + GameData.CRATE_COINS_PER_WAVE * game.wave
	while total > 0:
		var v := mini(total, 10)
		game.pickups.drop(c.pos, "coin", v)
		total -= v
	game.pickups.drop(c.pos, "ammo", 1)
	game.pickups.drop(c.pos, "item", 1, GameData.CRATE_ITEMS[_rng.randi() % GameData.CRATE_ITEMS.size()])
	if _rng.randf() < 0.4:
		game.pickups.drop(c.pos, "med", 25)
	game.fx.text(c.pos + Vector2(0, -20), "补给到手！", Color("#ffe060"))
	game.fx.dust(c.pos, 8)
	Sfx.play("buy")
	Harness.note("补给箱已拾取")


## HUD 右上角的事件标签。
func chips() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if weather != "":
		var spec: Dictionary = GameData.EVENTS[weather]
		out.append({"text": "%s %s" % [spec["name"], spec["chip"]], "color": Color(String(spec["color"])), "ratio": -1.0})
	if jam_t > 0.0:
		var spec: Dictionary = GameData.EVENTS["emp"]
		out.append({"text": "%s %s" % [spec["name"], spec["chip"]], "color": Color(String(spec["color"])), "ratio": jam_t / GameData.EMP_JAM_TIME})
	elif overclock_t > 0.0:
		out.append({"text": "炮塔过载 射速提升", "color": Color("#70e090"), "ratio": overclock_t / GameData.EMP_OVERCLOCK_TIME})
	var landed: Variant = nearest_crate(game.player.position)
	if landed != null:
		var spec: Dictionary = GameData.EVENTS["airdrop"]
		out.append({"text": "%s %s" % [spec["name"], spec["chip"]], "color": Color(String(spec["color"])), "ratio": landed.life / GameData.CRATE_LIFE})
	return out


# ---------------------------------------------------------------------------
# 每帧
# ---------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_clock += dt
	_tick_incident(dt)
	if game.player_can_act():
		_tick_crates(dt)
	_tick_jam(dt)
	if _plane_t >= 0.0:
		_plane_t += dt
		if _plane_t > _plane_dur:
			_plane_t = -1.0
	_tick_veil(dt)
	if weather == "storm" and game.state == game.State.COMBAT:
		_thunder_t -= dt
		if _thunder_t <= 0.0:
			_thunder_t = _rng.randf_range(9.0, 18.0)
			game.hud.screen_flash(0.16, Color("#c8dcff"))
			Sfx.play("explode", -18.0, 0.25)
	if not crates.is_empty() or _plane_t >= 0.0 or weather == "storm":
		queue_redraw()
	_sky.queue_redraw()


func _tick_incident(dt: float) -> void:
	if _warn_t >= 0.0:
		_warn_t -= dt
		if _warn_t < 0.0:
			_fire_incident()
	if game.state != game.State.COMBAT or _incident_t < 0.0:
		return
	_incident_t -= dt
	# 出怪结束、快打完了还没轮到就立刻触发，不然这波白等
	var ending: bool = game._queue.is_empty() and game.zombies.size() <= 4
	if _incident_t < 0.0 or ending:
		begin_incident(_incident)


func _tick_jam(dt: float) -> void:
	if jam_t > 0.0:
		jam_t -= dt
		if jam_t <= 0.0:
			overclock_t = GameData.EMP_OVERCLOCK_TIME
			game.hud.event_warn("电磁干扰结束", "炮塔过载，射速提升一小会儿", 2.5, Color("#70e090"))
			Sfx.play("reload_done")
	elif overclock_t > 0.0:
		overclock_t -= dt


func _tick_crates(dt: float) -> void:
	var player: Variant = game.player
	var i := crates.size() - 1
	while i >= 0:
		var c := crates[i]
		c.age += dt
		if c.fall > 0.0:
			c.fall -= dt
			if c.fall <= 0.0:
				game.fx.dust(c.pos, 10)
				game.add_shake(0.2)
				Sfx.play("rock_fall", -6.0)
		else:
			c.life -= dt
			if player.alive and player.position.distance_to(c.pos) < PICKUP_R:
				_open_crate(c)
				crates.remove_at(i)
			elif c.life <= 0.0:
				game.fx.text(c.pos + Vector2(0, -16), "补给箱过期了", Color("#c8c4b8"))
				game.fx.dust(c.pos, 6)
				crates.remove_at(i)
		i -= 1


func _tick_veil(dt: float) -> void:
	var goal := 1.0 if weather != "" else 0.0
	_veil_fade = move_toward(_veil_fade, goal, dt * FADE_SPEED)
	if _veil_fade <= 0.0:
		_veil.visible = false
		return
	var spec: Dictionary = VEILS[_veil_id]
	var cam: Vector2 = game.camera.position + game.camera.offset
	_veil.position = (cam - VEIL_SIZE * 0.5).round()
	var color: Color = spec["color"]
	color.a *= _veil_fade
	# 光圈随淡入从大收到小，天黑不是一下子的
	var open := 1.0 + (1.0 - _veil_fade) * 2.0
	var lights := PackedVector3Array()
	lights.append(_light(game.player.position + Vector2(0, -8), float(spec["player"]) * open))
	lights.append(_light(game.player.aim_point, float(spec["aim"]) * open))
	lights.append(_light(game.base.position + Vector2(0, -24), float(spec["base"]) * open))
	_veil_mat.set_shader_parameter("veil", color)
	_veil_mat.set_shader_parameter("lights", lights)
	_veil_mat.set_shader_parameter("drift", float(spec["drift"]))
	_veil_mat.set_shader_parameter("clock", _clock)


func _light(world: Vector2, radius: float) -> Vector3:
	var local := world - _veil.position
	return Vector3(local.x, local.y, radius)


## 当前遮罩的不透明度和光圈，测试用来确认事件真的画出来了。
func veil_alpha() -> float:
	return (VEILS[_veil_id]["color"] as Color).a * _veil_fade if _veil.visible else 0.0


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _wet_on:
		_draw_puddles()
	for c in crates:
		if c.fall > 0.0:
			# 还在天上：地上只有影子和落点圈
			var shrink := 1.0 - c.fall / FALL_TIME
			draw_arc(c.pos, 8.0 + (1.0 - shrink) * 10.0, 0.0, TAU, 20, Color(1.0, 0.88, 0.3, 0.8), 1.0)
			draw_rect(Rect2(c.pos + Vector2(-5, -1), Vector2(10, 3)), Color(0, 0, 0, 0.3 + shrink * 0.3))
			continue
		var flicker: bool = c.life > 8.0 or int(c.age * 6.0) % 2 == 0
		if flicker:
			var tex := Art.supply_tex
			draw_texture(tex, (c.pos - Vector2(tex.get_width() * 0.5, tex.get_height() - 3.0)).round())
		draw_rect(Rect2(c.pos + Vector2(-9, -19), Vector2(18, 2)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(c.pos + Vector2(-9, -19), Vector2(18.0 * c.life / GameData.CRATE_LIFE, 2)), Color("#ffe060"))


func _draw_puddles() -> void:
	var tile: int = map.TILE
	var cam: Vector2 = game.camera.position
	var col := Color(0.34, 0.52, 0.78, 0.42)
	var shine := Color(0.72, 0.86, 1.0, 0.45)
	var x0: int = clampi(int(cam.x - 256.0) / tile, 0, map.W - 1)
	var x1: int = clampi(int(cam.x + 256.0) / tile, 0, map.W - 1)
	var y0: int = clampi(int(cam.y - 150.0) / tile, 0, map.H - 1)
	var y1: int = clampi(int(cam.y + 150.0) / tile, 0, map.H - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if _wet[y * map.W + x] == 0:
				continue
			draw_rect(Rect2(x * tile, y * tile, tile, tile), col)
			var ripple := int(_clock * 2.0 + x * 3 + y * 5) % 6
			draw_rect(Rect2(x * tile + 2 + ripple, y * tile + 4 + (x + y) % 9, 5, 1), shine)


func _draw_sky() -> void:
	var cam: Vector2 = game.camera.position
	if weather == "storm" or (_veil_id == "storm" and _veil_fade > 0.0):
		var top_left := cam - VEIL_SIZE * 0.5
		var col := Color(0.72, 0.84, 1.0, 0.42 * _veil_fade)
		for i in 80:
			var x := fposmod(i * 37.7 - _clock * 90.0, VEIL_SIZE.x)
			var y := fposmod(i * 91.3 + _clock * 430.0, VEIL_SIZE.y)
			var a := top_left + Vector2(x, y)
			_sky.draw_line(a, a + Vector2(-2, 8), col, 1.0)
	if _plane_t >= 0.0:
		_draw_plane()
	for c in crates:
		if c.fall > 0.0:
			var drop := c.fall / FALL_TIME * 150.0
			var at := (c.pos + Vector2(0, -drop)).round()
			_sky.draw_texture(Art.chute_tex, at + Vector2(-12, -28))
			_sky.draw_texture(Art.supply_tex, at + Vector2(-8, -13))


## 运输机飞过的影子，提示空投方向。
func _draw_plane() -> void:
	var x: float = lerpf(_plane_x0, float(map.PIXEL_W) + 80.0, _plane_t / _plane_dur)
	var at := Vector2(x, _plane_y)
	var shade := Color(0.04, 0.04, 0.06, 0.45)
	_sky.draw_rect(Rect2(at + Vector2(-34, -4), Vector2(68, 8)), shade)
	_sky.draw_rect(Rect2(at + Vector2(-8, -30), Vector2(14, 60)), shade)
	_sky.draw_rect(Rect2(at + Vector2(-34, -13), Vector2(8, 26)), shade)
