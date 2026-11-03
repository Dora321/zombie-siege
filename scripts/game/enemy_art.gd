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
		"vanguard":
			_vanguard(a, img, s, b, dir, f)
		"plague":
			_plague(a, img, s, b, dir, f)
		"overlord":
			_overlord(a, img, s, b, dir, f)
		"colossus":
			_colossus(a, img, s, b, dir, f)
		"graveborn":
			_graveborn(a, img, s, b, dir, f)
		"burrowlord":
			_burrowlord(a, img, s, b, dir, f)
		"mirror":
			_mirror(a, img, s, b, dir, f)


## 只往空白处画：背后的东西不能盖住已经画好的身体。
static func _behind(a: Node, img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height() and img.get_pixel(xx, yy).a <= 0.0:
				a._px(img, xx, yy, c)


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


## 裂颚先锋：屠夫的配色缩小一号，下巴从中间裂开、挂在胸前一张一合，肩上顶着骨刺。
static func _vanguard(a: Node, img: Image, s: Dictionary, b: Dictionary, dir: int, f: int) -> void:
	var hw: int = s["hw"]
	var hh: int = s["hh"]
	var tw: int = s["tw"]
	var bone := Color("#e8e0c8")
	for x: int in [b["t_left"], b["t_left"] + tw - 1]:
		a._rect(img, x, b["t_top"] - 2, 1, 2, bone)
	if dir == UP:
		# 背后一排骨刺
		for k in 3:
			a._px(img, b["cx"] - 3 + k * 3, b["t_top"] + 2 + k % 2, bone)
		return
	var open: int = [2, 3, 3, 2][f] as int
	var mx: int = b["hx"] + 1 if dir == DOWN else b["hx"] + hw - 4
	var mw: int = hw - 2 if dir == DOWN else 5
	var my: int = b["h_top"] + hh - 2
	var jaw := Color(String(s["skin"])).darkened(0.25)
	a._rect(img, mx, my, mw, open, Color("#200a0c"))
	a._rect(img, mx - 1, my + open, mw + 2, 2, jaw)
	for k in range(0, mw, 2):
		a._px(img, mx + k, my, bone)
		a._px(img, mx + k + 1, my + open - 1, bone)
	# 下巴正中的裂口
	var split_x: int = mx + mw / 2 if dir == DOWN else mx + mw - 2
	a._rect(img, split_x, my + open, 1, 2, Color("#c02020"))


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


## 覆甲巨像：一身铆着铆钉的横向甲片，整个头罩在铁盔里只留眼缝，胸口裂缝里透出熔核。
static func _colossus(a: Node, img: Image, s: Dictionary, b: Dictionary, dir: int, f: int) -> void:
	var tw: int = s["tw"]
	var th: int = s["th"]
	var hw: int = s["hw"]
	var hh: int = s["hh"]
	var t_left: int = b["t_left"]
	var t_top: int = b["t_top"]
	var cx: int = b["cx"]
	var plate := Color("#8c909c")
	var plate_d := Color("#5a5e6a")
	var plate_l := Color("#c4c8d4")
	var rivet := Color("#e8dcb0")
	for k in 3:
		var y: int = t_top + 1 + k * 5
		a._rect(img, t_left, y, tw, 3, plate)
		a._rect(img, t_left, y, tw, 1, plate_l)
		a._rect(img, t_left, y + 2, tw, 1, plate_d)
		for x in range(t_left + 2, t_left + tw - 1, 6):
			a._px(img, x, y + 1, rivet)
	# 两块大肩甲，比身体宽出一截
	a._rect(img, t_left - 5, t_top - 2, 9, 4, plate)
	a._rect(img, t_left - 5, t_top - 2, 9, 1, plate_l)
	a._px(img, t_left - 3, t_top, rivet)
	if dir != SIDE:
		a._rect(img, t_left + tw - 4, t_top - 2, 9, 4, plate)
		a._rect(img, t_left + tw - 4, t_top - 2, 9, 1, plate_l)
		a._px(img, t_left + tw + 2, t_top, rivet)
	# 铁盔
	var hx: int = b["hx"]
	var h_top: int = b["h_top"]
	a._rect(img, hx - 1, h_top - 1, hw + 2, hh + 1, plate_d)
	a._rect(img, hx - 1, h_top - 1, hw + 2, 1, plate_l)
	a._rect(img, hx + hw / 2, h_top - 3, 1, 2, plate_l)
	if dir == UP:
		return
	var slit_x: int = hx if dir == DOWN else hx + hw - 4
	var slit_w: int = hw if dir == DOWN else 4
	a._rect(img, slit_x, h_top + 2, slit_w, 2, Color("#1c0c08"))
	var eye := Color(String(s["eye"]))
	if dir == DOWN:
		a._px(img, hx + 2, h_top + 2, eye)
		a._px(img, hx + hw - 3, h_top + 2, eye)
	else:
		a._px(img, hx + hw - 2, h_top + 2, eye)
	# 胸口的裂缝和熔核，一明一暗地跳
	var core := Color("#ffc050") if f % 2 == 0 else Color("#ff7020")
	var core_y: int = t_top + th / 2
	a._rect(img, cx - 1, t_top + 1, 1, th - 2, Color("#2a1810"))
	a._disc(img, cx - 0.5, core_y, 3.0, 2.5, Color("#2a1810"))
	a._disc(img, cx - 0.5, core_y, 2.0, 1.6, core)
	a._px(img, cx - 1, core_y - 1, Color("#fff0b0"))


## 再生坟主：背着一块墓碑，身上缠着苔藓和根须，胸口一枚绿色符文跟着心跳亮，脚下掉土。
static func _graveborn(a: Node, img: Image, s: Dictionary, b: Dictionary, dir: int, f: int) -> void:
	var tw: int = s["tw"]
	var th: int = s["th"]
	var t_left: int = b["t_left"]
	var t_top: int = b["t_top"]
	var cx: int = b["cx"]
	var stone := Color("#8a8a90")
	var stone_d := Color("#5c5c64")
	var moss := Color("#5a8a3a")
	# 墓碑：背面看整块，正面和侧面只从肩膀后面露出来
	var sx: int = cx - 7
	var sy: int = t_top - 9
	if dir == UP:
		a._rect(img, sx + 1, sy, 12, 1, stone)
		a._rect(img, sx, sy + 1, 14, 13, stone)
		a._rect(img, sx + 13, sy + 1, 1, 13, stone_d)
		a._rect(img, sx + 6, sy + 3, 2, 7, stone_d)
		a._rect(img, sx + 4, sy + 5, 6, 2, stone_d)
		a._rect(img, sx + 1, sy + 11, 4, 2, moss)
	else:
		_behind(a, img, sx + 1, sy, 12, 1, stone)
		_behind(a, img, sx, sy + 1, 14, 9, stone)
		_behind(a, img, sx + 13, sy + 1, 1, 9, stone_d)
	# 苔藓和根须斜着缠在身上
	for k in 4:
		var y: int = t_top + 2 + k * 3
		a._rect(img, t_left + (k * 5) % (tw - 4), y, 4, 1, moss)
		a._px(img, t_left + (k * 5 + 4) % tw, y + 1, moss.darkened(0.3))
	if dir != UP:
		var rune := Color("#b0ff60") if f % 2 == 0 else Color("#70c040")
		var ry: int = t_top + th / 2 - 1
		a._rect(img, cx - 1, ry - 2, 1, 5, rune)
		a._rect(img, cx - 3, ry, 5, 1, rune)
		a._px(img, cx - 3, ry - 2, rune)
		a._px(img, cx + 1, ry + 2, rune)
	# 脚边往下掉的土块
	var soil := Color("#5a4630")
	for k in 3:
		a._px(img, t_left + 3 + k * 7, b["hip"] + (f + k) % 3, soil)


## 掘地领主：矮壮的身子，头戴矿灯，一对铲子一样的大爪，肩上落满土。
static func _burrowlord(a: Node, img: Image, s: Dictionary, b: Dictionary, dir: int, f: int) -> void:
	var tw: int = s["tw"]
	var hw: int = s["hw"]
	var hh: int = s["hh"]
	var t_left: int = b["t_left"]
	var t_top: int = b["t_top"]
	var hx: int = b["hx"]
	var h_top: int = b["h_top"]
	var dirt := Color("#7a5a38")
	var dirt_l := Color("#a07c50")
	# 肩上的土
	for k in 6:
		a._px(img, t_left + 1 + k * 4, t_top + (k % 2), dirt_l if k % 3 == 0 else dirt)
	# 矿工头盔和矿灯
	var helm := Color("#c8a030")
	a._rect(img, hx - 1, h_top - 1, hw + 2, 2, helm)
	a._rect(img, hx - 1, h_top - 1, hw + 2, 1, helm.lightened(0.3))
	if dir != UP:
		var lamp_x: int = hx + hw / 2 - 1 if dir == DOWN else hx + hw - 2
		var lamp := Color("#fff8a0") if f % 2 == 0 else Color("#ffe040")
		a._rect(img, lamp_x, h_top - 2, 3, 2, lamp)
		# 尖鼻子
		var nose_x: int = hx + hw / 2 - 1 if dir == DOWN else hx + hw
		a._rect(img, nose_x, h_top + hh - 3, 2, 2, Color("#e08890"))
	# 两只铲子一样的大爪，挖土时一上一下
	var claw := Color("#e0d8c0")
	var claw_d := Color("#9a9078")
	var dig: int = [0, 1, 0, -1][f] as int
	var sh_y: int = t_top + 3
	if dir == SIDE:
		var x: int = b["cx"] + tw / 2 + int(s["arm_len"])
		a._rect(img, x, sh_y - 1 + dig, 3, 5, claw)
		for k in 3:
			a._rect(img, x + 3, sh_y - 1 + dig + k * 2, 2, 1, claw_d)
		return
	if dir == UP:
		return
	for side in 2:
		var x: int = t_left - int(s["arm_w"]) - 4 if side == 0 else t_left + tw + int(s["arm_w"])
		var y: int = sh_y + 2 + (dig if side == 0 else -dig)
		a._rect(img, x, y, 4, 4, claw)
		a._rect(img, x, y + 3, 4, 1, claw_d)
		for k in 3:
			a._px(img, x + k + (0 if side == 0 else 1), y + 4, claw)


## 镜面女皇：长裙罩住双腿，头顶一圈镜子碎片做的冠，肩上也嵌着碎片。身前的镜子由 boss_brain 按朝向画。
static func _mirror(a: Node, img: Image, s: Dictionary, b: Dictionary, dir: int, f: int) -> void:
	var tw: int = s["tw"]
	var hw: int = s["hw"]
	var t_left: int = b["t_left"]
	var t_top: int = b["t_top"]
	var cx: int = b["cx"]
	var gown := Color(String(s["shirt"]))
	var gown_d := gown.darkened(0.3)
	var trim := Color("#c8d0e8")
	# 长裙：从腰往下越来越宽，盖住两条腿，下摆随步子摆
	var hip: int = b["hip"]
	var foot: int = b["foot"]
	var sway: int = [0, 1, 0, -1][f] as int
	for y in range(hip - 1, foot + 1):
		var grow: int = (y - hip + 1) / 2
		var w: int = tw + grow * 2
		var x: int = cx - w / 2 + (sway if y > foot - 3 else 0)
		a._rect(img, x, y, w, 1, gown)
		a._px(img, x + w - 1, y, gown_d)
	var hem_w: int = tw + (foot - hip + 1) / 2 * 2
	a._rect(img, cx - hem_w / 2 + sway, foot, hem_w, 1, trim)
	# 银领子
	a._rect(img, t_left, t_top, tw, 1, trim)
	# 镜片冠
	var shard := Color("#b8e8ff")
	var shine := Color("#f8fcff")
	var hx: int = b["hx"]
	var h_top: int = b["h_top"]
	for k in 4:
		var x: int = hx + k * (hw - 1) / 3
		var tall: int = 3 if k == 1 or k == 2 else 2
		a._rect(img, x, h_top - tall, 1, tall, shard)
		a._px(img, x, h_top - tall, shine)
	a._rect(img, hx, h_top - 1, hw, 1, trim)
	# 肩上的碎片
	for x: int in [t_left - 2, t_left + tw]:
		a._rect(img, x, t_top - 1, 2, 3, shard)
		a._px(img, x, t_top - 1, shine)
	if dir == DOWN:
		# 胸前一颗菱形宝石
		a._px(img, cx - 1, t_top + 3, shine)
		a._px(img, cx - 2, t_top + 4, shard)
		a._px(img, cx, t_top + 4, shard)
		a._px(img, cx - 1, t_top + 5, shard)


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
