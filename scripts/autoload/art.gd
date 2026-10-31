extends Node
## 程序化像素美术工厂：所有贴图都在启动时由代码绘制，不依赖任何外部素材。

const DIR_DOWN := 0
const DIR_UP := 1
const DIR_SIDE := 2
const FRAMES := 4
const OUTLINE := Color(0.075, 0.06, 0.09)

## 人形角色的参数。w/h 是画布，hw/hh 头，tw/th 躯干，lh 腿长。
const CHARS := {
	"player": {
		"w": 16, "h": 18, "hw": 6, "hh": 6, "tw": 6, "th": 5, "lh": 3, "zombie": false,
		"skin": "#e8b48c", "hair": "#3f5a34", "shirt": "#3c7ea8", "pants": "#39404f",
		"shoe": "#20202a", "eye": "#1a1a22", "helmet": true,
	},
	"walker": {
		"w": 16, "h": 18, "hw": 6, "hh": 6, "tw": 6, "th": 5, "lh": 3, "zombie": true,
		"skin": "#86a862", "hair": "#3a3226", "shirt": "#5c6c9a", "pants": "#4d4034",
		"shoe": "#2a2420", "eye": "#e83a2a", "arm_w": 1, "arm_len": 4,
	},
	"runner": {
		"w": 16, "h": 16, "hw": 5, "hh": 5, "tw": 5, "th": 4, "lh": 3, "zombie": true,
		"skin": "#c9c078", "hair": "#6a2a22", "shirt": "#a83a34", "pants": "#3a3a44",
		"shoe": "#222228", "eye": "#ffe040", "arm_w": 1, "arm_len": 4, "lean": 1,
	},
	"tank": {
		"w": 26, "h": 25, "hw": 7, "hh": 6, "tw": 14, "th": 9, "lh": 5, "zombie": true,
		"skin": "#6f8a78", "hair": "#2c3a34", "shirt": "#57505e", "pants": "#332e38",
		"shoe": "#1c1a20", "eye": "#ff4a30", "arm_w": 3, "arm_len": 5, "pads": true,
	},
	"exploder": {
		"w": 20, "h": 21, "hw": 5, "hh": 5, "tw": 13, "th": 10, "lh": 3, "zombie": true,
		"skin": "#b8a23c", "hair": "#6a5a20", "shirt": "#c6862c", "pants": "#5c4a24",
		"shoe": "#2c2418", "eye": "#ff2a10", "arm_w": 1, "arm_len": 3, "round": true,
	},
	"spitter": {
		"w": 18, "h": 18, "hw": 6, "hh": 5, "tw": 7, "th": 5, "lh": 3, "zombie": true,
		"skin": "#7e6aa6", "hair": "#3c2e58", "shirt": "#4a7a42", "pants": "#3a3048",
		"shoe": "#221c2c", "eye": "#c0ff40", "arm_w": 1, "arm_len": 3, "sac": true, "lean": 1,
	},
	"boss": {
		"w": 36, "h": 34, "hw": 9, "hh": 7, "tw": 20, "th": 13, "lh": 7, "zombie": true,
		"skin": "#a8706a", "hair": "#3a1c1c", "shirt": "#7c3a3a", "pants": "#2c2228",
		"shoe": "#181418", "eye": "#ffe040", "arm_w": 4, "arm_len": 6, "apron": true, "pads": true,
	},
}

## 3x5 迷你数字字体，用于伤害飘字和 HUD 数值。
const TINY := {
	"0": "111101101101111", "1": "010110010010111", "2": "111001111100111",
	"3": "111001111001111", "4": "101101111001001", "5": "111100111001111",
	"6": "111100111101111", "7": "111001010010010", "8": "111101111101111",
	"9": "111101111001111", "+": "000010111010000", "-": "000000111000000",
	"x": "000101010101000", "/": "001001010100100", "%": "101001010100101",
	"$": "011110010011110", ":": "000010000010000", ".": "000000000000010",
}

const PISTOL := [".hhhhhhhh", ".gggggggg", ".kwg.....", ".kw......"]
const SHOTGUN := ["........hhhhhhhh", "wwwwgggggggggggg", "wwwkkgggg.kkkk..", "ww.............."]
const SMG := ["...hhhhhhhh..", "kkkggggggggkk", "k..gggkg.....", "....kk.k.....", "....kk......."]
const GUN_PAL := {"h": "#b8bcc8", "g": "#6c7080", "k": "#34343e", "w": "#7c5230"}

const MEDKIT := [".wwwwwww.", "wwwwrwwww", "wwwwrwwww", "wrrrrrrrw", "wwwwrwwww", "wwwwrwwww", ".ggggggg."]
const AMMOBOX := ["..yyyyy..", ".ooooooo.", "ooyooyooo", "ooyooyooo", "ddddddddd", "ddddddddd"]
const HEART := [".rr.rr.", "rlrrrrr", "rrrrrrr", ".rrrrr.", "..rrr..", "...r..."]
const SHIELD := ["bbbbbbb", "blbbbbb", "blbbbbb", "bbbbbbb", ".bbbbb.", "..bbb.."]
const SKULL := [".wwwww.", "wwwwwww", "wkkwkkw", "wwwwwww", ".wkwkw."]
const MISC_PAL := {
	"w": "#f0ece0", "r": "#d83838", "g": "#a0a0a8", "y": "#f0d050", "o": "#6c7a3c",
	"d": "#48522c", "l": "#ffa090", "b": "#5a90d0", "k": "#201c28",
}

var font: Font
var _chars := {}
var gib_sets := {}
var blood_splats: Array[Image] = []
var blood_splats_dark: Array[Image] = []
var scorch: Image
var acid_splat: Image
var rubble: Array[Image] = []

var guns := {}
var shell_tex: Dictionary = {}
var shell_img: Dictionary = {}
var coin_frames: Array[Texture2D] = []
var coin_big_frames: Array[Texture2D] = []
var medkit_tex: Texture2D
var ammo_tex: Texture2D
var heart_tex: Texture2D
var shield_tex: Texture2D
var skull_tex: Texture2D
var shadow_small: Texture2D
var shadow_medium: Texture2D
var shadow_big: Texture2D

var walls: Dictionary = {}
var barricades: Array[Texture2D] = []
var barrel_tex: Texture2D
var base_tex: Array[Texture2D] = []
var flag_frames: Array[Texture2D] = []
var radar_frames: Array[Texture2D] = []
var trees: Array[Texture2D] = []
var rocks: Array[Texture2D] = []
var cars: Array[Texture2D] = []
var crate_tex: Texture2D
var turret_base_tex: Texture2D
var turret_barrels: Array[Texture2D] = []
var tiles: Dictionary = {}


func _ready() -> void:
	font = (preload("res://resources/pixel_theme.tres") as Theme).default_font
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261031
	for kind in CHARS.keys():
		_build_char(kind, rng)
	_build_guns()
	_build_items(rng)
	_build_decals(rng)
	_build_structures(rng)
	_build_props(rng)
	_build_tiles(rng)


# ---------------------------------------------------------------------------
# 对外取贴图
# ---------------------------------------------------------------------------

func frame(kind: String, dir: int, index: int, white := false) -> Texture2D:
	var set_key := "white" if white else "normal"
	return _chars[kind][set_key][dir][index]


func char_size(kind: String) -> Vector2i:
	return Vector2i(int(CHARS[kind]["w"]), int(CHARS[kind]["h"]))


func char_image(kind: String, dir: int, index: int) -> Image:
	return _chars[kind]["images"][dir][index]


## 把图集里的图片合成一张预览图，供开发时肉眼检查。
func debug_sheet() -> Image:
	var sheet := Image.create_empty(320, 320, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.3, 0.42, 0.26))
	var y := 2
	for kind in CHARS.keys():
		var x := 2
		var size := char_size(kind)
		for d in 3:
			for f in FRAMES:
				var im: Image = _chars[kind]["images"][d][f]
				sheet.blit_rect_mask(im, im, Rect2i(0, 0, size.x, size.y), Vector2i(x, y))
				x += size.x + 1
				if x + size.x > 318:
					x = 2
					y += size.y + 1
		y += size.y + 2
	return sheet


# ---------------------------------------------------------------------------
# 绘图工具
# ---------------------------------------------------------------------------

func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	if w <= 0 or h <= 0:
		return
	var r := Rect2i(x, y, w, h).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, c)


func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


func _disc(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x - cx) / maxf(rx, 0.01)
			var dy := (y - cy) / maxf(ry, 0.01)
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c)


func _outline(img: Image, c := OUTLINE) -> void:
	var src := img.duplicate() as Image
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			var near := false
			if x > 0 and src.get_pixel(x - 1, y).a > 0.0:
				near = true
			elif x < w - 1 and src.get_pixel(x + 1, y).a > 0.0:
				near = true
			elif y > 0 and src.get_pixel(x, y - 1).a > 0.0:
				near = true
			elif y < h - 1 and src.get_pixel(x, y + 1).a > 0.0:
				near = true
			if near:
				img.set_pixel(x, y, c)


func _white(img: Image) -> Image:
	var out := img.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			if out.get_pixel(x, y).a > 0.0:
				out.set_pixel(x, y, Color.WHITE)
	return out


func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


func _new(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)


func _ascii(rows: Array, pal: Dictionary, outline := true, margin := 1) -> Image:
	var w := String(rows[0]).length()
	var img := _new(w + margin * 2, rows.size() + margin * 2)
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			var ch := row[x]
			if pal.has(ch):
				img.set_pixel(x + margin, y + margin, Color(String(pal[ch])))
	if outline:
		_outline(img)
	return img


## 用 3x5 字体在任意 CanvasItem 上绘字。
func draw_tiny(ci: CanvasItem, text: String, pos: Vector2, color: Color, scale := 1) -> void:
	var x := roundi(pos.x)
	var y := roundi(pos.y)
	for i in text.length():
		var glyph: String = TINY.get(text[i], "")
		if glyph != "":
			for g in 15:
				if glyph[g] == "1":
					ci.draw_rect(Rect2(x + (g % 3) * scale, y + (g / 3) * scale, scale, scale), color)
		x += 4 * scale


func tiny_width(text: String, scale := 1) -> int:
	return text.length() * 4 * scale - scale


## 带阴影的中文文字。align: 0 左对齐, 1 居中, 2 右对齐。pos.y 是文字顶部。
func draw_text(ci: CanvasItem, text: String, pos: Vector2, size: int, color: Color, align := 0, shadow := true) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == 1:
		x -= width * 0.5
	elif align == 2:
		x -= width
	var base := Vector2(roundf(x), roundf(pos.y + font.get_ascent(size)))
	if shadow:
		font.draw_string(ci.get_canvas_item(), base + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.85))
	font.draw_string(ci.get_canvas_item(), base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


# ---------------------------------------------------------------------------
# 角色
# ---------------------------------------------------------------------------

func _build_char(kind: String, rng: RandomNumberGenerator) -> void:
	var spec: Dictionary = CHARS[kind]
	var normal := []
	var white := []
	var images := []
	var wounds := []
	for i in 7:
		wounds.append(Vector2i(rng.randi_range(0, 100), rng.randi_range(0, 100)))
	for d in 3:
		var n_row: Array[Texture2D] = []
		var w_row: Array[Texture2D] = []
		var i_row: Array[Image] = []
		for f in FRAMES:
			var img := _paint_char(spec, d, f, wounds)
			_outline(img)
			i_row.append(img)
			n_row.append(_tex(img))
			w_row.append(_tex(_white(img)))
		normal.append(n_row)
		white.append(w_row)
		images.append(i_row)
	_chars[kind] = {"normal": normal, "white": white, "images": images}
	if bool(spec["zombie"]) or kind == "player":
		gib_sets[kind] = _cut_gibs(images[DIR_DOWN][0], 5 if int(spec["w"]) >= 24 else 4)


func _leg(img: Image, x: int, top: int, foot: int, w: int, pants: Color, shoe: Color, shoe_dx := 0) -> void:
	_rect(img, x, top, w, foot - top, pants)
	_rect(img, x + mini(shoe_dx, 0), foot, w + absi(shoe_dx), 1, shoe)


func _paint_char(s: Dictionary, dir: int, f: int, wounds: Array) -> Image:
	var w: int = s["w"]
	var h: int = s["h"]
	var hw: int = s["hw"]
	var hh: int = s["hh"]
	var tw: int = s["tw"]
	var th: int = s["th"]
	var lh: int = s["lh"]
	var zombie: bool = s["zombie"]
	var skin := Color(String(s["skin"]))
	var skin_d := skin.darkened(0.22)
	var hair := Color(String(s["hair"]))
	var shirt := Color(String(s["shirt"]))
	var shirt_d := shirt.darkened(0.28)
	var shirt_l := shirt.lightened(0.14)
	var pants := Color(String(s["pants"]))
	var shoe := Color(String(s["shoe"]))
	var eye := Color(String(s["eye"]))
	var blood := Color("#7a1616")
	var arm_w: int = s.get("arm_w", 1)
	var arm_len: int = s.get("arm_len", 3)
	var lean: int = s.get("lean", 0)
	var is_round: bool = s.get("round", false)
	var has_sac: bool = s.get("sac", false)
	var has_pads: bool = s.get("pads", false)
	var has_apron: bool = s.get("apron", false)
	var helmet: bool = s.get("helmet", false)

	var img := _new(w, h)
	var cx := w / 2
	var foot := h - 2
	var yo := -1 if f % 2 == 0 else 0
	var hip := foot - lh + 1
	var t_top := hip - th + yo
	var t_left := cx - tw / 2
	var lw := maxi(2, tw / 3 if tw >= 9 else tw / 2)
	var scale_step := 1 + w / 24

	# 腿
	if dir != DIR_SIDE:
		var lift_l := scale_step if f == 1 else 0
		var lift_r := scale_step if f == 3 else 0
		_leg(img, cx - lw, hip + yo, foot - lift_l, lw, pants, shoe)
		_leg(img, cx, hip + yo, foot - lift_r, lw, pants.darkened(0.14), shoe)
	else:
		var off: int = [0, 2, 0, -2][f] * scale_step
		var rear_lift := scale_step if f == 1 else 0
		var front_lift := scale_step if f == 3 else 0
		_leg(img, cx - lw / 2 - off, hip + yo, foot - rear_lift, lw, pants.darkened(0.2), shoe.darkened(0.1), 1)
		_leg(img, cx - lw / 2 + off, hip + yo, foot - front_lift, lw, pants, shoe, 1)

	# 后侧手臂
	var sh_y := t_top + 1 + (1 if th >= 9 else 0)
	if zombie and dir == DIR_SIDE:
		var far_y := sh_y + 1 + ([1, 0, 0, 0][f] as int)
		_rect(img, cx, far_y, tw / 2 + arm_len - 1, arm_w, skin_d)
	if not zombie and dir == DIR_SIDE:
		_rect(img, cx + 1, sh_y + 1, 3, 1, skin_d)

	# 喷吐僵尸背后的毒囊
	if has_sac:
		var sac_c := Color("#9ae040") if f % 2 == 0 else Color("#7cc030")
		if dir == DIR_SIDE:
			_disc(img, cx - 3, t_top + 1, 3, 2.6, sac_c)
		elif dir == DIR_UP:
			_disc(img, cx, t_top + 2, 3.6, 3, sac_c)
			_px(img, cx - 1, t_top + 1, Color("#e0ff90"))

	# 躯干
	if is_round:
		var grow := 0.5 if f % 2 == 0 else 0.0
		var body_rx := tw * 0.5 + grow
		var body_ry := th * 0.5 + grow
		var body_cy := t_top + th * 0.5
		_disc(img, cx - 0.5, body_cy, body_rx, body_ry, shirt)
		_disc(img, cx - 1.5, body_cy - 1, body_rx - 2.5, body_ry - 2.5, shirt_l)
		# 发光的脓包，明暗交替就是脉动动画
		var glow := Color("#fff070") if f % 2 == 0 else Color("#ffb030")
		for p: Vector2i in [Vector2i(-3, 1), Vector2i(2, -1), Vector2i(0, 2), Vector2i(3, 2), Vector2i(-2, -2)]:
			if dir == DIR_UP and p.y > 0:
				continue
			_px(img, cx + p.x, roundi(body_cy) + p.y, glow)
			_px(img, cx + p.x + 1, roundi(body_cy) + p.y, glow.darkened(0.2))
	else:
		_rect(img, t_left, t_top, tw, th, shirt)
		_rect(img, t_left + tw - maxi(1, tw / 5), t_top, maxi(1, tw / 5), th, shirt_d)
		_rect(img, t_left, t_top, maxi(1, tw / 5), th, shirt_l)
		if not zombie and dir == DIR_DOWN:
			_rect(img, cx - 1, t_top, 2, th - 1, shirt_d)
			_rect(img, t_left, t_top + th - 1, tw, 1, Color("#5a4630"))
		if has_apron and dir != DIR_UP:
			_rect(img, t_left + 3, t_top + 2, tw - 6, th, Color("#c8c0b0"))
			for wp: Vector2i in wounds:
				_rect(img, t_left + 3 + wp.x % (tw - 7), t_top + 2 + wp.y % th, 3, 2, blood)
		if zombie:
			# 破烂衣摆和伤口
			for wp: Vector2i in wounds:
				var wx := t_left + wp.x % tw
				_px(img, wx, t_top + th - 1, Color(0, 0, 0, 0))
			for i in mini(3, wounds.size()):
				var wp: Vector2i = wounds[i]
				_px(img, t_left + wp.x % tw, t_top + wp.y % maxi(th - 1, 1), blood)
				_px(img, t_left + (wp.x + 1) % tw, t_top + wp.y % maxi(th - 1, 1), blood.darkened(0.2))

	# 头
	var h_drop := 1 if has_sac else 0
	var h_top := t_top - hh + 1 + h_drop
	var hx := cx - hw / 2
	if dir == DIR_SIDE:
		hx += lean
	elif zombie:
		hx += ([0, 1, 0, -1][f] as int)
	if dir == DIR_UP:
		_rect(img, hx, h_top, hw, hh, hair)
		_rect(img, hx, h_top + hh - 1, hw, 1, skin_d)
		_rect(img, hx + hw - 1, h_top, 1, hh - 1, hair.darkened(0.2))
	else:
		_rect(img, hx, h_top, hw, hh, skin)
		_rect(img, hx + hw - 1, h_top, 1, hh, skin_d)
		_rect(img, hx, h_top + hh - 1, hw, 1, skin_d)
		_rect(img, hx, h_top, hw, 2, hair)
		if dir == DIR_SIDE:
			_rect(img, hx, h_top, 2, hh - 1, hair)
		if helmet:
			_rect(img, hx - 1, h_top + 1, hw + 2, 1, hair.lightened(0.2))
			_rect(img, hx + 1, h_top, 2, 1, hair.lightened(0.35))
		elif zombie:
			# 秃斑
			_px(img, hx + 2, h_top, skin_d)
			_px(img, hx + hw - 2, h_top + 1, skin)
	if helmet and dir == DIR_UP:
		_rect(img, hx - 1, h_top + 1, hw + 2, 1, hair.lightened(0.2))
		_rect(img, hx + 1, h_top, 2, 1, hair.lightened(0.35))
	var eye_y := h_top + hh - 3
	var mouth_c := Color("#c0ff40") if has_sac else Color("#2a1416")
	if dir == DIR_DOWN:
		_px(img, hx + 1, eye_y, eye)
		_px(img, hx + hw - 2, eye_y, eye)
		if zombie:
			_rect(img, hx + hw / 2 - 1, eye_y + 2, 2, 1, mouth_c)
	elif dir == DIR_SIDE:
		_px(img, hx + hw - 2, eye_y, eye)
		if zombie:
			_rect(img, hx + hw - 2, eye_y + 2, 2, 1, mouth_c)

	# 前侧手臂
	if zombie:
		var left_up := -1 if f == 1 else 0
		var right_up := -1 if f == 3 else 0
		if dir == DIR_DOWN:
			_rect(img, t_left - arm_w, sh_y + left_up, arm_w, 2, shirt_d)
			_rect(img, t_left - arm_w, sh_y + left_up + 2, arm_w, arm_w + 1, skin)
			_rect(img, t_left + tw, sh_y + right_up, arm_w, 2, shirt_d)
			_rect(img, t_left + tw, sh_y + right_up + 2, arm_w, arm_w + 1, skin)
		elif dir == DIR_UP:
			_rect(img, t_left - arm_w, sh_y + left_up, arm_w, 3, shirt_d)
			_rect(img, t_left + tw, sh_y + right_up, arm_w, 3, shirt_d)
		else:
			var near_y := sh_y + ([0, 0, 0, 1][f] as int)
			_rect(img, cx, near_y, tw / 2 + 1, arm_w, shirt_d)
			_rect(img, cx + tw / 2 + 1, near_y, arm_len, arm_w, skin)
	else:
		if dir == DIR_DOWN or dir == DIR_UP:
			var sw_l := 1 if f == 1 else 0
			var sw_r := 1 if f == 3 else 0
			_rect(img, t_left - 1, sh_y + sw_l, 1, th - 2, shirt_d)
			_rect(img, t_left + tw, sh_y + sw_r, 1, th - 2, shirt_d)

	if has_pads:
		var pad := Color("#8c8c98")
		_rect(img, t_left - arm_w, t_top, arm_w + 2, 2, pad)
		if dir != DIR_SIDE:
			_rect(img, t_left + tw - 2, t_top, arm_w + 2, 2, pad)
	if has_apron and dir != DIR_UP:
		# 屠夫的大砍刀
		var kx := t_left + tw + arm_w if dir == DIR_DOWN else cx + tw / 2 + arm_len - 1
		var ky := sh_y + 2 + (1 if f % 2 == 1 else 0)
		if dir == DIR_DOWN:
			_rect(img, kx - 2, ky, 2, 7, Color("#5a4630"))
			_rect(img, kx - 3, ky - 8, 5, 9, Color("#c0c4cc"))
			_rect(img, kx - 3, ky - 8, 1, 9, Color("#f0f2f8"))
		else:
			_rect(img, kx, ky - 7, 4, 8, Color("#c0c4cc"))
			_rect(img, kx + 3, ky - 7, 1, 8, Color("#f0f2f8"))
	return img


func _cut_gibs(src: Image, block: int) -> Array:
	var out := []
	var w := src.get_width()
	var h := src.get_height()
	for y in range(0, h, block):
		for x in range(0, w, block):
			var piece := src.get_region(Rect2i(x, y, mini(block, w - x), mini(block, h - y)))
			var solid := 0
			for py in piece.get_height():
				for px in piece.get_width():
					if piece.get_pixel(px, py).a > 0.0 and piece.get_pixel(px, py) != OUTLINE:
						solid += 1
			if solid >= block:
				out.append({"img": piece, "tex": _tex(piece)})
	return out


# ---------------------------------------------------------------------------
# 武器与道具
# ---------------------------------------------------------------------------

func _build_guns() -> void:
	var specs := {"pistol": PISTOL, "shotgun": SHOTGUN, "smg": SMG}
	for id in specs.keys():
		var img := _ascii(specs[id], GUN_PAL)
		guns[id] = {"tex": _tex(img), "w": img.get_width(), "h": img.get_height()}
	var brass := _new(2, 1)
	brass.fill(Color("#e8c050"))
	var red := _new(3, 2)
	red.fill(Color("#c83c30"))
	red.set_pixel(0, 0, Color("#e8c050"))
	red.set_pixel(0, 1, Color("#e8c050"))
	shell_img = {"brass": brass, "red": red}
	shell_tex = {"brass": _tex(brass), "red": _tex(red)}


func _build_items(_rng: RandomNumberGenerator) -> void:
	for width: int in [7, 5, 3, 5]:
		coin_frames.append(_tex(_coin(width, 7)))
	for width: int in [9, 7, 3, 7]:
		coin_big_frames.append(_tex(_coin(width, 9)))
	medkit_tex = _tex(_ascii(MEDKIT, MISC_PAL))
	ammo_tex = _tex(_ascii(AMMOBOX, MISC_PAL))
	heart_tex = _tex(_ascii(HEART, MISC_PAL))
	shield_tex = _tex(_ascii(SHIELD, MISC_PAL))
	skull_tex = _tex(_ascii(SKULL, MISC_PAL))
	shadow_small = _tex(_shadow(11, 4))
	shadow_medium = _tex(_shadow(19, 6))
	shadow_big = _tex(_shadow(29, 9))


func _coin(width: int, size: int) -> Image:
	var img := _new(size + 2, size + 2)
	var c := (size + 2) * 0.5 - 0.5
	_disc(img, c, c, width * 0.5 - 0.3, size * 0.5 - 0.3, Color("#f0c030"))
	if width > 3:
		_disc(img, c - 0.5, c - 0.5, width * 0.5 - 1.8, size * 0.5 - 1.8, Color("#ffe880"))
	_outline(img, Color("#7a5010"))
	return img


func _shadow(w: int, h: int) -> Image:
	var img := _new(w, h)
	_disc(img, (w - 1) * 0.5, (h - 1) * 0.5, w * 0.5 - 0.2, h * 0.5 - 0.2, Color(0, 0, 0, 0.32))
	return img


func _build_decals(rng: RandomNumberGenerator) -> void:
	for i in 6:
		var size := 12 + i * 2
		blood_splats.append(_splat(size, Color("#7c1414"), Color("#551010"), rng))
		blood_splats_dark.append(_splat(size + 6, Color("#641212"), Color("#430c0c"), rng))
	acid_splat = _splat(22, Color("#5e9a28"), Color("#3e6e1c"), rng)
	scorch = _splat(46, Color(0.09, 0.08, 0.08, 0.8), Color(0.16, 0.13, 0.11, 0.62), rng)
	for i in 4:
		rubble.append(_rubble(rng))


func _splat(size: int, c1: Color, c2: Color, rng: RandomNumberGenerator) -> Image:
	var img := _new(size, size)
	var c := size * 0.5
	for i in 7:
		var a := rng.randf() * TAU
		var d := rng.randf() * size * 0.26
		_disc(img, c + cos(a) * d, c + sin(a) * d, rng.randf_range(1.5, size * 0.24), rng.randf_range(1.5, size * 0.2), c2 if i % 3 == 0 else c1)
	for i in size:
		var a := rng.randf() * TAU
		var d := rng.randf_range(size * 0.3, size * 0.5)
		_px(img, roundi(c + cos(a) * d), roundi(c + sin(a) * d), c1)
	return img


func _rubble(rng: RandomNumberGenerator) -> Image:
	var img := _new(16, 16)
	for i in 14:
		var col := Color("#8a8880") if i % 3 else Color("#5e5c56")
		_rect(img, rng.randi_range(1, 12), rng.randi_range(2, 13), rng.randi_range(1, 3), rng.randi_range(1, 2), col)
	return img


# ---------------------------------------------------------------------------
# 建筑：围墙、路障、基地、炮塔
# ---------------------------------------------------------------------------

func _build_structures(rng: RandomNumberGenerator) -> void:
	# 围墙贴图 16x24：下方 16 像素对应格子，上方 8 像素是墙体高度。
	for front: bool in [true, false]:
		var row: Array[Texture2D] = []
		for dmg in 4:
			row.append(_tex(_wall(front, dmg, rng)))
		walls[front] = row
	for dmg in 4:
		barricades.append(_tex(_barricade(dmg, rng)))
	var barrel := _new(14, 16)
	_rect(barrel, 2, 1, 10, 14, Color("#b83a2c"))
	_rect(barrel, 9, 1, 3, 14, Color("#8a2a20"))
	_rect(barrel, 2, 1, 2, 14, Color("#d85a48"))
	_rect(barrel, 2, 4, 10, 1, Color("#5a1c16"))
	_rect(barrel, 2, 11, 10, 1, Color("#5a1c16"))
	_rect(barrel, 5, 6, 4, 4, Color("#f0d050"))
	_px(barrel, 6, 7, Color("#201c28"))
	_px(barrel, 7, 8, Color("#201c28"))
	_rect(barrel, 3, 1, 8, 1, Color("#e88070"))
	_outline(barrel)
	barrel_tex = _tex(barrel)
	for stage in 4:
		base_tex.append(_tex(_base(stage, rng)))
	for i in 3:
		var flag := _new(16, 18)
		_rect(flag, 1, 0, 1, 18, Color("#c8c4b8"))
		var wave_y: Array = [[0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0], [1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0], [1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1]][i]
		for x in 12:
			var dy: int = wave_y[x]
			_rect(flag, 2 + x, 1 + dy, 1, 7, Color("#c23a2c") if x % 4 != 3 else Color("#a22e22"))
			_px(flag, 2 + x, 4 + dy, Color("#f0ece0"))
		flag_frames.append(_tex(flag))
	for i in 4:
		var radar := _new(13, 11)
		_rect(radar, 5, 7, 3, 4, Color("#454a4e"))
		var widths := [11, 7, 3, 7]
		var rw: int = widths[i]
		var left := 6 - rw / 2
		_rect(radar, left, 3, rw, 3, Color("#c0c4c8"))
		_rect(radar, left, 5, rw, 1, Color("#808488"))
		_rect(radar, 6, 1, 1, 3, Color("#e05040"))
		_outline(radar)
		radar_frames.append(_tex(radar))
	var tb := _new(16, 14)
	_disc(tb, 7.5, 9, 6.5, 4, Color("#4c5058"))
	_disc(tb, 7.5, 8, 5, 3, Color("#6c7078"))
	_rect(tb, 5, 2, 6, 6, Color("#50745a"))
	_rect(tb, 5, 2, 6, 1, Color("#70987a"))
	_outline(tb)
	turret_base_tex = _tex(tb)
	for lvl in 4:
		var barrel_img := _new(16, 6)
		var main_c: Color = [Color("#8a90a0"), Color("#a0b070"), Color("#d0a050"), Color("#e06040")][lvl]
		_rect(barrel_img, 3, 2, 11, 2, main_c)
		_rect(barrel_img, 3, 2, 11, 1, main_c.lightened(0.25))
		_rect(barrel_img, 0, 1, 5, 4, Color("#50745a"))
		_outline(barrel_img)
		turret_barrels.append(_tex(barrel_img))


func _wall(front: bool, dmg: int, rng: RandomNumberGenerator) -> Image:
	var img := _new(16, 24)
	var top := Color("#a6a294")
	var top_d := Color("#8c897c")
	var brick := Color("#8d5f48")
	var brick_d := Color("#6d4836")
	var mortar := Color("#574038")
	_rect(img, 0, 0, 16, 24 if not front else 13, top)
	_rect(img, 0, 0, 16, 1, Color("#c4c0b0"))
	_rect(img, 0, 0, 1, 24 if not front else 13, top_d)
	_rect(img, 15, 0, 1, 24 if not front else 13, top_d)
	for i in 8:
		_px(img, rng.randi_range(2, 13), rng.randi_range(2, 22 if not front else 11), top_d)
	if front:
		_rect(img, 0, 13, 16, 11, brick)
		_rect(img, 0, 13, 16, 1, mortar)
		for row in 3:
			var y := 14 + row * 3
			_rect(img, 0, y + 2, 16, 1, mortar)
			var off := 0 if row % 2 == 0 else 4
			for x in range(off, 16, 8):
				_rect(img, x, y, 1, 2, mortar)
				_px(img, x + 3, y, brick_d)
		_rect(img, 0, 23, 16, 1, brick_d.darkened(0.4))
	_damage_marks(img, dmg, rng, 2 if front else 0)
	return img


func _damage_marks(img: Image, dmg: int, rng: RandomNumberGenerator, y_min := 0) -> void:
	var dark := Color("#2c2622")
	for c in dmg * 3:
		var x := rng.randi_range(1, img.get_width() - 2)
		var y := rng.randi_range(y_min, img.get_height() - 2)
		for s in rng.randi_range(2, 4):
			_px(img, x, y, dark)
			x += rng.randi_range(-1, 1)
			y += 1
	if dmg >= 3:
		for c in 3:
			var hole_x := rng.randi_range(0, img.get_width() - 1)
			_rect(img, hole_x, 0, rng.randi_range(1, 3), rng.randi_range(1, 4), Color(0, 0, 0, 0))


func _barricade(dmg: int, rng: RandomNumberGenerator) -> Image:
	var img := _new(16, 20)
	var wood := Color("#9a6a3c")
	var wood_d := Color("#6c4826")
	# 沙袋底座
	for i in 3:
		_rect(img, i * 5 + 0, 14, 6, 5, Color("#a89a70"))
		_rect(img, i * 5 + 0, 14, 6, 1, Color("#c4b68a"))
		_rect(img, i * 5 + 5, 15, 1, 4, Color("#74684a"))
	# 交叉木桩
	for t in 12:
		_rect(img, 1 + t, 2 + t, 2, 2, wood)
		_rect(img, 13 - t, 2 + t, 2, 2, wood_d if t < 6 else wood)
	_rect(img, 0, 7, 16, 3, wood)
	_rect(img, 0, 9, 16, 1, wood_d)
	_px(img, 3, 8, Color("#d0d0d0"))
	_px(img, 12, 8, Color("#d0d0d0"))
	_px(img, 1, 1, Color("#d8d4c8"))
	_px(img, 14, 1, Color("#d8d4c8"))
	_damage_marks(img, dmg, rng, 0)
	_outline(img)
	return img


func _base(stage: int, rng: RandomNumberGenerator) -> Image:
	var w := 64
	var h := 64
	var img := _new(w, h)
	var roof := Color("#5f6f58")
	var roof_d := Color("#4c5a47")
	var roof_l := Color("#7a8c70")
	var wall := Color("#4a5044")
	var wall_d := Color("#383d34")
	_rect(img, 0, 2, w, 40, roof_d)
	_rect(img, 1, 3, w - 2, 38, roof)
	_rect(img, 1, 3, w - 2, 1, roof_l)
	for x in range(8, w, 12):
		_rect(img, x, 4, 1, 37, roof_d)
	for y in range(13, 40, 12):
		_rect(img, 1, y, w - 2, 1, roof_d)
	# 直升机坪
	_disc(img, 32, 21, 13, 12, Color("#d8d4c0"))
	_disc(img, 32, 21, 11, 10, Color("#3c4238"))
	_rect(img, 28, 15, 2, 12, Color("#d84030"))
	_rect(img, 34, 15, 2, 12, Color("#d84030"))
	_rect(img, 28, 20, 8, 2, Color("#d84030"))
	# 通风口
	_rect(img, 5, 7, 8, 6, Color("#30352e"))
	_rect(img, 6, 8, 6, 1, Color("#6c7468"))
	_rect(img, 6, 10, 6, 1, Color("#6c7468"))
	_rect(img, 51, 30, 8, 6, Color("#30352e"))
	_rect(img, 52, 31, 6, 1, Color("#6c7468"))
	_rect(img, 52, 33, 6, 1, Color("#6c7468"))
	# 正面墙体
	_rect(img, 0, 42, w, 22, wall)
	_rect(img, 0, 42, w, 2, wall_d)
	_rect(img, 0, 62, w, 2, wall_d.darkened(0.25))
	for x in range(3, w, 8):
		_px(img, x, 46, wall_d)
		_px(img, x, 58, wall_d)
	# 大门与警示条
	_rect(img, 24, 46, 16, 18, Color("#2a2c2a"))
	for y in range(46, 64, 4):
		_rect(img, 24, y, 2, 2, Color("#e0b830"))
		_rect(img, 38, y + 2, 2, 2, Color("#e0b830"))
	_rect(img, 31, 46, 2, 18, Color("#44484a"))
	# 窗户
	for wx: int in [7, 47]:
		_rect(img, wx, 48, 10, 7, Color("#1c2020"))
		_rect(img, wx + 1, 49, 8, 5, Color("#f0c860"))
		_rect(img, wx + 1, 49, 8, 2, Color("#ffe8a0"))
		_rect(img, wx + 4, 49, 1, 5, Color("#1c2020"))
	_outline_edges(img)
	# 受损阶段：裂痕、窟窿
	var dark := Color("#1c1c1a")
	for c in stage * 9:
		var x := rng.randi_range(1, w - 2)
		var y := rng.randi_range(3, h - 2)
		for s in rng.randi_range(3, 8):
			_px(img, x, y, dark)
			x += rng.randi_range(-1, 1)
			y += rng.randi_range(0, 1)
	for c in maxi(stage - 1, 0) * 4:
		var x := rng.randi_range(3, w - 10)
		var y := rng.randi_range(4, h - 10)
		_disc(img, x, y, rng.randf_range(2.0, 4.0), rng.randf_range(1.5, 3.0), Color("#14120f"))
	return img


func _outline_edges(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	_rect(img, 0, 2, w, 1, OUTLINE)
	_rect(img, 0, 2, 1, h - 2, OUTLINE)
	_rect(img, w - 1, 2, 1, h - 2, OUTLINE)
	_rect(img, 0, h - 1, w, 1, OUTLINE)


# ---------------------------------------------------------------------------
# 场景摆件
# ---------------------------------------------------------------------------

func _build_props(rng: RandomNumberGenerator) -> void:
	for i in 3:
		trees.append(_tex(_tree(i, rng)))
	for i in 2:
		rocks.append(_tex(_rock(rng)))
	var car_colors := ["#8a3a30", "#3a5a7c", "#7c7450", "#50505c"]
	for hex: String in car_colors:
		cars.append(_tex(_car(Color(hex), rng)))
	var crate := _new(14, 15)
	_rect(crate, 1, 1, 12, 13, Color("#8c6a3c"))
	_rect(crate, 1, 1, 12, 4, Color("#a8844e"))
	_rect(crate, 1, 5, 12, 1, Color("#5a4224"))
	for t in 8:
		_px(crate, 2 + t, 6 + t, Color("#5a4224"))
		_px(crate, 11 - t, 6 + t, Color("#5a4224"))
	_outline(crate)
	crate_tex = _tex(crate)


func _tree(variant: int, rng: RandomNumberGenerator) -> Image:
	var img := _new(32, 40)
	_rect(img, 13, 26, 6, 13, Color("#5a4028"))
	_rect(img, 13, 26, 2, 13, Color("#7a5838"))
	_rect(img, 17, 26, 2, 13, Color("#42301e"))
	var greens: Array = [
		[Color("#2c5230"), Color("#3a6a3a"), Color("#5a8c48")],
		[Color("#34562a"), Color("#4c7434"), Color("#74984a")],
		[Color("#28483a"), Color("#366248"), Color("#50845c")],
	][variant]
	_disc(img, 16, 16, 14, 13, greens[0])
	_disc(img, 9, 19, 7, 7, greens[0])
	_disc(img, 23, 19, 7, 7, greens[0])
	_disc(img, 14, 13, 11, 10, greens[1])
	_disc(img, 11, 10, 6, 5, greens[2])
	for i in 34:
		var a := rng.randf() * TAU
		var d := rng.randf() * 12.0
		_px(img, roundi(16 + cos(a) * d), roundi(15 + sin(a) * d), greens[rng.randi() % 3])
	_outline(img)
	return img


func _rock(rng: RandomNumberGenerator) -> Image:
	var img := _new(16, 14)
	_disc(img, 7.5, 7.5, 7, 5.5, Color("#6a6c70"))
	_disc(img, 6.5, 6, 5, 3.5, Color("#8a8c90"))
	_disc(img, 5, 4.5, 2.2, 1.4, Color("#a8aaae"))
	for i in 5:
		_px(img, rng.randi_range(3, 12), rng.randi_range(5, 11), Color("#54565a"))
	_outline(img)
	return img


func _car(color: Color, rng: RandomNumberGenerator) -> Image:
	var img := _new(32, 22)
	var dark := color.darkened(0.3)
	# 车身
	_rect(img, 1, 8, 30, 10, dark)
	_rect(img, 1, 7, 30, 6, color)
	_rect(img, 7, 1, 17, 7, color.darkened(0.08))
	_rect(img, 9, 2, 13, 5, Color("#22282c"))
	_rect(img, 9, 2, 5, 1, Color("#50606a"))
	_rect(img, 3, 8, 3, 2, Color("#d8c880"))
	_rect(img, 26, 8, 3, 2, Color("#8c2a22"))
	# 轮胎
	_rect(img, 4, 17, 6, 4, Color("#1a1a1e"))
	_rect(img, 22, 17, 6, 4, Color("#1a1a1e"))
	# 锈迹
	for i in 22:
		_px(img, rng.randi_range(1, 30), rng.randi_range(7, 17), Color("#6a4226"))
	_outline(img)
	return img


# ---------------------------------------------------------------------------
# 地面贴片
# ---------------------------------------------------------------------------

func _build_tiles(rng: RandomNumberGenerator) -> void:
	tiles["grass"] = []
	tiles["grass_dark"] = []
	tiles["dirt"] = []
	tiles["road"] = []
	tiles["concrete"] = []
	for i in 6:
		tiles["grass"].append(_grass(Color("#4e7a3c"), i, rng))
		tiles["grass_dark"].append(_grass(Color("#436c36"), i, rng))
	for i in 4:
		tiles["dirt"].append(_speckle(Color("#7a6444"), Color("#68543a"), Color("#8c7654"), 22, rng))
		tiles["road"].append(_speckle(Color("#3c3e46"), Color("#33353c"), Color("#474a52"), 16, rng))
		var con := _speckle(Color("#74726a"), Color("#68665f"), Color("#7e7c74"), 12, rng)
		_rect(con, 0, 0, 16, 1, Color("#615f58"))
		_rect(con, 0, 0, 1, 16, Color("#615f58"))
		tiles["concrete"].append(con)


func _speckle(base: Color, dark: Color, light: Color, n: int, rng: RandomNumberGenerator) -> Image:
	var img := _new(16, 16)
	img.fill(base)
	for i in n:
		_px(img, rng.randi_range(0, 15), rng.randi_range(0, 15), dark)
	for i in n / 2:
		_px(img, rng.randi_range(0, 15), rng.randi_range(0, 15), light)
	return img


func _grass(base: Color, variant: int, rng: RandomNumberGenerator) -> Image:
	var img := _speckle(base, base.darkened(0.12), base.lightened(0.1), 22, rng)
	# 草簇
	for i in 3:
		var x := rng.randi_range(1, 13)
		var y := rng.randi_range(3, 14)
		var c := base.lightened(0.24)
		_px(img, x, y, c)
		_px(img, x + 1, y - 1, c)
		_px(img, x + 2, y, c)
	# 少数贴片带小花或碎石
	if variant == 4:
		var fx := rng.randi_range(3, 12)
		var fy := rng.randi_range(3, 12)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			_px(img, fx + d.x, fy + d.y, Color("#f0ece0"))
		_px(img, fx, fy, Color("#f0c830"))
	elif variant == 5:
		_rect(img, rng.randi_range(2, 12), rng.randi_range(2, 12), 2, 1, Color("#8c8c84"))
	return img
