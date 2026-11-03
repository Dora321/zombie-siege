extends Node2D
## 所有一次性特效：血滴、碎块、弹壳、枪口火光、爆炸、飘字、残影。
## 集中用数组模拟并绘制；落地的粒子会被印到贴花层，永久留在地上。

const MAX_PARTICLES := 520
## 枪口火光配色：内芯、外焰、地面辉光、火星。
const FLASH_TINTS := {
	"": ["#fff8d0", "#ffb040", Color(1.0, 0.8, 0.4, 0.14), "#ffd870"],
	"sniper": ["#fff4f0", "#ff6a50", Color(1.0, 0.4, 0.3, 0.2), "#ffb0a0"],
	"smoke": ["#f0e8c8", "#b8a880", Color(0.9, 0.85, 0.6, 0.1), "#a0a098"],
	"arc": ["#f0faff", "#60a8ff", Color(0.4, 0.7, 1.0, 0.22), "#a0d8ff"],
	"cryo": ["#f0ffff", "#90e4ff", Color(0.6, 0.9, 1.0, 0.18), "#d0f8ff"],
}

class P:
	var x: float
	var y: float
	var z: float
	var vx: float
	var vy: float
	var vz: float
	var life: float
	var size: int
	var color: Color
	var tex: Texture2D
	var stamp_img: Image
	var stamp_px: bool
	var tink: bool
	var gravity: float
	var bounces: int


class Flash:
	var pos: Vector2
	var dir: Vector2
	var t: float
	var big: bool
	var core: Color
	var edge: Color
	var glow: Color


class Blast:
	var pos: Vector2
	var r: float
	var t: float
	var dur: float


class Ring:
	var pos: Vector2
	var r: float
	var t: float
	var dur: float
	var color: Color


class Ghost:
	var tex: Texture2D
	var pos: Vector2
	var flip: bool
	var color: Color
	var t: float
	var dur: float


class Floater:
	var pos: Vector2
	var text: String
	var color: Color
	var t: float
	var cjk: bool


var game: Node
var decals: Node2D
var particles: Array[P] = []
var flashes: Array[Flash] = []
var blasts: Array[Blast] = []
var rings: Array[Ring] = []
var ghosts: Array[Ghost] = []
var floaters: Array[Floater] = []


func setup(g: Node, d: Node2D) -> void:
	game = g
	decals = d


func _spawn() -> P:
	if particles.size() >= MAX_PARTICLES:
		# 满了就把最老的粒子直接落地
		var old := particles[0]
		_land(old)
		particles[0] = particles[particles.size() - 1]
		particles.pop_back()
	var p := P.new()
	p.z = 0.0
	p.life = 1.0
	p.size = 1
	p.gravity = 240.0
	p.color = Color.WHITE
	p.stamp_px = false
	p.tink = false
	p.bounces = 0
	particles.append(p)
	return p


func _land(p: P) -> void:
	if p.stamp_img != null:
		decals.stamp(p.stamp_img, Vector2(p.x, p.y))
	elif p.stamp_px:
		decals.stamp_pixel(Vector2(p.x, p.y), p.color)


# ---------------------------------------------------------------------------
# 对外接口
# ---------------------------------------------------------------------------

func blood_hit(pos: Vector2, dir: Vector2, count: int, color: Color) -> void:
	for i in mini(count, 12):
		var p := _spawn()
		p.x = pos.x
		p.y = pos.y + 7.0
		p.z = 7.0
		var a := dir.angle() + randf_range(-0.9, 0.9)
		var s := randf_range(25.0, 95.0)
		p.vx = cos(a) * s
		p.vy = sin(a) * s * 0.7
		p.vz = randf_range(10.0, 70.0)
		p.size = 1 if randf() < 0.75 else 2
		p.color = color if randf() < 0.7 else color.darkened(0.25)
		p.life = 1.2
		p.stamp_px = true


func gibs(kind: String, pos: Vector2, dir: Vector2) -> void:
	var pieces: Array = Art.gib_sets.get(kind, [])
	var big := kind == "tank" or GameData.BOSSES.has(kind)
	for piece: Dictionary in pieces:
		var p := _spawn()
		p.x = pos.x + randf_range(-5, 5)
		p.y = pos.y + randf_range(-3, 3)
		p.z = randf_range(3.0, 12.0)
		var a := dir.angle() + randf_range(-1.5, 1.5)
		var s := randf_range(30.0, 130.0 if not big else 170.0)
		p.vx = cos(a) * s
		p.vy = sin(a) * s * 0.75
		p.vz = randf_range(50.0, 130.0)
		p.tex = piece["tex"]
		p.stamp_img = piece["img"]
		p.life = 2.2
	var blood_color := Color(String(GameData.ZOMBIES.get(kind, {"blood": "#8c1c1c"})["blood"]))
	blood_hit(pos + Vector2(0, -6), dir, 12, blood_color)
	blood_hit(pos + Vector2(0, -6), dir.rotated(PI * 0.5), 8, blood_color)


func casing(pos: Vector2, aim: Vector2, shell: bool) -> void:
	var p := _spawn()
	p.x = pos.x
	p.y = pos.y + 7.0
	p.z = 7.0
	var side := aim.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
	var a := (side - aim * 0.4).normalized()
	p.vx = a.x * randf_range(30, 60)
	p.vy = a.y * randf_range(20, 45)
	p.vz = randf_range(55, 85)
	var key := "red" if shell else "brass"
	p.tex = Art.shell_tex[key]
	p.stamp_img = Art.shell_img[key]
	p.life = 1.6
	p.tink = true


func muzzle_flash(pos: Vector2, dir: Vector2, big: bool, tint := "") -> void:
	var f := Flash.new()
	f.pos = pos
	f.dir = dir
	f.t = 0.05 if not big else 0.075
	f.big = big
	var pal: Array = FLASH_TINTS[tint]
	f.core = Color(pal[0])
	f.edge = Color(pal[1])
	f.glow = pal[2]
	flashes.append(f)
	for i in (5 if big else 2):
		var p := _spawn()
		p.x = pos.x
		p.y = pos.y + 7.0
		p.z = 7.0
		var a := dir.angle() + randf_range(-0.4, 0.4)
		var s := randf_range(90, 200)
		p.vx = cos(a) * s
		p.vy = sin(a) * s
		p.vz = randf_range(-5, 15)
		p.color = Color(pal[3])
		p.life = randf_range(0.05, 0.13)
		p.gravity = 0.0


## 火焰喷射器的一股火：粒子贴着锥形飞，越远越暗。
func flame(pos: Vector2, dir: Vector2, length: float, cone: float) -> void:
	for i in 4:
		var p := _spawn()
		p.x = pos.x
		p.y = pos.y + 7.0
		p.z = 7.0
		var a := dir.angle() + randf_range(-cone, cone)
		var life := randf_range(0.14, 0.28)
		var s := length / life * randf_range(0.55, 1.0)
		p.vx = cos(a) * s
		p.vy = sin(a) * s
		p.vz = randf_range(0, 20)
		p.gravity = 0.0
		p.size = 3 if i == 0 else 2
		p.color = [Color("#fff0a0"), Color("#ffb030"), Color("#ff7020"), Color("#e04818")][i]
		p.life = life


## 燃烧僵尸身上冒的火星。
func ember(pos: Vector2) -> void:
	var p := _spawn()
	p.x = pos.x + randf_range(-3, 3)
	p.y = pos.y + 7.0
	p.z = 7.0 + randf_range(-3, 3)
	p.vx = randf_range(-6, 6)
	p.vy = 0.0
	p.vz = randf_range(20, 40)
	p.gravity = 0.0
	p.size = 2 if randf() < 0.3 else 1
	p.color = Color("#ffb030") if randf() < 0.6 else Color("#ff6020")
	p.life = randf_range(0.2, 0.4)


## 电弧命中点的蓝色火花。
func zap(pos: Vector2) -> void:
	for i in 5:
		var p := _spawn()
		p.x = pos.x
		p.y = pos.y + 7.0
		p.z = 7.0
		var a := randf() * TAU
		p.vx = cos(a) * randf_range(30, 90)
		p.vy = sin(a) * randf_range(30, 90)
		p.vz = randf_range(0, 30)
		p.gravity = 0.0
		p.color = Color("#f0faff") if i % 2 == 0 else Color("#60a8ff")
		p.life = randf_range(0.08, 0.18)


## 冰碴。
func frost(pos: Vector2) -> void:
	for i in 3:
		var p := _spawn()
		p.x = pos.x
		p.y = pos.y + 7.0
		p.z = 7.0
		var a := randf() * TAU
		p.vx = cos(a) * randf_range(15, 45)
		p.vy = sin(a) * randf_range(10, 30)
		p.vz = randf_range(20, 50)
		p.gravity = 160.0
		p.color = Color("#e0f8ff") if i % 2 == 0 else Color("#90e4ff")
		p.life = randf_range(0.2, 0.35)


## 向外扩散的一圈光环。
func ring(pos: Vector2, radius: float, dur: float, color: Color) -> void:
	var r := Ring.new()
	r.pos = pos
	r.r = radius
	r.t = dur
	r.dur = dur
	r.color = color
	rings.append(r)


func spark(pos: Vector2) -> void:
	for i in 4:
		var p := _spawn()
		p.x = pos.x
		p.y = pos.y + 7.0
		p.z = 7.0
		var a := randf() * TAU
		p.vx = cos(a) * randf_range(20, 70)
		p.vy = sin(a) * randf_range(20, 70)
		p.vz = randf_range(10, 50)
		p.color = Color("#ffe8a0") if i % 2 == 0 else Color("#c0c0c8")
		p.life = randf_range(0.1, 0.25)


func dust(pos: Vector2, count: int) -> void:
	for i in count:
		var p := _spawn()
		p.x = pos.x + randf_range(-4, 4)
		p.y = pos.y + randf_range(-2, 2)
		p.z = randf_range(0, 3)
		var a := randf() * TAU
		p.vx = cos(a) * randf_range(8, 30)
		p.vy = sin(a) * randf_range(4, 18)
		p.vz = randf_range(8, 28)
		p.gravity = 40.0
		p.color = Color(0.72, 0.68, 0.58, 0.8)
		p.size = 2 if randf() < 0.4 else 1
		p.life = randf_range(0.25, 0.5)


func debris(pos: Vector2, kind: String) -> void:
	var colors: Array = [Color("#9a6a3c"), Color("#6c4826"), Color("#a89a70")]
	if kind != "barricade":
		colors = [Color("#a6a294"), Color("#8d5f48"), Color("#6d4836")]
	for i in 14:
		var p := _spawn()
		p.x = pos.x + randf_range(-6, 6)
		p.y = pos.y + 8.0
		p.z = 8.0
		var a := randf() * TAU
		var s := randf_range(20, 90)
		p.vx = cos(a) * s
		p.vy = sin(a) * s * 0.7
		p.vz = randf_range(40, 110)
		p.size = 2
		p.color = colors[i % colors.size()]
		p.life = 1.2
		p.stamp_px = true


func smoke(pos: Vector2, fire: bool) -> void:
	var p := _spawn()
	p.x = pos.x
	p.y = pos.y + 30.0
	p.z = 30.0
	p.vx = randf_range(-6, 8)
	p.vy = 0.0
	p.vz = randf_range(14, 26)
	p.gravity = 0.0
	p.size = 3
	var ember := fire and randf() < 0.35
	p.color = Color("#ff9030") if ember else Color(0.25, 0.25, 0.27, 0.65)
	p.life = randf_range(0.5, 1.0)


## 淬火冒的白汽：和烟一样往上飘，颜色浅。
func steam(pos: Vector2) -> void:
	var p := _spawn()
	p.x = pos.x
	p.y = pos.y + 20.0
	p.z = 20.0
	p.vx = randf_range(-5, 5)
	p.vy = 0.0
	p.vz = randf_range(18, 30)
	p.gravity = 0.0
	p.size = 2
	p.color = Color(0.9, 0.92, 0.96, 0.8)
	p.life = randf_range(0.35, 0.7)


func acid_burst(pos: Vector2) -> void:
	for i in 8:
		var p := _spawn()
		p.x = pos.x
		p.y = pos.y
		var a := randf() * TAU
		p.vx = cos(a) * randf_range(15, 55)
		p.vy = sin(a) * randf_range(10, 35)
		p.vz = randf_range(30, 70)
		p.color = Color("#a8e040")
		p.life = 0.6


func explosion(pos: Vector2, radius: float) -> void:
	var b := Blast.new()
	b.pos = pos
	b.r = radius
	b.dur = 0.32
	b.t = 0.32
	blasts.append(b)
	for i in 34:
		var p := _spawn()
		p.x = pos.x
		p.y = pos.y + 6.0
		p.z = 6.0
		var a := randf() * TAU
		var s := randf_range(40.0, radius * 4.5)
		p.vx = cos(a) * s
		p.vy = sin(a) * s * 0.75
		p.vz = randf_range(20, 110)
		p.size = 2 if i % 3 == 0 else 1
		p.color = [Color("#fff0a0"), Color("#ffb030"), Color("#e05020"), Color("#403c3c")][i % 4]
		p.life = randf_range(0.25, 0.7)
	for i in 12:
		smoke(pos + Vector2(randf_range(-radius * 0.5, radius * 0.5), randf_range(-radius * 0.4, radius * 0.4) - 30.0), false)


func ghost(tex: Texture2D, pos: Vector2, flip: bool, color: Color, dur: float) -> void:
	if tex == null:
		return
	var g := Ghost.new()
	g.tex = tex
	g.pos = pos
	g.flip = flip
	g.color = color
	g.t = dur
	g.dur = dur
	ghosts.append(g)


func number(pos: Vector2, value: int, color: Color) -> void:
	if floaters.size() > 50:
		return
	var f := Floater.new()
	f.pos = pos
	f.text = str(value)
	f.color = color
	f.t = 0.5
	f.cjk = false
	floaters.append(f)


func text(pos: Vector2, content: String, color: Color) -> void:
	var f := Floater.new()
	f.pos = pos
	f.text = content
	f.color = color
	f.t = 1.1
	f.cjk = true
	floaters.append(f)


func coin_text(pos: Vector2, amount: int) -> void:
	var f := Floater.new()
	f.pos = pos
	f.text = "+" + str(amount)
	f.color = Color("#ffe060")
	f.t = 0.6
	f.cjk = false
	floaters.append(f)


# ---------------------------------------------------------------------------
# 模拟与绘制
# ---------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var i := particles.size() - 1
	while i >= 0:
		var p := particles[i]
		p.life -= dt
		p.x += p.vx * dt
		p.y += p.vy * dt
		p.z += p.vz * dt
		p.vz -= p.gravity * dt
		var finished := p.life <= 0.0
		if p.gravity > 0.0 and p.z <= 0.0 and p.vz < 0.0:
			p.z = 0.0
			p.bounces += 1
			if p.tink and p.bounces == 1:
				Sfx.play("casing", -13.0, 0.15)
			if (p.tex != null) and p.bounces < 3:
				p.vz = -p.vz * 0.42
				p.vx *= 0.55
				p.vy *= 0.55
			else:
				finished = true
		if finished:
			if p.gravity > 0.0:
				_land(p)
			particles[i] = particles[particles.size() - 1]
			particles.pop_back()
		i -= 1
	i = flashes.size() - 1
	while i >= 0:
		flashes[i].t -= dt
		if flashes[i].t <= 0.0:
			flashes.remove_at(i)
		i -= 1
	i = blasts.size() - 1
	while i >= 0:
		blasts[i].t -= dt
		if blasts[i].t <= 0.0:
			blasts.remove_at(i)
		i -= 1
	i = rings.size() - 1
	while i >= 0:
		rings[i].t -= dt
		if rings[i].t <= 0.0:
			rings.remove_at(i)
		i -= 1
	i = ghosts.size() - 1
	while i >= 0:
		ghosts[i].t -= dt
		if ghosts[i].t <= 0.0:
			ghosts.remove_at(i)
		i -= 1
	i = floaters.size() - 1
	while i >= 0:
		var f := floaters[i]
		f.t -= dt
		f.pos.y -= dt * (26.0 if not f.cjk else 14.0)
		if f.t <= 0.0:
			floaters.remove_at(i)
		i -= 1
	queue_redraw()


func _draw() -> void:
	for f in flashes:
		_draw_flash(f)
	for g in ghosts:
		var c := g.color
		c.a *= g.t / g.dur
		var size := Vector2(g.tex.get_size())
		var rect := Rect2(g.pos.round(), Vector2(-size.x if g.flip else size.x, size.y))
		if g.flip:
			rect.position.x += size.x
		draw_texture_rect(g.tex, rect, false, c)
	for p in particles:
		var at := Vector2(roundf(p.x), roundf(p.y - p.z))
		if p.tex != null:
			draw_texture(p.tex, at)
		else:
			draw_rect(Rect2(at, Vector2(p.size, p.size)), p.color)
	for b in blasts:
		_draw_blast(b)
	for r in rings:
		var ratio := 1.0 - r.t / r.dur
		var c := r.color
		c.a = 1.0 - ratio
		draw_circle(r.pos.round(), r.r * ratio, Color(c.r, c.g, c.b, c.a * 0.25))
		draw_arc(r.pos.round(), r.r * ratio, 0.0, TAU, 32, c, 2.0)
	for f in floaters:
		var c := f.color
		c.a = clampf(f.t * 4.0, 0.0, 1.0)
		if f.cjk:
			Art.draw_text(self, f.text, f.pos, 12, c, 1)
		else:
			var w := Art.tiny_width(f.text)
			Art.draw_tiny(self, f.text, f.pos + Vector2(-w * 0.5 + 1, 1), Color(0, 0, 0, c.a))
			Art.draw_tiny(self, f.text, f.pos + Vector2(-w * 0.5, 0), c)


func _draw_flash(f: Flash) -> void:
	var length := 11.0 if f.big else 6.0
	var side := f.dir.orthogonal()
	var at := f.pos.round()
	# 地面上一圈昏黄的火光
	draw_circle(at, 13.0 if f.big else 8.0, f.glow)
	var steps := int(length)
	for s in steps:
		var ratio := float(s) / steps
		var half := int((1.0 - ratio) * (3.0 if f.big else 2.0))
		var p := at + f.dir * s
		draw_rect(Rect2((p - side * half).round(), Vector2(1, 1)), f.edge)
		draw_rect(Rect2((p + side * half).round(), Vector2(1, 1)), f.edge)
		draw_rect(Rect2(p.round(), Vector2(1, 1)), f.core)
	draw_rect(Rect2((at - side * 3.0).round(), Vector2(1, 1)), f.edge.lightened(0.3))
	draw_rect(Rect2((at + side * 3.0).round(), Vector2(1, 1)), f.edge.lightened(0.3))


func _draw_blast(b: Blast) -> void:
	var ratio := 1.0 - b.t / b.dur
	var at := b.pos.round()
	if ratio < 0.2:
		draw_circle(at, b.r * (0.5 + ratio * 2.0), Color("#fff8e0"))
	elif ratio < 0.5:
		draw_circle(at, b.r * 0.85, Color("#ffb030"))
		draw_circle(at, b.r * 0.55, Color("#fff0a0"))
	else:
		var fade := 1.0 - (ratio - 0.5) * 2.0
		draw_arc(at, b.r * (0.8 + ratio * 0.3), 0, TAU, 28, Color(1.0, 0.55, 0.2, fade), 2.0)
		draw_circle(at, b.r * 0.6 * fade, Color(0.25, 0.22, 0.22, fade * 0.8))
