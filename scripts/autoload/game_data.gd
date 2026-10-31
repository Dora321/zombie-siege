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

## 击杀掉落：按顺序掷一次，互斥。坦克概率翻倍，精英 1.5 倍，Boss 必掉。
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
const ELITE_DROP_MULT := 1.5
## Boss 专属战利品：捡到立刻生效，整局有效。
const TROPHIES := {
	"heart": {"name": "屠夫之心", "desc": "生命上限 +25 并回满"},
	"serum": {"name": "母体血清", "desc": "毒雾和酸液伤害减半"},
	"crown": {"name": "尸王之冠", "desc": "分数 +3000"},
}
const TROPHY_HP := 25.0
const TROPHY_DOT := 0.5
const TROPHY_SCORE := 3000

## 僵尸属性：hit_r 是子弹判定半径，center 是身体中心离脚底的高度。
## desc 和 tip 是图鉴文案，is_boss 的配置在 BOSSES。
const ZOMBIES := {
	"walker": {
		"name": "普通僵尸", "hp": 34.0, "speed": 27.0, "damage": 7.0, "attack_cd": 0.95,
		"coins": 3, "score": 10, "hit_r": 6.0, "center": 7.0, "knock_res": 0.0, "aggro": 85.0,
		"blood": "#8c1c1c", "desc": "速度慢，数量多", "tip": "手枪和炮塔就能处理",
	},
	"runner": {
		"name": "快跑僵尸", "hp": 18.0, "speed": 62.0, "damage": 5.0, "attack_cd": 0.55,
		"coins": 3, "score": 15, "hit_r": 5.5, "center": 6.0, "knock_res": 0.0, "aggro": 130.0,
		"blood": "#8c1c1c", "desc": "血薄跑得快，老远就盯上你", "tip": "冲锋枪扫，别被围",
	},
	"tank": {
		"name": "坦克僵尸", "hp": 240.0, "speed": 18.0, "damage": 22.0, "attack_cd": 1.25,
		"coins": 14, "score": 60, "hit_r": 11.0, "center": 11.0, "knock_res": 0.85, "aggro": 90.0,
		"blood": "#6e1414", "desc": "血厚不吃击退，拆墙伤害翻倍", "tip": "集火，引去炸药桶",
	},
	"exploder": {
		"name": "自爆僵尸", "hp": 26.0, "speed": 38.0, "damage": 42.0, "attack_cd": 1.0,
		"coins": 6, "score": 25, "hit_r": 8.0, "center": 8.0, "knock_res": 0.2, "aggro": 110.0,
		"blood": "#7f9c20", "desc": "碰到东西 0.5 秒后爆炸", "tip": "远距离打死，还能炸到同类",
	},
	"spitter": {
		"name": "喷吐僵尸", "hp": 36.0, "speed": 24.0, "damage": 9.0, "attack_cd": 2.4,
		"coins": 6, "score": 30, "hit_r": 6.0, "center": 7.0, "knock_res": 0.0, "aggro": 150.0,
		"blood": "#4c8a2a", "range": 135.0, "desc": "远程吐酸越过围墙，留下酸液池", "tip": "优先击杀，别站在酸液里",
	},
	"stalker": {
		"name": "潜伏者", "hp": 46.0, "speed": 40.0, "damage": 24.0, "attack_cd": 1.4,
		"coins": 8, "score": 45, "hit_r": 5.5, "center": 8.0, "knock_res": 0.1, "aggro": 260.0,
		"blood": "#4a2a6a", "melee": 0.4, "elite": true,
		"desc": "半透明摸到身边，现身后猛扑一口", "tip": "留意地上的扭曲，一闪红就冲刺躲开",
	},
	"shielder": {
		"name": "护盾兵", "hp": 72.0, "speed": 23.0, "damage": 11.0, "attack_cd": 1.1,
		"coins": 10, "score": 45, "hit_r": 7.0, "center": 9.0, "knock_res": 0.7, "aggro": 120.0,
		"blood": "#8c1c1c", "shield": 70.0, "elite": true,
		"desc": "盾牌挡下正面子弹，盾转得慢", "tip": "绕后，或用爆炸、火焰、电弧、眩晕",
	},
	"splitter": {
		"name": "分裂体", "hp": 80.0, "speed": 25.0, "damage": 9.0, "attack_cd": 1.0,
		"coins": 7, "score": 35, "hit_r": 9.0, "center": 9.0, "knock_res": 0.3, "aggro": 90.0,
		"blood": "#6a9c30", "split": 3, "elite": true,
		"desc": "死后裂成 2~3 只快跑的小怪", "tip": "留一发范围武器收拾小怪",
	},
	"splitling": {
		"name": "分裂小怪", "hp": 14.0, "speed": 54.0, "damage": 4.0, "attack_cd": 0.7,
		"coins": 1, "score": 4, "hit_r": 4.5, "center": 4.0, "knock_res": 0.0, "aggro": 130.0,
		"blood": "#6a9c30", "desc": "分裂体死后的碎块", "tip": "一枪一只",
	},
	"summoner": {
		"name": "召唤者", "hp": 60.0, "speed": 21.0, "damage": 6.0, "attack_cd": 1.2,
		"coins": 12, "score": 60, "hit_r": 6.5, "center": 10.0, "knock_res": 0.1, "aggro": 170.0,
		"blood": "#5a2a8a", "elite": true,
		"desc": "躲在远处吟唱，把小鬼叫到你身边", "tip": "直接打它，它一死小鬼全散",
	},
	"imp": {
		"name": "小鬼", "hp": 14.0, "speed": 46.0, "damage": 4.0, "attack_cd": 0.8,
		"coins": 1, "score": 3, "hit_r": 4.5, "center": 5.0, "knock_res": 0.0, "aggro": 170.0,
		"blood": "#5a2a8a", "desc": "召唤者叫来的骷髅", "tip": "看到紫圈就走开",
	},
	"screamer": {
		"name": "尖叫者", "hp": 50.0, "speed": 31.0, "damage": 5.0, "attack_cd": 1.0,
		"coins": 10, "score": 50, "hit_r": 6.0, "center": 9.0, "knock_res": 0.1, "aggro": 150.0,
		"blood": "#8c1c4c", "elite": true,
		"desc": "尖叫让周围僵尸加速冲向你或基地", "tip": "蓄力时发抖，趁机打断或击杀",
	},
	"balloon": {
		"name": "气球僵尸", "hp": 38.0, "speed": 32.0, "damage": 16.0, "attack_cd": 2.6,
		"coins": 9, "score": 40, "hit_r": 9.0, "center": 28.0, "knock_res": 0.0, "aggro": 190.0,
		"blood": "#8c1c1c", "flying": true, "elite": true,
		"desc": "飘过围墙，在头顶投下毒弹", "tip": "打爆气球会摔下一只半血僵尸",
	},
	"boss": {
		"name": "屠夫", "hp": 950.0, "speed": 21.0, "damage": 30.0, "attack_cd": 1.3,
		"coins": 150, "score": 600, "hit_r": 15.0, "center": 15.0, "knock_res": 0.96, "aggro": 140.0,
		"blood": "#6e1414", "is_boss": true,
	},
	"plague": {
		"name": "瘟疫母体", "hp": 1300.0, "speed": 19.0, "damage": 26.0, "attack_cd": 1.5,
		"coins": 260, "score": 1200, "hit_r": 16.0, "center": 15.0, "knock_res": 0.97, "aggro": 150.0,
		"blood": "#5e8a20", "is_boss": true,
	},
	"overlord": {
		"name": "尸王", "hp": 2600.0, "speed": 22.0, "damage": 32.0, "attack_cd": 1.3,
		"coins": 500, "score": 3000, "hit_r": 18.0, "center": 20.0, "knock_res": 0.98, "aggro": 170.0,
		"blood": "#4a2a6a", "is_boss": true,
	},
}

## Boss 的阶段表。at 是进入该阶段的血量比例，moves 是招式池，enter 是一进阶段就放的招。
## 招式实现见 boss_brain.gd。
const BOSSES := {
	"boss": {
		"title": "屠夫", "warn": "看到红色通道就侧向闪开", "trophy": "heart", "drops": ["armor", "ammo_crate", "damage"],
		"phases": [
			{"at": 1.0, "name": "屠刀", "sub": "", "speed": 1.0, "gap": [2.4, 3.4], "rocks": 3, "moves": ["charge", "slam", "rocks"]},
			{"at": 0.5, "name": "狂怒", "sub": "连环冲撞，还叫来了帮手", "speed": 1.35, "gap": [1.5, 2.3], "rocks": 5, "tint": "#ffa8a0",
				"enter": "call", "call": ["runner", "runner", "exploder"], "moves": ["charge2", "slam", "rocks", "call"]},
		],
	},
	"plague": {
		"title": "瘟疫母体", "warn": "毒雾会缓慢掉血，离开绿圈", "trophy": "serum", "drops": ["medkit", "inf_ammo", "armor"], "shield": 0.16,
		"phases": [
			{"at": 1.0, "name": "孢子", "sub": "", "speed": 1.0, "gap": [2.2, 3.2], "call": ["splitling", "splitling", "spitter"], "moves": ["fog", "fan", "call"]},
			{"at": 0.55, "name": "脓盾", "sub": "先打破绿色护盾，再打本体", "speed": 0.9, "gap": [1.7, 2.6], "tint": "#d8ffa0",
				"enter": "shield", "call": ["splitter", "spitter", "screamer"], "moves": ["fogring", "fog", "fan", "shield", "call"]},
		],
	},
	"overlord": {
		"title": "尸王", "warn": "这是最后一战，它会用尽所有手段", "trophy": "crown", "final": true, "drops": ["nuke", "damage", "armor"], "shield": 0.1, "slam_scale": 1.25,
		"elites": ["stalker", "shielder", "splitter", "summoner", "screamer", "balloon"],
		"phases": [
			{"at": 1.0, "name": "围城", "sub": "", "speed": 1.0, "gap": [2.2, 3.2], "rocks": 5, "moves": ["charge", "slam", "rocks"]},
			{"at": 0.75, "name": "亡者号令", "sub": "精英活着时本体大幅减伤，先清精英", "speed": 1.0, "gap": [2.0, 3.0], "rocks": 5, "guard": 0.45, "tint": "#d8c0ff",
				"enter": "elites", "moves": ["elites", "charge", "rocks", "wave"]},
			{"at": 0.5, "name": "瘟疫之息", "sub": "毒雾、护盾和全场尖叫", "speed": 1.1, "gap": [1.7, 2.5], "tint": "#d0ffb0",
				"enter": "shield", "moves": ["fog", "fan", "fogring", "scream", "wave", "shield"]},
			{"at": 0.25, "name": "末日狂暴", "sub": "落石如雨，别停下", "speed": 1.4, "gap": [1.2, 1.9], "rocks": 7, "tint": "#ff9090",
				"enter": "storm", "moves": ["charge2", "storm", "wave", "slam", "elites", "fog"]},
		],
	},
}

## 特殊波的数值：酸雨每隔几秒落几滴。
const ACID_RAIN_GAP := 3.2
const ACID_RAIN_COUNT := 3
const ACID_RAIN_DAMAGE := 10.0

## 手工设计的 15 波节奏：新敌人逐波登场，第 5、10、15 波是 Boss 阶段战，第 8、12 波是特殊波。
const WAVES := [
	{"name": "先头部队", "walker": 9},
	{"name": "脚步渐近", "walker": 12, "runner": 3},
	{"name": "毒液来袭", "walker": 13, "runner": 4, "spitter": 2},
	{"name": "会爆炸的家伙", "walker": 12, "runner": 5, "spitter": 2, "exploder": 3, "splitter": 2},
	{"name": "屠夫现身", "walker": 8, "runner": 4, "exploder": 2, "boss": 1},
	{"name": "暗处的眼睛", "walker": 10, "runner": 16, "exploder": 2, "stalker": 3},
	{"name": "铁壁", "walker": 14, "runner": 6, "spitter": 3, "tank": 2, "shielder": 3},
	{"name": "酸雨", "walker": 16, "runner": 8, "spitter": 7, "exploder": 3, "tank": 1, "splitter": 3, "special": "acid_rain", "hint": "天上在下酸雨，看到地上的红圈就走开"},
	{"name": "火药桶", "walker": 14, "runner": 10, "exploder": 10, "tank": 2, "summoner": 2},
	{"name": "瘟疫母体", "walker": 16, "runner": 8, "spitter": 3, "exploder": 3, "tank": 1, "splitter": 2, "screamer": 1, "plague": 1},
	{"name": "黑夜降临", "walker": 28, "runner": 16, "spitter": 5, "exploder": 6, "tank": 3, "screamer": 3, "balloon": 2},
	{"name": "断电之夜", "walker": 18, "runner": 12, "spitter": 5, "exploder": 5, "tank": 4, "shielder": 4, "stalker": 8, "special": "blackout", "hint": "全城断电，潜伏者最爱这种夜晚"},
	{"name": "尸潮", "walker": 42, "runner": 26, "spitter": 7, "exploder": 8, "tank": 4, "splitter": 5, "balloon": 4, "screamer": 2},
	{"name": "绝望之墙", "walker": 24, "runner": 18, "spitter": 8, "exploder": 8, "tank": 6, "shielder": 8, "summoner": 3, "screamer": 3, "balloon": 3},
	{"name": "最终围城", "walker": 22, "runner": 16, "spitter": 5, "exploder": 6, "tank": 3, "shielder": 3, "stalker": 3, "overlord": 1},
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
	if is_boss(zombie_kind):
		return {"item": BOSS_DROPS[randi() % BOSS_DROPS.size()]}
	var mult := 2.0 if zombie_kind == "tank" else 1.0
	if bool(ZOMBIES[zombie_kind].get("elite", false)):
		mult = ELITE_DROP_MULT
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
	for kind: String in ZOMBIES.keys():
		if is_boss(kind):
			continue
		for i in int(cfg.get(kind, 0)):
			queue.append(kind)
	queue.shuffle()
	for kind: String in BOSSES.keys():
		for i in int(cfg.get(kind, 0)):
			var at := queue.size() / 2 + i * 12
			queue.insert(mini(at, queue.size()), kind)
	return queue


func is_boss(kind: String) -> bool:
	return bool(ZOMBIES[kind].get("is_boss", false))


func wave_special(wave: int) -> String:
	return String(WAVES[clampi(wave - 1, 0, WAVES.size() - 1)].get("special", ""))


func wave_hint(wave: int) -> String:
	return String(WAVES[clampi(wave - 1, 0, WAVES.size() - 1)].get("hint", ""))


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
