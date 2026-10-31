extends Node
## 全局数值表：武器、道具、掉落、僵尸、波次。调平衡只需要改这里。

const MAX_WAVE := 15
## 顺序决定数字键：第 N 把对应按键 N。
const WEAPON_ORDER: Array[String] = ["pistol", "shotgun", "smg", "sniper", "flamer", "grenade", "arc", "cryo", "boomerang"]
const MAX_WEAPON_LEVEL := 5

const WEAPONS := {
	"pistol": {
		"name": "手枪", "damage": 15.0, "cooldown": 0.2, "mag": 12, "reload": 0.8,
		"spread": 1.5, "pellets": 1, "speed": 470.0, "life": 0.75, "knock": 55.0,
		"reserve": - 1, "pierce": 0, "shake": 0.14, "recoil": 2.0, "sfx": "pistol",
		"color": "#ffe9a0", "upgrade_cost": 50, "casing": "brass", "hint": "伤害射速提升，隔级穿透",
		"unlock_cost": 0, "start_reserve": -1,
	},
	"shotgun": {
		"name": "霰弹枪", "damage": 9.0, "cooldown": 0.62, "mag": 6, "reload": 1.25,
		"spread": 11.0, "pellets": 8, "speed": 420.0, "life": 0.36, "knock": 62.0,
		"reserve": 24, "pierce": 0, "shake": 0.42, "recoil": 4.0, "sfx": "shotgun",
		"color": "#ffc070", "upgrade_cost": 70, "casing": "red", "hint": "伤害提升，弹丸 +1", "big_flash": true,
		"unlock_cost": 0, "start_reserve": 18, "ammo_pack": 12, "ammo_cost": 35, "ammo_drop": 6,
	},
	"smg": {
		"name": "冲锋枪", "damage": 8.5, "cooldown": 0.072, "mag": 32, "reload": 1.1,
		"spread": 5.0, "pellets": 1, "speed": 500.0, "life": 0.62, "knock": 26.0,
		"reserve": 128, "pierce": 0, "shake": 0.1, "recoil": 1.5, "sfx": "smg",
		"color": "#fff2c0", "upgrade_cost": 70, "casing": "brass", "hint": "伤害提升，更稳更快",
		"unlock_cost": 0, "start_reserve": 96, "ammo_pack": 64, "ammo_cost": 35, "ammo_drop": 32,
	},
	# 下面六把要先在商店解锁。mode 决定开火逻辑，见 player.gd 的 _fire_mode
	"sniper": {
		"name": "狙击枪", "damage": 95.0, "cooldown": 1.15, "mag": 5, "reload": 1.7,
		"spread": 0.0, "pellets": 1, "speed": 0.0, "life": 0.0, "knock": 90.0,
		"reserve": 15, "pierce": 4, "shake": 0.6, "recoil": 6.0, "sfx": "sniper",
		"color": "#ff5040", "upgrade_cost": 90, "casing": "brass", "big_flash": true,
		"mode": "beam", "range": 520.0, "flash": "sniper",
		"desc": "高伤穿透多敌和障碍，激光瞄准", "hint": "伤害提升，多穿 1 个",
		"unlock_cost": 180, "start_reserve": 15, "ammo_pack": 10, "ammo_cost": 40, "ammo_drop": 2,
	},
	"flamer": {
		"name": "火焰喷射器", "damage": 3.2, "cooldown": 0.09, "mag": 80, "reload": 1.6,
		"spread": 0.0, "pellets": 1, "speed": 0.0, "life": 0.0, "knock": 0.0,
		"reserve": 160, "pierce": 0, "shake": 0.05, "recoil": 0.5, "sfx": "flamer",
		"color": "#ff9030", "upgrade_cost": 85, "flash": "flame",
		"mode": "flame", "range": 62.0, "cone": 26.0,
		"desc": "短距锥形持续烧伤，地面留火", "hint": "伤害提升，喷得更远",
		"unlock_cost": 200, "start_reserve": 160, "ammo_pack": 120, "ammo_cost": 40, "ammo_drop": 40,
	},
	"grenade": {
		"name": "榴弹发射器", "damage": 30.0, "cooldown": 0.9, "mag": 4, "reload": 1.8,
		"spread": 0.0, "pellets": 1, "speed": 0.0, "life": 0.0, "knock": 0.0,
		"reserve": 12, "pierce": 0, "shake": 0.35, "recoil": 4.5, "sfx": "launcher",
		"color": "#d0c070", "upgrade_cost": 100, "casing": "red", "big_flash": true, "flash": "smoke",
		"mode": "lob", "range": 190.0, "radius": 40.0,
		"desc": "抛物线落点爆炸，引爆炸药桶", "hint": "伤害提升，爆炸范围加大",
		"unlock_cost": 240, "start_reserve": 12, "ammo_pack": 8, "ammo_cost": 45, "ammo_drop": 2,
	},
	"arc": {
		"name": "电弧枪", "damage": 20.0, "cooldown": 0.26, "mag": 24, "reload": 1.3,
		"spread": 0.0, "pellets": 1, "speed": 0.0, "life": 0.0, "knock": 12.0,
		"reserve": 72, "pierce": 0, "shake": 0.16, "recoil": 1.5, "sfx": "arc",
		"color": "#90d0ff", "upgrade_cost": 90, "flash": "arc",
		"mode": "arc", "range": 150.0, "chain": 3, "jump": 64.0,
		"desc": "闪电在僵尸之间连跳", "hint": "伤害提升，多跳 1 次",
		"unlock_cost": 220, "start_reserve": 72, "ammo_pack": 48, "ammo_cost": 40, "ammo_drop": 12,
	},
	"cryo": {
		"name": "冰冻枪", "damage": 6.0, "cooldown": 0.12, "mag": 30, "reload": 1.2,
		"spread": 3.0, "pellets": 1, "speed": 300.0, "life": 0.5, "knock": 4.0,
		"reserve": 90, "pierce": 0, "shake": 0.05, "recoil": 0.8, "sfx": "cryo",
		"color": "#a8ecff", "upgrade_cost": 75, "flash": "cryo", "chill": 0.2,
		"desc": "减速再冻住，冻住的僵尸更吃伤害", "hint": "伤害提升，冻得更快",
		"unlock_cost": 160, "start_reserve": 90, "ammo_pack": 60, "ammo_cost": 35, "ammo_drop": 16,
	},
	"boomerang": {
		"name": "回旋镖", "damage": 26.0, "cooldown": 0.35, "mag": 1, "reload": 0.0,
		"spread": 0.0, "pellets": 1, "speed": 260.0, "life": 0.0, "knock": 40.0,
		"reserve": -1, "pierce": 0, "shake": 0.08, "recoil": 1.0, "sfx": "boomerang",
		"color": "#e0a050", "upgrade_cost": 70, "flash": "none",
		"mode": "boomerang", "range": 150.0, "returns": true,
		"desc": "飞出去再飞回来，往返都能穿透", "hint": "伤害提升，隔级多带一把",
		"unlock_cost": 150, "start_reserve": -1,
	},
}

## 冰冻和燃烧的数值。
const CHILL_SLOW := 0.5
const CHILL_SLOW_BOSS := 0.7
const CHILL_TIME := 1.8
const FREEZE_TIME := 1.8
const CHILL_VULN := 1.25
const FREEZE_VULN := 1.5
const BURN_DPS := 8.0

## 道具：按顺序排在快捷栏。pack 是商店一次买几个，max 是最多带几个，start 是开局自带。
const ITEM_ORDER: Array[String] = ["medkit", "armor", "frag", "sticky", "flash", "decoy", "ammo_crate", "inf_ammo", "speed", "damage", "nuke"]
const ITEMS := {
	"medkit": {"name": "医疗包", "desc": "生命 +50，战斗中随时用", "cost": 45, "pack": 1, "max": 5, "start": 1, "power": 50.0},
	"armor": {"name": "护甲板", "desc": "护甲 +50，先于生命扣", "cost": 60, "pack": 1, "max": 3, "start": 0, "power": 50.0},
	"frag": {"name": "手雷", "desc": "朝准星扔，落地爆炸", "cost": 40, "pack": 2, "max": 8, "start": 2, "power": 38.0, "radius": 44.0},
	"sticky": {"name": "粘性炸弹", "desc": "粘在僵尸身上，延时重伤", "cost": 35, "pack": 1, "max": 6, "start": 0, "power": 70.0, "radius": 40.0},
	"flash": {"name": "闪光弹", "desc": "大范围眩晕，Boss 只晕一下", "cost": 30, "pack": 1, "max": 5, "start": 0, "power": 2.6, "radius": 110.0},
	"decoy": {"name": "诱饵", "desc": "吸引附近僵尸，撑 8 秒", "cost": 40, "pack": 1, "max": 4, "start": 0, "power": 8.0, "radius": 170.0},
	"ammo_crate": {"name": "弹药箱", "desc": "全武器补满弹匣和备弹", "cost": 50, "pack": 1, "max": 3, "start": 0, "power": 3.0},
	"inf_ammo": {"name": "无限弹药", "desc": "10 秒内不耗弹不换弹", "cost": 70, "pack": 1, "max": 3, "start": 0, "power": 10.0},
	"speed": {"name": "速度药水", "desc": "12 秒内移速 +40%", "cost": 45, "pack": 1, "max": 3, "start": 0, "power": 12.0},
	"damage": {"name": "伤害药水", "desc": "12 秒内武器伤害 +60%", "cost": 60, "pack": 1, "max": 3, "start": 0, "power": 12.0},
	"nuke": {"name": "核弹", "desc": "每波限 1 次，清屏重创 Boss", "cost": 350, "pack": 1, "max": 2, "start": 0, "power": 1.0},
}
const THROW_RANGE := 160.0
const ARMOR_MAX := 100.0
const SPEED_BUFF := 1.4
const DAMAGE_BUFF := 1.6
## 道具已带满时捡到的折算金币。
const ITEM_OVERFLOW_COINS := 10

## 击杀掉落：按顺序掷一次，互斥。坦克概率翻倍，Boss 必掉一件。
const DROPS: Array[Dictionary] = [
	{"kind": "ammo", "chance": 0.045},
	{"kind": "med", "chance": 0.02},
	{"item": "frag", "chance": 0.014},
	{"item": "medkit", "chance": 0.007},
	{"item": "armor", "chance": 0.007},
	{"item": "sticky", "chance": 0.007},
	{"item": "flash", "chance": 0.007},
	{"item": "decoy", "chance": 0.005},
	{"item": "ammo_crate", "chance": 0.004},
	{"item": "speed", "chance": 0.004},
	{"item": "damage", "chance": 0.004},
	{"item": "inf_ammo", "chance": 0.003},
	{"item": "nuke", "chance": 0.0006},
]
const BOSS_DROPS: Array[String] = ["nuke", "damage", "inf_ammo", "armor", "ammo_crate"]

## 僵尸属性：hit_r 是子弹判定半径，center 是身体中心离脚底的高度。
const ZOMBIES := {
	"walker": {
		"name": "普通僵尸", "hp": 34.0, "speed": 27.0, "damage": 7.0, "attack_cd": 0.95,
		"coins": 3, "score": 10, "hit_r": 6.0, "center": 7.0, "knock_res": 0.0, "aggro": 85.0,
		"blood": "#8c1c1c",
	},
	"runner": {
		"name": "快跑僵尸", "hp": 18.0, "speed": 62.0, "damage": 5.0, "attack_cd": 0.55,
		"coins": 3, "score": 15, "hit_r": 5.5, "center": 6.0, "knock_res": 0.0, "aggro": 130.0,
		"blood": "#8c1c1c",
	},
	"tank": {
		"name": "坦克僵尸", "hp": 240.0, "speed": 18.0, "damage": 22.0, "attack_cd": 1.25,
		"coins": 14, "score": 60, "hit_r": 11.0, "center": 11.0, "knock_res": 0.85, "aggro": 90.0,
		"blood": "#6e1414",
	},
	"exploder": {
		"name": "自爆僵尸", "hp": 26.0, "speed": 38.0, "damage": 42.0, "attack_cd": 1.0,
		"coins": 6, "score": 25, "hit_r": 8.0, "center": 8.0, "knock_res": 0.2, "aggro": 110.0,
		"blood": "#7f9c20",
	},
	"spitter": {
		"name": "喷吐僵尸", "hp": 36.0, "speed": 24.0, "damage": 9.0, "attack_cd": 2.4,
		"coins": 6, "score": 30, "hit_r": 6.0, "center": 7.0, "knock_res": 0.0, "aggro": 150.0,
		"blood": "#4c8a2a", "range": 135.0,
	},
	"boss": {
		"name": "屠夫", "hp": 950.0, "speed": 21.0, "damage": 30.0, "attack_cd": 1.3,
		"coins": 120, "score": 600, "hit_r": 15.0, "center": 15.0, "knock_res": 0.96, "aggro": 140.0,
		"blood": "#6e1414",
	},
}

## 手工设计的 15 波节奏，每 5 波一个 Boss 关。
const WAVES := [
	{"name": "先头部队", "walker": 9},
	{"name": "脚步渐近", "walker": 12, "runner": 3},
	{"name": "毒液来袭", "walker": 13, "runner": 4, "spitter": 2},
	{"name": "会爆炸的家伙", "walker": 14, "runner": 5, "spitter": 2, "exploder": 3},
	{"name": "屠夫现身", "walker": 10, "runner": 5, "exploder": 2, "boss": 1},
	{"name": "快跑潮", "walker": 8, "runner": 24, "exploder": 2},
	{"name": "铁壁", "walker": 18, "runner": 6, "spitter": 3, "tank": 2},
	{"name": "酸雨", "walker": 18, "runner": 8, "spitter": 8, "exploder": 3, "tank": 1},
	{"name": "火药桶", "walker": 16, "runner": 12, "exploder": 12, "tank": 2},
	{"name": "屠夫归来", "walker": 22, "runner": 12, "spitter": 5, "exploder": 5, "tank": 2, "boss": 1},
	{"name": "黑夜降临", "walker": 34, "runner": 20, "spitter": 7, "exploder": 7, "tank": 4},
	{"name": "钢铁洪流", "walker": 24, "runner": 16, "spitter": 7, "exploder": 7, "tank": 8},
	{"name": "尸潮", "walker": 52, "runner": 32, "spitter": 9, "exploder": 10, "tank": 5},
	{"name": "绝望之墙", "walker": 32, "runner": 24, "spitter": 11, "exploder": 12, "tank": 8},
	{"name": "最终围城", "walker": 38, "runner": 30, "spitter": 11, "exploder": 12, "tank": 6, "boss": 2},
]


func weapon_stats(id: String, level: int) -> Dictionary:
	var s: Dictionary = WEAPONS[id].duplicate()
	var l := level - 1
	s["level"] = level
	s["damage"] = float(s["damage"]) * (1.0 + 0.24 * l)
	s["cooldown"] = float(s["cooldown"]) * pow(0.94, l)
	s["reload"] = float(s["reload"]) * pow(0.92, l)
	s["mag"] = roundi(int(s["mag"]) * (1.0 + 0.2 * l))
	match id:
		"pistol":
			s["pierce"] = l / 2
		"shotgun":
			s["pellets"] = int(s["pellets"]) + l
		"smg":
			s["spread"] = float(s["spread"]) * pow(0.88, l)
		"sniper":
			s["pierce"] = int(s["pierce"]) + l
		"flamer":
			s["range"] = float(s["range"]) + 6.0 * l
		"grenade":
			s["radius"] = float(s["radius"]) + 3.0 * l
		"arc":
			s["chain"] = int(s["chain"]) + l
		"cryo":
			s["chill"] = float(s["chill"]) + 0.03 * l
		"boomerang":
			s["mag"] = 1 + l / 2
			s["range"] = float(s["range"]) + 10.0 * l
	return s


## level 为 0 表示还没解锁，这时返回解锁价。
func upgrade_cost(id: String, level: int) -> int:
	if level <= 0:
		return int(WEAPONS[id]["unlock_cost"])
	return int(WEAPONS[id]["upgrade_cost"]) * level


## 掷一次击杀掉落，返回掉落表里的一项，没掉东西返回空字典。
func roll_drop(zombie_kind: String) -> Dictionary:
	if zombie_kind == "boss":
		return {"item": BOSS_DROPS[randi() % BOSS_DROPS.size()]}
	var mult := 2.0 if zombie_kind == "tank" else 1.0
	var roll := randf()
	for entry: Dictionary in DROPS:
		roll -= float(entry["chance"]) * mult
		if roll < 0.0:
			return entry
	return {}


## 把一波的配置展开成乱序的出怪队列；Boss 压轴在队列中段之后出现。
func build_spawn_queue(wave: int) -> Array[String]:
	var cfg: Dictionary = WAVES[clampi(wave - 1, 0, WAVES.size() - 1)]
	var queue: Array[String] = []
	for kind in ZOMBIES.keys():
		if kind == "boss":
			continue
		for i in int(cfg.get(kind, 0)):
			queue.append(kind)
	queue.shuffle()
	for i in int(cfg.get("boss", 0)):
		var at := queue.size() / 2 + i * 12
		queue.insert(mini(at, queue.size()), "boss")
	return queue


func wave_name(wave: int) -> String:
	return String(WAVES[clampi(wave - 1, 0, WAVES.size() - 1)]["name"])


func hp_scale(wave: int) -> float:
	return 1.0 + (wave - 1) * 0.065


func damage_scale(wave: int) -> float:
	return 1.0 + (wave - 1) * 0.035


func spawn_interval(wave: int) -> float:
	return maxf(0.6, 1.6 - wave * 0.07)


func wave_bonus(wave: int) -> int:
	return 90 + wave * 30
