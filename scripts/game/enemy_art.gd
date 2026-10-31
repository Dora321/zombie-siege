extends RefCounted
## 精英和 Boss 的像素造型。a 是 Art 单例，借用它的画笔。
## paint 从零画一整帧；decorate 在通用人形（Art._paint_char）上加细节。

const DOWN := 0
const UP := 1
const SIDE := 2


static func paint(a: Node, style: String, s: Dictionary, dir: int, f: int) -> Image:
	match style:
		"splitling":
			return _splitling(a, s, dir, f)
		"summoner":
			return _summoner(a, s, dir, f)
		"balloon":
			return _balloon(a, s, dir, f)
	return a._new(int(s["w"]), int(s["h"]))


## 算出通用人形的关键位置，和 Art._paint_char 保持一致。
static func _body(s: Dictionary, dir: int, f: int) -> Dictionary:
	var w: int = s["w"]
	var foot: int = int(s["h"]) - 2
	var yo := -1 if f % 2 == 0 else 0
	var hip: int = foot - int(s["lh"]) + 1
	var t_top: int = hip - int(s["th"]) + yo
	var cx := w / 2
	var hx: int = cx - int(s["hw"]) / 2
	if dir == SIDE:
		hx += int(s.get("lean", 0))
	else:
		hx += [0, 1, 0, -1][f] as int
	return {
		"cx": cx, "foot": foot, "hip": hip, "t_top": t_top, "t_left": cx - int(s["tw"]) / 2,
		"h_top": t_top - int(s["hh"]) + 1, "hx": hx,
	}


static func decorate(a: Node, style: String, img: Image, s: Dictionary, dir: int, f: int) -> void:
	var b := _body(s, dir, f)
	match style:
		"stalker":
			_stalker(a, img, s, b, dir, f)
		"shielder":
			_shielder(a, img, s, b, dir, f)
		"splitter":
			_splitter(a, img, s, b, dir, f)
		"imp":
			_imp(a, img, s, b, dir, f)
		"screamer":
			_screamer(a, img, s, b, dir, f)
		"plague":
			_plague(a, img, s, b, dir, f)
		"overlord":
			_overlord(a, img, s, b, dir, f)


## 潜伏者：兜帽、发亮的眼睛、一双长爪子。
static func _stalker(a: Node, img: Image, s: Dictionary, b: Dictionary, dir: int, f: int) -> void:
	var hw: int = s["hw"]
	var hood := Color("#1c1826")
	var claw := Color("#dce8ff")
	a._rect(img, b["hx"] - 1, b["h_top"] - 1, hw + 2, 2, hood)
	a._rect(img, b["hx"] - 1, b["h_top"], 1, 4, hood)
	a._rect(img, b["hx"] + hw, b["h_top"], 1, 4, hood)
	var eye_y: int = b["h_top"] + 2
	var glow := Color("#60f0ff")
	if dir == DOWN:
		a._rect(img, b["hx"], eye_y, 2, 1, glow)
		a._rect(img, b["hx"] + hw - 2, eye_y, 2, 1, glow)
	elif dir == SIDE:
		a._rect(img, b["hx"] + hw - 2, eye_y, 2, 1, glow)
	var reach: int = [0, 1, 0, -1][f] as int
	if dir == SIDE:
		var x: int = b["cx"] + int(s["tw"]) / 2 + int(s["arm_len"])
		var y: int = b["t_top"] + 2 + reach
		a._px(img, x + 1, y - 1, claw)
		a._px(img, x + 1, y + 1, claw)
		a._px(img, x + 2, y, claw)
	else:
		var y: int = b["t_top"] + 5
		for x: int in [b["t_left"] - 2, b["t_left"] + int(s["tw"]) + 1]:
			a._px(img, x, y + reach, claw)
			a._px(img, x, y + 1 + reach, claw)
			a._px(img, x + (1 if x > b["cx"] else -1), y + 1 + reach, claw)


## 护盾兵：防暴头盔、面罩、胸前的黄条。盾牌在 brain 里实时画，能转向。
static func _shielder(a: Node, img: Image, s: Dictionary, b: Dictionary, dir: int, _f: int) -> void:
	var hw: int = s["hw"]
	var helm := Color("#28344c")
	a._rect(img, b["hx"] - 1, b["h_top"] - 1, hw + 2, 3, helm)
	a._rect(img, b["hx"], b["h_top"] - 1, hw - 2, 1, helm.lightened(0.3))
	if dir == DOWN:
		a._rect(img, b["hx"], b["h_top"] + 2, hw, 2, Color("#90c0e0"))
		a._rect(img, b["hx"] + 1, b["h_top"] + 2, 1, 1, Color("#e0f4ff"))
	elif dir == SIDE:
		a._rect(img, b["hx"] + 2, b["h_top"] + 2, hw - 2, 2, Color("#90c0e0"))
	else:
		a._rect(img, b["hx"] - 1, b["h_top"] + 2, hw + 2, 2, helm)
	if dir != UP:
		a._rect(img, b["t_left"], b["t_top"] + 2, int(s["tw"]), 1, Color("#e0b830"))


## 分裂体：肚子中间一道发光的裂缝，两侧鼓着即将长出来的小脑袋。
static func _splitter(a: Node, img: Image, s: Dictionary, b: Dictionary, dir: int, f: int) -> void:
	var cy: int = b["t_top"] + int(s["th"]) / 2
	var cx: int = b["cx"]
	var bulge := 0 if f % 2 == 0 else 1
	var bud := Color("#a8c860")
	a._disc(img, cx - 7 - bulge, cy - 2, 3.0, 3.0, bud)
	a._disc(img, cx + 6 + bulge, cy + 1, 3.0, 3.0, bud)
	var eye := Color("#ff4030")
	a._px(img, cx - 8 - bulge, cy - 3, eye)
	a._px(img, cx + 7 + bulge, cy, eye)
	if dir != UP:
		var seam := Color("#ff60a0") if f % 2 == 0 else Color("#ffb0d0")
		for y in range(b["t_top"] + 3, b["t_top"] + int(s["th"]) - 1):
			a._px(img, cx + (y % 2), y, seam)


## 小鬼：骷髅脸、小角、肋骨。
static func _imp(a: Node, img: Image, s: Dictionary, b: Dictionary, dir: int, f: int) -> void:
	var hw: int = s["hw"]
	var bone := Color("#e8e4d0")
	a._px(img, b["hx"], b["h_top"] - 1, bone)
	a._px(img, b["hx"] + hw - 1, b["h_top"] - 1, bone)
	if dir != UP:
		for k in int(s["th"]):
			if k % 2 == 0:
				a._rect(img, b["t_left"], b["t_top"] + k, int(s["tw"]), 1, bone)
		var eye := Color("#d060ff") if f % 2 == 0 else Color("#f0c0ff")
		a._px(img, b["hx"] + 1, b["h_top"] + 1, eye)
		if dir == DOWN:
			a._px(img, b["hx"] + hw - 2, b["h_top"] + 1, eye)


## 尖叫者：乱发竖起，嘴张得比脸还大，开合就是它的动画。
static func _screamer(a: Node, img: Image, s: Dictionary, b: Dictionary, dir: int, f: int) -> void:
	var hw: int = s["hw"]
	var hh: int = s["hh"]
	var hair := Color("#d04a6a")
	for k in hw + 2:
		var tall := 3 if (k + f) % 3 == 0 else 2
		a._rect(img, b["hx"] - 1 + k, b["h_top"] - tall, 1, tall + 1, hair)
	if dir == UP:
		return
	var open: int = [2, 3, 4, 3][f] as int
	var mx: int = b["hx"] + 1 if dir == DOWN else b["hx"] + hw - 4
	var mw: int = hw - 2 if dir == DOWN else 4
	var my: int = b["h_top"] + hh - 3
	a._rect(img, mx, my, mw, open, Color("#200810"))
	a._rect(img, mx + 1, my + open - 1, maxi(mw - 2, 1), 1, Color("#c02840"))
	a._rect(img, mx, my, mw, 1, Color("#f0ece0"))


## 瘟疫母体：浑身是搏动的毒囊，嘴角滴着脓。
static func _plague(a: Node, img: Image, s: Dictionary, b: Dictionary, dir: int, f: int) -> void:
	var cx: int = b["cx"]
	var t_top: int = b["t_top"]
	var th: int = s["th"]
	var pulse := 0.0 if f % 2 == 0 else 1.0
	var sac := Color("#b8f040") if f % 2 == 0 else Color("#90d030")
	var spots: Array = [Vector2i(-12, 4), Vector2i(12, 7), Vector2i(-9, 13), Vector2i(10, 15), Vector2i(0, 16)]
	if dir == UP:
		spots.append(Vector2i(-4, 6))
		spots.append(Vector2i(5, 9))
	for p: Vector2i in spots:
		a._disc(img, cx + p.x, t_top + p.y, 3.0 + pulse, 3.0 + pulse, sac)
		a._px(img, cx + p.x - 1, t_top + p.y - 1, Color("#f0ffb0"))
	for k in 3:
		a._px(img, cx - 6 + k * 6, t_top + th - 1 + (f + k) % 3, Color("#a0e030"))
	if dir != UP:
		var hx: int = b["hx"]
		var mouth_y: int = b["h_top"] + int(s["hh"]) - 2
		a._rect(img, hx + 2, mouth_y, int(s["hw"]) - 4, 2, Color("#2a3a10"))
		a._px(img, hx + 3, mouth_y + 2 + f % 2, Color("#c0ff40"))


## 尸王：金冠、红披风、胸口跳动的心脏、一把大剑。
static func _overlord(a: Node, img: Image, s: Dictionary, b: Dictionary, dir: int, f: int) -> void:
	var hw: int = s["hw"]
	var tw: int = s["tw"]
	var th: int = s["th"]
	var t_left: int = b["t_left"]
	var t_top: int = b["t_top"]
	var gold := Color("#f0c030")
	var gold_d := Color("#a87c18")
	var h_top: int = b["h_top"]
	a._rect(img, b["hx"] - 1, h_top - 2, hw + 2, 3, gold)
	a._rect(img, b["hx"] - 1, h_top, hw + 2, 1, gold_d)
	for k in 4:
		var x: int = b["hx"] - 1 + k * (hw + 1) / 3
		a._rect(img, x, h_top - 4 - (k % 2), 2, 3, gold)
	a._px(img, b["hx"] + hw / 2, h_top - 1, Color("#ff3020"))
	var cape := Color("#8c1c2c")
	if dir == UP:
		a._rect(img, t_left - 2, t_top, tw + 4, th + 4 + f % 2, cape)
		a._rect(img, t_left - 2, t_top, tw + 4, 1, cape.lightened(0.2))
		for k in range(0, tw + 4, 5):
			a._rect(img, t_left - 2 + k, t_top + 2, 1, th + 2, cape.darkened(0.3))
	else:
		# 肩甲和胸前的护甲条
		a._rect(img, t_left, t_top + 3, tw, 1, Color("#6c6c80"))
		a._rect(img, t_left, t_top + th - 3, tw, 1, Color("#6c6c80"))
		var heart := Color("#ff3020") if f % 2 == 0 else Color("#c01c14")
		a._disc(img, b["cx"], t_top + th / 2, 3.0 + (0.8 if f % 2 == 0 else 0.0), 3.0 + (0.8 if f % 2 == 0 else 0.0), heart)
		a._px(img, b["cx"] - 1, t_top + th / 2 - 1, Color("#ffb0a0"))
		# 大剑
		var steel := Color("#c8ccd8")
		var bob := f % 2
		var sx: int = t_left + tw + int(s["arm_w"]) - 1 if dir == DOWN else b["cx"] + tw / 2 + int(s["arm_len"]) - 1
		a._rect(img, sx, t_top - 8 + bob, 3, 20, steel)
		a._rect(img, sx + 2, t_top - 8 + bob, 1, 20, Color("#f0f4ff"))
		a._rect(img, sx - 2, t_top + 11 + bob, 7, 2, gold)
		a._rect(img, sx, t_top + 13 + bob, 3, 3, Color("#4a3020"))


## 分裂小怪：一团肉冻，弹跳时压扁再拉长。
static func _splitling(a: Node, s: Dictionary, dir: int, f: int) -> Image:
	var w: int = s["w"]
	var h: int = s["h"]
	var img: Image = a._new(w, h)
	var body := Color(String(s["skin"]))
	var rx: float = [4.5, 3.8, 4.5, 5.4][f]
	var ry: float = [3.6, 4.4, 3.6, 2.8][f]
	var hop: int = [0, -2, 0, 0][f]
	var cx := (w - 1) * 0.5
	var cy: float = h - 2 - ry + hop
	a._disc(img, cx, cy, rx, ry, body)
	a._disc(img, cx - 1.0, cy - 1.0, rx * 0.5, ry * 0.5, body.lightened(0.25))
	var ground := h - 2
	a._rect(img, int(cx) - 3, ground, 2, 1, body.darkened(0.3))
	a._rect(img, int(cx) + 2, ground, 2, 1, body.darkened(0.3))
	var eye := Color(String(s["eye"]))
	var ey := int(cy) - 1
	if dir == DOWN:
		a._px(img, int(cx) - 2, ey, eye)
		a._px(img, int(cx) + 2, ey, eye)
		a._px(img, int(cx), ey + 2, Color("#203010"))
	elif dir == SIDE:
		a._px(img, int(cx) + 2, ey, eye)
		a._px(img, int(cx) + 3, ey + 2, Color("#203010"))
	return img


## 召唤者：拖地长袍和兜帽，手持骷髅法杖，杖头的光一明一暗。
static func _summoner(a: Node, s: Dictionary, dir: int, f: int) -> Image:
	var w: int = s["w"]
	var h: int = s["h"]
	var img: Image = a._new(w, h)
	var robe := Color("#3c2a5c")
	var robe_d := Color("#2a1c44")
	var trim := Color("#c8a040")
	var foot := h - 2
	var cx := w / 2
	var bob := -1 if f % 2 == 0 else 0
	var top := 7 + bob
	for y in range(top, foot + 1):
		var half := 3 + (y - top) / 3
		a._rect(img, cx - half, y, half * 2, 1, robe)
		a._rect(img, cx + half - 2, y, 2, 1, robe_d)
	var sway: int = [0, 1, 0, -1][f] as int
	a._rect(img, cx - 6 + sway, foot, 12, 1, trim)
	# 兜帽
	a._rect(img, cx - 3, top - 5, 6, 6, robe_d)
	a._rect(img, cx - 2, top - 6, 4, 1, robe_d)
	if dir != UP:
		var fx: int = cx - 2 if dir == DOWN else cx - 1
		a._rect(img, fx, top - 4, 4, 3, Color("#141018"))
		var eye := Color("#e080ff")
		a._px(img, fx + 2 if dir == SIDE else fx, top - 3, eye)
		a._px(img, fx + 3, top - 3, eye)
		a._rect(img, cx - 1, top + 1, 2, foot - top - 2, trim.darkened(0.25))
	else:
		a._rect(img, cx - 1, top + 2, 2, 2, trim)
	# 法杖
	var sx: int = cx + 5 if dir != SIDE else cx + 4
	a._rect(img, sx, top - 3, 1, foot - top + 3, Color("#6c4826"))
	a._rect(img, sx - 1, top - 7, 3, 3, Color("#e8e4d0"))
	a._px(img, sx, top - 6, Color("#141018"))
	var orb := Color("#e0a0ff") if f % 2 == 0 else Color("#8040c0")
	a._px(img, sx - 2, top - 8, orb)
	a._px(img, sx + 2, top - 8, orb)
	a._px(img, sx, top - 9, orb)
	return img


## 气球僵尸：吊在红气球下面，两条腿晃来晃去。
static func _balloon(a: Node, s: Dictionary, dir: int, f: int) -> Image:
	var w: int = s["w"]
	var h: int = s["h"]
	var img: Image = a._new(w, h)
	var cx := w / 2
	var bob: int = [0, 1, 0, -1][f] as int
	var red := Color("#d83a4a")
	a._disc(img, cx - 0.5, 9.0 + bob, 7.5, 8.0, red)
	a._disc(img, cx - 2.5, 6.0 + bob, 2.5, 2.5, red.lightened(0.35))
	a._px(img, cx - 3, 5 + bob, Color("#ffe8e8"))
	a._rect(img, cx + 1, 12 + bob, 3, 2, red.darkened(0.3))
	a._rect(img, cx - 1, 17 + bob, 2, 1, red.darkened(0.3))
	for y in range(18 + bob, 23):
		a._px(img, cx - 1 + (y % 2), y, Color("#c8c4b8"))
	var skin := Color(String(s["skin"]))
	var shirt := Color(String(s["shirt"]))
	var pants := Color(String(s["pants"]))
	# 双手抓着绳子
	a._rect(img, cx - 3, 23, 5, 1, skin)
	a._rect(img, cx - 3, 24, 5, 4, skin)
	a._rect(img, cx - 3, 24, 5, 1, Color(String(s["hair"])))
	if dir == DOWN:
		a._px(img, cx - 2, 26, Color(String(s["eye"])))
		a._px(img, cx, 26, Color(String(s["eye"])))
	elif dir == SIDE:
		a._px(img, cx, 26, Color(String(s["eye"])))
	a._rect(img, cx - 3, 28, 5, 4, shirt)
	var swing_l := 1 if f == 1 else 0
	var swing_r := 1 if f == 3 else 0
	a._rect(img, cx - 3 - swing_l, 32, 2, 2, pants)
	a._rect(img, cx + swing_r, 32, 2, 2, pants)
	return img
