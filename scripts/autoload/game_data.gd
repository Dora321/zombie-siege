extends Node
## 全局数值表：武器、僵尸、波次。调平衡只需要改这里。

const MAX_WAVE := 15
const WEAPON_ORDER: Array[String] = ["pistol", "shotgun", "smg"]
const MAX_WEAPON_LEVEL := 5

const WEAPONS := {
	"pistol": {
		"name": "手枪", "damage": 15.0, "cooldown": 0.2, "mag": 12, "reload": 0.8,
		"spread": 1.5, "pellets": 1, "speed": 470.0, "life": 0.75, "knock": 55.0,
		"reserve": - 1, "pierce": 0, "shake": 0.14, "recoil": 2.0, "sfx": "pistol",
		"color": "#ffe9a0", "upgrade_cost": 50,
	},
	"shotgun": {
		"name": "霰弹枪", "damage": 9.0, "cooldown": 0.62, "mag": 6, "reload": 1.25,
		"spread": 11.0, "pellets": 8, "speed": 420.0, "life": 0.36, "knock": 62.0,
		"reserve": 24, "pierce": 0, "shake": 0.42, "recoil": 4.0, "sfx": "shotgun",
		"color": "#ffc070", "upgrade_cost": 70,
	},
	"smg": {
		"name": "冲锋枪", "damage": 8.5, "cooldown": 0.072, "mag": 32, "reload": 1.1,
		"spread": 5.0, "pellets": 1, "speed": 500.0, "life": 0.62, "knock": 26.0,
		"reserve": 128, "pierce": 0, "shake": 0.1, "recoil": 1.5, "sfx": "smg",
		"color": "#fff2c0", "upgrade_cost": 70,
	},
}

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
	return s


func upgrade_cost(id: String, level: int) -> int:
	return int(WEAPONS[id]["upgrade_cost"]) * level


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
