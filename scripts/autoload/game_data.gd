extends Node
## 全局数值表：武器、道具、掉落、僵尸、波次。调平衡只需要改这里。

const MAX_WAVE := 15
## 商店情报最多列几种怪。
const PREVIEW_KINDS := 5
## 顺序决定数字键：第 N 把对应按键 N。
const WEAPON_ORDER: Array[String] = ["pistol", "shotgun", "smg", "sniper", "flamer", "grenade", "arc", "cryo", "boomerang"]
const MAX_WEAPON_LEVEL := 5
## 随身枪袋：开局 4 格（手枪、霰弹、冲锋占 3 格），商店扩容一次到 5 格。
const BASE_WEAPON_SLOTS := 4
const MAX_WEAPON_SLOTS := 5
const SLOT_COST := 220

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

## 武器进化：满级的枪满足 need 后在商店花 EVOLVE_COST 原地进化（同一把枪，不占枪袋），每种专克一类题。
## need.item 是要带着的道具，consume 是进化时扣几个（0 表示带着就行）；used 为 true 时本局用过这种道具也算；
## kills 是本局击杀 kinds 的累计数，够 count 也算。走 used 或 kills 的不扣道具。开火分支见 player._fire_mode。
const EVOLVE_COST := 50
const EVOLUTIONS := {
	"frost_mine": {
		"base": "cryo", "name": "冰封雷", "counter": "群体控场：尸潮、尖叫加速、再生",
		"desc": "冰弹留雷，片刻后炸开冻一圈", "need": {"item": "sticky", "consume": 1},
	},
	"saw_rang": {
		"base": "boomerang", "name": "锯刃回旋", "counter": "护盾兵正面、镜面女皇",
		"desc": "伤害 +25%，锯穿盾牌，镜子弹不回", "need": {"item": "damage", "consume": 0, "used": true},
	},
	"storm_rod": {
		"base": "arc", "name": "避雷针", "counter": "密集尸群、暴雨波",
		"desc": "首跳 +20%，湿身更痛，诱饵引雷", "need": {"item": "decoy", "consume": 1},
	},
	"thermite": {
		"base": "grenade", "name": "铝热榴弹", "counter": "覆甲巨像、坦克",
		"desc": "炸开留一圈久烧的火，打重甲 +20%", "need": {"item": "frag", "consume": 1, "used": true},
	},
	"puncturer": {
		"base": "sniper", "name": "穿甲狙击", "counter": "铁壁波、护盾兵、覆甲巨像",
		"desc": "穿盾不减伤，打重甲 +20%",
		"need": {"item": "sticky", "consume": 1, "kills": {"kinds": ["tank", "shielder", "colossus"], "count": 8}},
	},
}
## 冰封雷：每只身上同时只挂一颗，FUSE 秒后在它身上炸开，半径内全体上冰，伤害是这发冰弹的倍数。
const FROST_MINE_FUSE := 0.6
const FROST_MINE_R := 30.0
const FROST_MINE_CHILL := 0.55
const FROST_MINE_DAMAGE := 1.5
## 锯刃回旋：伤害倍率；正面锯过盾牌时顺带磨掉的盾耐久（按这一下伤害的比例）。
const SAW_MULT := 1.25
const SAW_SHIELD_WEAR := 0.5
## 避雷针：首跳加成、湿身再乘的倍率；导电诱饵在射程内且大致在前方时电弧先打到诱饵，再从诱饵多连几跳。
const ROD_FIRST := 1.2
const ROD_WET := 1.25
const ROD_DECOY_CHAIN := 2
## 铝热榴弹：落点留几团火、每团烧多久，对坦克和覆甲 Boss 的加成。
const THERMITE_FIRES := 6
const THERMITE_FIRE_TIME := 6.0
const THERMITE_HEAVY := 1.2
## 穿甲狙击：打坦克、举盾的护盾兵和覆甲 Boss 的加成；穿盾也不再减半。
const PUNCTURE_MULT := 1.2

## 冰冻和燃烧的数值。
const CHILL_SLOW := 0.5
const CHILL_SLOW_BOSS := 0.7
const CHILL_TIME := 1.8
const FREEZE_TIME := 1.8
const CHILL_VULN := 1.25
const FREEZE_VULN := 1.5
const BURN_DPS := 8.0
## 元素联动。湿身（下雨、踩酸液池、被酸雨溅到）时电弧伤害翻倍，和暴雨本身的电弧加成叠乘；
## 冻住时挨霰弹或狙击会碎冰：这一下多吃一半，同一枪的弹丸都算，然后解冻；
## 先燃后冻（烧着时上冰）会淬火：几秒内 Boss 的覆甲和护盾兵的盾都失效。
const WET_ARC := 2.0
const WET_HOLD := 0.6
const WET_SPLASH := 2.5
const SHATTER_BONUS := 0.5
const SHATTER_GRACE := 0.08
const QUENCH_TIME := 3.0

## 道具：按顺序排在快捷栏。pack 是商店一次买几个，max 是最多带几个，start 是开局自带。
const ITEM_ORDER: Array[String] = ["medkit", "armor", "frag", "sticky", "flash", "decoy", "ammo_crate", "inf_ammo", "speed", "damage", "nuke"]
const ITEMS := {
	"medkit": {"name": "医疗包", "desc": "生命 +50，战斗中随时用", "cost": 50, "pack": 1, "max": 5, "start": 1, "power": 50.0},
	"armor": {"name": "护甲板", "desc": "护甲 +50，先于生命扣", "cost": 65, "pack": 1, "max": 3, "start": 0, "power": 50.0},
	"frag": {"name": "手雷", "desc": "朝准星扔，落地爆炸", "cost": 40, "pack": 2, "max": 8, "start": 2, "power": 38.0, "radius": 44.0},
	"sticky": {"name": "粘性炸弹", "desc": "粘在僵尸身上，延时重伤", "cost": 35, "pack": 1, "max": 6, "start": 0, "power": 70.0, "radius": 40.0},
	"flash": {"name": "闪光弹", "desc": "大范围眩晕，Boss 只晕一下", "cost": 30, "pack": 1, "max": 5, "start": 0, "power": 2.6, "radius": 110.0},
	"decoy": {"name": "诱饵", "desc": "吸引附近僵尸，撑 8 秒", "cost": 40, "pack": 1, "max": 4, "start": 0, "power": 8.0, "radius": 170.0},
	"ammo_crate": {"name": "弹药箱", "desc": "全武器补满弹匣和备弹", "cost": 50, "pack": 1, "max": 3, "start": 0, "power": 3.0},
	"inf_ammo": {"name": "无限弹药", "desc": "10 秒内不耗弹不换弹", "cost": 70, "pack": 1, "max": 3, "start": 0, "power": 10.0},
	"speed": {"name": "速度药水", "desc": "12 秒内移速 +40%", "cost": 45, "pack": 1, "max": 3, "start": 0, "power": 12.0},
	"damage": {"name": "伤害药水", "desc": "12 秒内武器伤害 +60%", "cost": 60, "pack": 1, "max": 3, "start": 0, "power": 12.0},
	"nuke": {"name": "核弹", "desc": "每波限 1 次，清屏重创 Boss", "cost": 400, "pack": 1, "max": 2, "start": 0, "power": 1.0},
}
const THROW_RANGE := 160.0
const ARMOR_MAX := 100.0
const SPEED_BUFF := 1.4
const DAMAGE_BUFF := 1.6
## 道具已带满时捡到的折算金币。
const ITEM_OVERFLOW_COINS := 10

## 击杀掉落：按顺序掷一次，互斥。坦克概率翻倍，精英 1.5 倍，Boss 必掉。
const DROPS: Array[Dictionary] = [
	{"kind": "ammo", "chance": 0.04},
	{"kind": "med", "chance": 0.016},
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
	"plating": {"name": "巨像甲片", "desc": "粘性炸弹伤害 +15%"},
	"ash": {"name": "坟主骨灰", "desc": "冰冻和燃烧多持续 0.5 秒"},
	"soil": {"name": "掘地晶石", "desc": "手雷、粘弹和榴弹对 Boss 伤害 +10%"},
	"shard": {"name": "镜面碎片", "desc": "镜面反弹的伤害再减半"},
}
const TROPHY_HP := 25.0
const TROPHY_DOT := 0.5
const TROPHY_SCORE := 3000
const TROPHY_STICKY := 1.15
const TROPHY_STATUS_TIME := 0.5
const TROPHY_BLAST_BOSS := 1.1
const TROPHY_REFLECT := 0.5

## 僵尸属性：hit_r 是子弹判定半径，center 是身体中心离脚底的高度。
## desc 和 tip 是图鉴文案，weak 是弱点短标签（/ 分隔，图鉴和商店情报都用），is_boss 的配置在 BOSSES。
const ZOMBIES := {
	"walker": {
		"name": "普通僵尸", "hp": 35.0, "speed": 28.0, "damage": 7.5, "attack_cd": 0.95,
		"coins": 3, "score": 10, "hit_r": 6.0, "center": 7.0, "knock_res": 0.0, "aggro": 85.0,
		"blood": "#8c1c1c", "desc": "速度慢，数量多", "tip": "手枪和炮塔就能处理",
	},
	"runner": {
		"name": "快跑僵尸", "hp": 18.0, "speed": 64.0, "damage": 5.5, "attack_cd": 0.55,
		"coins": 3, "score": 15, "hit_r": 5.5, "center": 6.0, "knock_res": 0.0, "aggro": 130.0,
		"weak": "冲锋枪", "blood": "#8c1c1c", "desc": "血薄跑得快，老远就盯上你", "tip": "冲锋枪扫，别被围",
	},
	"tank": {
		"name": "坦克僵尸", "hp": 250.0, "speed": 19.0, "damage": 24.0, "attack_cd": 1.25,
		"coins": 14, "score": 60, "hit_r": 11.0, "center": 11.0, "knock_res": 0.85, "aggro": 90.0,
		"weak": "狙击/粘弹/炸药桶", "blood": "#6e1414", "desc": "血厚不吃击退，拆墙伤害翻倍", "tip": "集火，引去炸药桶",
	},
	"exploder": {
		"name": "自爆僵尸", "hp": 27.0, "speed": 40.0, "damage": 44.0, "attack_cd": 1.0,
		"coins": 6, "score": 25, "hit_r": 8.0, "center": 8.0, "knock_res": 0.2, "aggro": 110.0,
		"blood": "#7f9c20", "desc": "碰到东西 0.5 秒后爆炸", "tip": "远距离打死，还能炸到同类",
	},
	"spitter": {
		"name": "喷吐僵尸", "hp": 37.0, "speed": 25.0, "damage": 9.5, "attack_cd": 2.4,
		"coins": 6, "score": 30, "hit_r": 6.0, "center": 7.0, "knock_res": 0.0, "aggro": 150.0,
		"blood": "#4c8a2a", "range": 135.0, "desc": "远程吐酸越过围墙，留下酸液池", "tip": "优先击杀，别站在酸液里",
	},
	"stalker": {
		"name": "潜伏者", "hp": 48.0, "speed": 41.0, "damage": 27.0, "attack_cd": 1.4,
		"coins": 8, "score": 45, "hit_r": 5.5, "center": 8.0, "knock_res": 0.1, "aggro": 260.0,
		"blood": "#4a2a6a", "melee": 0.4, "elite": true,
		"desc": "半透明摸到身边，现身后猛扑一口", "tip": "留意地上的扭曲，一闪红就冲刺躲开",
	},
	"shielder": {
		"name": "护盾兵", "hp": 75.0, "speed": 24.0, "damage": 12.0, "attack_cd": 1.1,
		"coins": 10, "score": 45, "hit_r": 7.0, "center": 9.0, "knock_res": 0.7, "aggro": 120.0,
		"weak": "绕后/爆炸/火焰/电弧/眩晕", "blood": "#8c1c1c", "shield": 70.0, "elite": true,
		"desc": "盾牌挡下正面子弹，盾转得慢", "tip": "绕后，或用爆炸、火焰、电弧、眩晕",
	},
	"splitter": {
		"name": "分裂体", "hp": 84.0, "speed": 26.0, "damage": 10.0, "attack_cd": 1.0,
		"coins": 7, "score": 35, "hit_r": 9.0, "center": 9.0, "knock_res": 0.3, "aggro": 90.0,
		"weak": "榴弹/电弧/火焰", "blood": "#6a9c30", "split": 3, "elite": true,
		"desc": "死后裂成 2~3 只快跑的小怪", "tip": "留一发范围武器收拾小怪",
	},
	"splitling": {
		"name": "分裂小怪", "hp": 14.0, "speed": 54.0, "damage": 4.0, "attack_cd": 0.7,
		"coins": 1, "score": 4, "hit_r": 4.5, "center": 4.0, "knock_res": 0.0, "aggro": 130.0,
		"blood": "#6a9c30", "desc": "分裂体死后的碎块", "tip": "一枪一只",
	},
	"summoner": {
		"name": "召唤者", "hp": 62.0, "speed": 22.0, "damage": 7.0, "attack_cd": 1.2,
		"coins": 12, "score": 60, "hit_r": 6.5, "center": 10.0, "knock_res": 0.1, "aggro": 170.0,
		"weak": "狙击/集火本体", "blood": "#5a2a8a", "elite": true,
		"desc": "躲在远处吟唱，把小鬼叫到你身边", "tip": "直接打它，它一死小鬼全散",
	},
	"imp": {
		"name": "小鬼", "hp": 14.0, "speed": 46.0, "damage": 4.0, "attack_cd": 0.8,
		"coins": 1, "score": 3, "hit_r": 4.5, "center": 5.0, "knock_res": 0.0, "aggro": 170.0,
		"blood": "#5a2a8a", "desc": "召唤者叫来的骷髅", "tip": "看到紫圈就走开",
	},
	"screamer": {
		"name": "尖叫者", "hp": 52.0, "speed": 32.0, "damage": 6.0, "attack_cd": 1.0,
		"coins": 10, "score": 50, "hit_r": 6.0, "center": 9.0, "knock_res": 0.1, "aggro": 150.0,
		"weak": "眩晕/冰冻/集火", "blood": "#8c1c4c", "elite": true,
		"desc": "尖叫让周围僵尸加速冲向你或基地", "tip": "蓄力时发抖，趁机打断或击杀",
	},
	"balloon": {
		"name": "气球僵尸", "hp": 40.0, "speed": 33.0, "damage": 18.0, "attack_cd": 2.6,
		"coins": 9, "score": 40, "hit_r": 9.0, "center": 28.0, "knock_res": 0.0, "aggro": 190.0,
		"weak": "冲锋枪/电弧", "blood": "#8c1c1c", "flying": true, "elite": true,
		"desc": "飘过围墙，在头顶投下毒弹", "tip": "打爆气球会摔下一只半血僵尸",
	},
	"vanguard": {
		"name": "裂颚先锋", "hp": 420.0, "speed": 26.0, "damage": 22.0, "attack_cd": 1.2,
		"coins": 60, "score": 250, "hit_r": 10.0, "center": 11.0, "knock_res": 0.9, "aggro": 140.0,
		"weak": "任意枪/侧闪后还手", "blood": "#7a1818", "is_boss": true,
		"desc": "屠夫的小号，会冲撞和重砸", "tip": "不用换枪，先学会躲开再还手",
	},
	"boss": {
		"name": "屠夫", "hp": 900.0, "speed": 22.0, "damage": 33.0, "attack_cd": 1.3,
		"coins": 140, "score": 600, "hit_r": 15.0, "center": 15.0, "knock_res": 0.96, "aggro": 140.0,
		"weak": "霰弹/闪光弹", "blood": "#6e1414", "is_boss": true,
	},
	"colossus": {
		"name": "覆甲巨像", "hp": 1100.0, "speed": 18.0, "damage": 32.0, "attack_cd": 1.5,
		"coins": 180, "score": 900, "hit_r": 16.0, "center": 16.0, "knock_res": 0.97, "aggro": 140.0,
		"weak": "霰弹/狙击/榴弹/回旋镖/粘弹", "blood": "#5a4a3a", "is_boss": true,
		"desc": "一身厚甲，小口径子弹几乎打不动", "tip": "小伤害无效，换霰弹、狙击、榴弹、回旋镖或粘弹",
	},
	"plague": {
		"name": "瘟疫母体", "hp": 1350.0, "speed": 20.0, "damage": 28.0, "attack_cd": 1.5,
		"coins": 240, "score": 1200, "hit_r": 16.0, "center": 15.0, "knock_res": 0.97, "aggro": 150.0,
		"weak": "榴弹/火焰/电弧", "blood": "#5e8a20", "is_boss": true,
	},
	"graveborn": {
		"name": "再生坟主", "hp": 1500.0, "speed": 19.0, "damage": 30.0, "attack_cd": 1.4,
		"coins": 280, "score": 1400, "hit_r": 15.0, "center": 15.0, "knock_res": 0.97, "aggro": 150.0,
		"weak": "冰冻/火焰", "blood": "#4a5a32", "is_boss": true,
		"desc": "不挂冰也不着火时，每秒都在回血", "tip": "先用冰或火压住再生，再集火",
	},
	"burrowlord": {
		"name": "掘地领主", "hp": 1600.0, "speed": 24.0, "damage": 32.0, "attack_cd": 1.3,
		"coins": 320, "score": 1700, "hit_r": 15.0, "center": 13.0, "knock_res": 0.97, "aggro": 160.0,
		"weak": "榴弹/手雷/火焰/闪光弹", "blood": "#6a4a2a", "is_boss": true,
		"desc": "钻进地下时子弹打不到，出土就是一记重砸", "tip": "往土堆扔爆炸、喷火或闪光，把它逼出来",
	},
	"mirror": {
		"name": "镜面女皇", "hp": 1800.0, "speed": 21.0, "damage": 30.0, "attack_cd": 1.3,
		"coins": 380, "score": 2000, "hit_r": 14.0, "center": 17.0, "knock_res": 0.97, "aggro": 160.0,
		"weak": "绕后/榴弹/电弧/火焰", "blood": "#5a3a6a", "is_boss": true,
		"desc": "身前的镜子把子弹和狙击弹回来", "tip": "绕到背后，或用榴弹、电弧、火焰",
	},
	"overlord": {
		"name": "尸王", "hp": 2700.0, "speed": 23.0, "damage": 36.0, "attack_cd": 1.3,
		"coins": 500, "score": 3000, "hit_r": 18.0, "center": 20.0, "knock_res": 0.98, "aggro": 170.0,
		"weak": "榴弹/火焰/电弧", "blood": "#4a2a6a", "is_boss": true,
	},
}

## Boss 的阶段表。at 是进入该阶段的血量比例，moves 是招式池，enter 是一进阶段就放的招。
## 招式实现见 boss_brain.gd。trophy 可以没有（小 Boss 只掉道具）。
## break 是连冲 charge2 蓄力时能吃的霰弹击退总量（不打 knock_res 的折扣），攒够就被打断并硬直。
## once 里的招式每个阶段只放一次。下面几项是各 Boss 的专属机制，见 boss_brain.gd：
## hit_floor 覆甲阈值（单次伤害低于它只结算 floor_mult，阶段 bare 取消）；
## regen 每秒回复的最大生命比例（挂冰或着火时停）；burrow 钻地秒数范围；reflect 正面反弹子弹。
const BOSSES := {
	"vanguard": {
		"title": "裂颚先锋", "warn": "红色通道是冲撞路线，红圈是重砸，侧向闪开", "drops": ["armor", "ammo_crate"], "slam_scale": 0.9,
		"phases": [
			{"at": 1.0, "name": "裂颚", "sub": "", "speed": 1.0, "gap": [2.4, 3.2], "moves": ["charge", "slam"]},
			{"at": 0.45, "name": "狂奔", "sub": "跑得更快，冲完还会再冲一次", "speed": 1.3, "gap": [1.6, 2.3], "rocks": 2, "tint": "#ffc0a0",
				"enter": "charge", "moves": ["charge2", "rocks"]},
		],
	},
	"boss": {
		"title": "屠夫", "warn": "看到红色通道就侧向闪开", "trophy": "heart", "drops": ["armor", "ammo_crate", "damage"],
		"phases": [
			{"at": 1.0, "name": "屠刀", "sub": "", "speed": 1.0, "gap": [2.2, 3.1], "rocks": 3, "moves": ["charge", "slam", "rocks"]},
			{"at": 0.5, "name": "狂怒", "sub": "连冲蓄力时，用闪光弹或霰弹枪贴脸打断它", "speed": 1.35, "gap": [1.4, 2.1], "rocks": 5, "tint": "#ffa8a0",
				"enter": "call", "call": ["runner", "runner", "exploder"], "break": 300.0, "moves": ["charge2", "slam", "rocks", "call"]},
		],
	},
	"colossus": {
		"title": "覆甲巨像", "warn": "小伤害打在甲上只剩一成，换霰弹、狙击、榴弹或回旋镖", "trophy": "plating",
		"drops": ["sticky", "ammo_crate", "armor"], "shield": 0.16, "slam_scale": 1.2, "hit_floor": 16.0, "floor_mult": 0.1,
		"phases": [
			{"at": 1.0, "name": "外壳", "sub": "", "speed": 1.0, "gap": [2.0, 2.8], "rocks": 3, "moves": ["rocks", "slam", "charge"]},
			{"at": 0.6, "name": "裂甲", "sub": "甲裂开了，先用榴弹、火或电打破护盾", "speed": 1.0, "gap": [1.6, 2.4], "rocks": 3, "tint": "#e0d0c0",
				"enter": "shield", "call": ["tank"], "moves": ["rocks", "slam", "call"]},
			{"at": 0.3, "name": "裸核", "sub": "装甲脱落，什么枪都打得动了", "speed": 1.4, "gap": [1.2, 1.8], "tint": "#ffb090", "bare": true,
				"moves": ["charge2", "wave", "slam"]},
		],
	},
	"plague": {
		"title": "瘟疫母体", "warn": "毒雾会缓慢掉血，离开绿圈", "trophy": "serum", "drops": ["medkit", "inf_ammo", "armor"], "shield": 0.16,
		"phases": [
			# 第 8 波和酸雨同场，第一阶段不放毒雾，免得地上的圈分不清
			{"at": 1.0, "name": "孢子", "sub": "", "speed": 1.0, "gap": [2.0, 3.0], "rocks": 2, "call": ["splitling", "splitling", "spitter"], "moves": ["fan", "call", "rocks"]},
			{"at": 0.55, "name": "脓盾", "sub": "先打破绿色护盾，再打本体", "speed": 0.9, "gap": [1.6, 2.4], "tint": "#d8ffa0",
				"enter": "shield", "call": ["splitter", "spitter", "screamer"], "moves": ["fogring", "fog", "fan", "shield", "call"]},
		],
	},
	"graveborn": {
		"title": "再生坟主", "warn": "不挂冰也不着火时它一直回血，先用冰或火压住", "trophy": "ash",
		"drops": ["ammo_crate", "medkit"], "shield": 0.1, "regen": 0.025,
		"phases": [
			{"at": 1.0, "name": "腐土", "sub": "", "speed": 1.0, "gap": [2.0, 2.8], "rocks": 3, "call": ["walker", "walker", "walker"],
				"moves": ["call", "rocks", "slam"]},
			{"at": 0.55, "name": "冻土·焦土", "sub": "维持冰或火，别让它回血", "speed": 1.0, "gap": [1.5, 2.2], "tint": "#c8e0b0",
				"enter": "shield", "moves": ["fogring", "fan", "shield"]},
			{"at": 0.25, "name": "崩坟", "sub": "再生更快了，冰火别断，一口气打完", "speed": 1.15, "gap": [1.2, 1.8], "tint": "#b0d890", "regen": 0.04,
				"call": ["walker", "walker", "runner"], "moves": ["wave", "storm", "call"]},
		],
	},
	"burrowlord": {
		"title": "掘地领主", "warn": "黄圈和土堆是它在地下，子弹打不到；用爆炸、火或闪光逼它出土", "trophy": "soil",
		"drops": ["frag", "ammo_crate", "armor"], "slam_scale": 1.1, "burrow": [2.5, 4.0],
		"phases": [
			{"at": 1.0, "name": "潜伏", "sub": "", "speed": 1.0, "gap": [2.2, 3.0], "rocks": 2, "moves": ["burrow", "emerge_slam", "rocks"]},
			{"at": 0.6, "name": "地裂", "sub": "冲击波贴地扫来，冲刺能穿过去", "speed": 1.1, "gap": [1.6, 2.3], "tint": "#e8d0a0",
				"moves": ["wave", "storm", "burrow"]},
			{"at": 0.3, "name": "塌方", "sub": "钻地更频繁，还叫来了潜伏者", "speed": 1.2, "gap": [1.2, 1.8], "tint": "#ffc080",
				"enter": "call", "call": ["stalker", "stalker"], "burrow": [1.4, 2.2], "moves": ["burrow", "emerge_slam", "storm"]},
		],
	},
	"mirror": {
		"title": "镜面女皇", "warn": "正面的子弹和狙击会被弹回来，绕后或用榴弹、电弧、火焰", "trophy": "shard",
		"drops": ["armor", "ammo_crate", "frag"], "shield": 0.12, "reflect": true,
		"phases": [
			{"at": 1.0, "name": "镜面", "sub": "", "speed": 1.0, "gap": [1.9, 2.7], "rocks": 4, "moves": ["fan", "rocks", "slam"]},
			{"at": 0.55, "name": "裂镜", "sub": "先清护盾兵，再用爆炸破盾", "speed": 1.0, "gap": [1.5, 2.2], "tint": "#d8d0ff",
				"enter": "shield", "call": ["shielder"], "moves": ["shield", "fog", "call", "wave"]},
			{"at": 0.25, "name": "万镜", "sub": "红环亮起时任何直射都会弹回，只打范围伤害", "speed": 1.1, "gap": [1.2, 1.7], "tint": "#ffb0d0",
				"moves": ["reflect_aura", "fan", "wave"]},
		],
	},
	"overlord": {
		"title": "尸王", "warn": "这是最后一战，它会用尽所有手段", "trophy": "crown", "final": true, "drops": ["nuke", "damage", "armor"], "shield": 0.1, "slam_scale": 1.25,
		"elites": ["stalker", "shielder", "splitter", "summoner", "screamer", "balloon"],
		"phases": [
			# 开局就会张一次薄盾，逼玩家早点掏出榴弹、火和电
			{"at": 1.0, "name": "围城", "sub": "", "speed": 1.0, "gap": [2.0, 3.0], "rocks": 5, "once": ["shield"], "moves": ["charge", "slam", "rocks", "shield"]},
			{"at": 0.75, "name": "亡者号令", "sub": "精英活着时本体大幅减伤，先清精英", "speed": 1.0, "gap": [1.9, 2.8], "rocks": 5, "guard": 0.4, "tint": "#d8c0ff",
				"enter": "elites", "moves": ["elites", "charge", "rocks", "wave"]},
			{"at": 0.5, "name": "瘟疫之息", "sub": "毒雾、护盾和全场尖叫", "speed": 1.1, "gap": [1.6, 2.3], "tint": "#d0ffb0",
				"enter": "shield", "moves": ["fog", "fan", "fogring", "scream", "wave", "shield"]},
			{"at": 0.25, "name": "末日狂暴", "sub": "落石如雨，别停下", "speed": 1.4, "gap": [1.1, 1.8], "rocks": 7, "tint": "#ff9090",
				"enter": "storm", "moves": ["charge2", "storm", "wave", "slam", "elites", "fog"]},
		],
	},
}

## 特殊波的数值：酸雨每隔几秒落几滴。
const ACID_RAIN_GAP := 2.8
const ACID_RAIN_COUNT := 4
const ACID_RAIN_DAMAGE := 12.0
## Boss 在场时酸雨变稀：间隔乘这个倍数，每轮少落一滴。
const ACID_RAIN_BOSS_GAP := 1.5

## 三张地图。布局见 map_layouts.gd（废墟街区在 world_map.gd 里程序生成）。
## coins 开局金币，base_scale 基地受伤系数，group 一批僵尸从同一方向来的数量（越小越容易被包抄），
## group_grow 每隔几波多一只，look_gain 和 look_limit 控制镜头往准星方向看多远，
## count_scale 普通僵尸数量倍率（精英和 Boss 不变），spawn_pace 出怪间隔倍率（越小越密）。
const MAP_ORDER: Array[String] = ["ruins", "parking", "alley"]
const MAPS := {
	"ruins": {
		"name": "废墟街区", "tag": "攻守均衡", "ground": "grass", "tint": "#ffffff", "mini": "#14210f",
		"desc": ["完整的围墙和四条大路，树和废车能挡子弹。", "僵尸一批批从一个方向来，攻守均衡。", "第一次玩选这里。"],
		"coins": 130, "base_scale": 0.31, "count_scale": 1.0, "spawn_pace": 1.0, "group": [3, 5], "group_grow": 2, "look_gain": 0.2, "look_limit": 160.0,
		"preview": {"floor": "#4e7a3c", "road": "#3c3e46", "solid": "#2c3a22", "prop": "#2e5226"},
	},
	"parking": {
		"name": "露天停车场", "tag": "开阔易被包抄 · 尸群更多", "ground": "asphalt", "tint": "#fff4e0", "mini": "#23232a",
		"desc": ["障碍少，视线开阔，镜头能看得更远，枪线通畅。", "只有四角矮墙，僵尸不断换方向，很容易被包抄。", "尸群更多，基地也更不经打，要四面都照顾到。"],
		"coins": 120, "base_scale": 0.53, "count_scale": 1.15, "spawn_pace": 0.85, "group": [1, 2], "group_grow": 6, "look_gain": 0.42, "look_limit": 260.0,
		"preview": {"floor": "#44464e", "road": "#44464e", "solid": "#26262c", "prop": "#a8a498"},
	},
	"alley": {
		"name": "窄巷迷宫", "tag": "狭窄适合卡位 · 开局多 20 金币", "ground": "cobble", "tint": "#dce6ff", "mini": "#191c26",
		"desc": ["楼房夹着两三格宽的巷子，僵尸排成长队来。", "一座炮塔卡住路口就很值，手雷和电弧也打得满。", "但小心被前后堵死，跑之前先看小地图。"],
		"coins": 150, "base_scale": 0.3, "count_scale": 0.88, "spawn_pace": 1.05, "group": [4, 7], "group_grow": 2, "look_gain": 0.2, "look_limit": 160.0,
		"preview": {"floor": "#6a645c", "road": "#6a645c", "solid": "#2a2833", "prop": "#4a7a58"},
	},
}

## 随机事件。slot 为 weather 的持续整波、开打前预警；slot 为 incident 的是波中或波前的一次性事件。
## skip 列出不触发的波次：第 11 波「黑夜降临」不再叠夜战，第 12 波「断电之夜」不再叠电磁干扰。
## 第 8、12 波已有特殊天气，不叠 weather；Boss 波要看清红圈，只可能有补给空投。规则见 event_allowed。
const EVENT_ORDER: Array[String] = ["night", "storm", "fog", "airdrop", "vanguard", "emp"]
const EVENTS := {
	"night": {
		"name": "夜战", "slot": "weather", "color": "#a8b4ff", "min_wave": 3, "skip": [11],
		"sub": "只看得清身边和准星处；僵尸加速，但金币 +25%", "chip": "僵尸快 金币多",
		"zombie_speed": 1.18, "coin_mult": 1.25, "tint": "#c8d0ff",
	},
	"storm": {
		"name": "暴雨", "slot": "weather", "color": "#80c8ff", "min_wave": 2,
		"sub": "都走得慢，水洼打滑，爆炸变小；电弧枪伤害 +35%", "chip": "水洼滑 电弧强",
		"zombie_speed": 0.92, "player_speed": 0.88, "splash": 0.75, "arc": 1.35, "pool_decay": 1.8, "tint": "#c0d4e8",
	},
	"fog": {
		"name": "大雾", "slot": "weather", "color": "#d0d8d8", "min_wave": 3,
		"sub": "看不远，炮塔射程变短；僵尸也更难发现你", "chip": "僵尸难发现你",
		"aggro": 0.65, "turret_range": 0.7, "tint": "#e8ecec",
	},
	"airdrop": {
		"name": "补给空投", "slot": "incident", "color": "#ffe060", "min_wave": 2, "warn_t": 3.0,
		"sub": "运输机飞过，地图边缘有补给箱，限时去捡！", "chip": "去捡补给箱",
	},
	"vanguard": {
		"name": "先遣尸群", "slot": "incident", "color": "#ff9070", "min_wave": 4, "warn_t": 1.5,
		"sub": "有一小撮僵尸提前摸过来了，从%s来，本波总数不变", "chip": "",
	},
	"emp": {
		"name": "电磁干扰", "slot": "incident", "color": "#70e8ff", "min_wave": 4, "warn_t": 3.0,
		"sub": "炮塔和雷达快要失灵了，靠你顶一会儿，恢复后炮塔过载", "chip": "炮塔停火 雷达失灵",
	},
}
const EVENT_WEATHER_CHANCE := 0.4
const EVENT_INCIDENT_CHANCE := 0.55
## 补给箱：落地后能留多久，开箱给多少钱。
const CRATE_LIFE := 25.0
const CRATE_COINS := 35
const CRATE_COINS_PER_WAVE := 7
const CRATE_ITEMS: Array[String] = ["medkit", "armor", "frag", "sticky", "flash", "decoy", "ammo_crate", "inf_ammo", "speed", "damage"]
## 水洼：玩家打滑（加速度倍率），僵尸踩水再慢一点。
const WET_TRACTION := 0.22
const WET_ZOMBIE_SPEED := 0.8
## 电磁干扰：停火多久，之后过载多久、射速倍率。
const EMP_JAM_TIME := 9.0
const EMP_OVERCLOCK_TIME := 5.0
const EMP_OVERCLOCK_RATE := 0.6
## 先遣尸群：从本波队列里提前放多少只，倒计时加长多少秒。
const VANGUARD_COUNT := 6
const VANGUARD_EXTRA_TIME := 3.0

## 手工设计的 15 波节奏：偶数波打 Boss，奇数波是普通波，第 15 波尸王终局；第 8、12 波是特殊波。
## 八道 Boss：裂颚先锋 2、屠夫 4、覆甲巨像 6、瘟疫母体 8（酸雨）、再生坟主 10、掘地领主 12（断电）、镜面女皇 14、尸王 15。
const WAVES := [
	{"name": "先头部队", "walker": 10},
	{"name": "裂颚先锋", "walker": 6, "runner": 2, "vanguard": 1, "hint": "红色通道是冲撞路线，红圈是重砸，看到就侧向闪开"},
	{"name": "毒液来袭", "walker": 12, "runner": 4, "spitter": 3},
	{"name": "屠夫现身", "walker": 6, "runner": 4, "exploder": 1, "boss": 1},
	{"name": "会爆炸的家伙", "walker": 13, "runner": 5, "spitter": 2, "exploder": 4, "splitter": 2},
	{"name": "覆甲巨像", "walker": 8, "runner": 4, "tank": 1, "colossus": 1, "hint": "小伤害几乎打不动它，换成霰弹、狙击、榴弹或回旋镖"},
	{"name": "铁壁", "walker": 14, "runner": 7, "spitter": 3, "tank": 2, "shielder": 3},
	{"name": "瘟疫酸雨", "walker": 12, "runner": 6, "spitter": 4, "exploder": 2, "splitter": 3, "plague": 1, "special": "acid_rain", "hint": "酸雨里瘟疫母体来了：红圈落酸液，绿圈是毒雾"},
	{"name": "火药桶", "walker": 14, "runner": 10, "exploder": 10, "tank": 2, "summoner": 2},
	{"name": "再生坟主", "walker": 12, "runner": 6, "spitter": 2, "exploder": 2, "graveborn": 1, "hint": "先挂上冰或火压住再生，再集火"},
	{"name": "黑夜降临", "walker": 28, "runner": 16, "spitter": 5, "exploder": 6, "tank": 3, "screamer": 3, "balloon": 2},
	{"name": "断电之夜", "walker": 18, "runner": 12, "spitter": 5, "exploder": 5, "tank": 4, "shielder": 4, "stalker": 6, "burrowlord": 1, "special": "blackout",
		"hint": "土堆和黄圈是掘地领主，断电时更难发现——用榴弹、火或闪光逼它出土"},
	{"name": "尸潮", "walker": 38, "runner": 23, "spitter": 6, "exploder": 7, "tank": 4, "splitter": 4, "balloon": 4, "screamer": 2},
	{"name": "镜面女皇", "walker": 14, "runner": 10, "spitter": 4, "exploder": 4, "mirror": 1, "hint": "别正面点射，绕后或用榴弹、电弧、火焰"},
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


## 这把枪能进化成什么，没有返回空串。
func evolution_of(weapon: String) -> String:
	for id: String in EVOLUTIONS.keys():
		if EVOLUTIONS[id]["base"] == weapon:
			return id
	return ""


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
		for i in spawn_count(cfg, kind):
			queue.append(kind)
	queue.shuffle()
	for kind: String in BOSSES.keys():
		for i in int(cfg.get(kind, 0)):
			var at := queue.size() / 2 + i * 12
			queue.insert(mini(at, queue.size()), kind)
	return queue


## 一波里某种杂兵出几只。当前地图的 count_scale 只缩放普通僵尸，精英是逐波设计好的。
func spawn_count(cfg: Dictionary, kind: String) -> int:
	var count := int(cfg.get(kind, 0))
	if not bool(ZOMBIES[kind].get("elite", false)):
		count = roundi(count * float(MAPS[Save.map_id]["count_scale"]))
	return count


## 商店情报：这一波叫什么、提示、有哪些怪（最多 5 项，多的并成「其他」）、Boss 是谁。
## 有弱点标签的怪（精英、坦克）优先列出，普通杂兵按数量补齐。
func wave_preview(wave: int) -> Dictionary:
	var cfg: Dictionary = WAVES[clampi(wave - 1, 0, WAVES.size() - 1)]
	var boss_kind := ""
	var all: Array = []
	for kind: String in ZOMBIES.keys():
		if is_boss(kind):
			if cfg.has(kind):
				boss_kind = kind
			continue
		var n := spawn_count(cfg, kind)
		if n > 0:
			all.append({"id": kind, "name": short_name(kind), "count": n, "weak": String(ZOMBIES[kind].get("weak", ""))})
	var ranked := all.duplicate()
	ranked.sort_custom(func(a, b):
		if (a["weak"] != "") != (b["weak"] != ""):
			return a["weak"] != ""
		return int(a["count"]) > int(b["count"]))
	var kinds: Array = []
	if ranked.size() <= PREVIEW_KINDS:
		kinds = ranked
	else:
		kinds = ranked.slice(0, PREVIEW_KINDS - 1)
		var rest := 0
		for e: Dictionary in ranked.slice(PREVIEW_KINDS - 1):
			rest += int(e["count"])
		kinds.append({"id": "other", "name": "其他", "count": rest, "weak": ""})
	# 显示时按图鉴顺序排，「其他」放最后
	var order: Array = ZOMBIES.keys()
	kinds.sort_custom(func(a, b): return (order.find(a["id"]) if a["id"] != "other" else 999) < (order.find(b["id"]) if b["id"] != "other" else 999))
	return {"name": wave_name(wave), "hint": wave_hint(wave), "kinds": kinds, "boss_kind": boss_kind}


## 情报栏里的短名：去掉「僵尸」后缀，Boss 用称号。
func short_name(kind: String) -> String:
	if BOSSES.has(kind):
		return String(BOSSES[kind]["title"])
	return String(ZOMBIES[kind]["name"]).trim_suffix("僵尸")


func weakness(kind: String) -> String:
	return String(ZOMBIES[kind].get("weak", ""))


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
	return 1.0 + (wave - 1) * 0.04


func speed_scale(wave: int) -> float:
	return 1.0 + (wave - 1) * 0.013


func spawn_interval(wave: int) -> float:
	return maxf(0.58, 1.58 - wave * 0.07) * float(MAPS[Save.map_id]["spawn_pace"])


func wave_bonus(wave: int) -> int:
	return 88 + wave * 29


func boss_wave(wave: int) -> bool:
	var cfg: Dictionary = WAVES[clampi(wave - 1, 0, WAVES.size() - 1)]
	for kind: String in BOSSES.keys():
		if cfg.has(kind):
			return true
	return false


## 这一波能不能触发这个事件，避开和特殊波、Boss 波重复或冲突的组合。
func event_allowed(id: String, wave: int) -> bool:
	var spec: Dictionary = EVENTS[id]
	if wave < int(spec["min_wave"]) or (spec.get("skip", []) as Array).has(wave):
		return false
	if boss_wave(wave):
		return id == "airdrop"
	if wave_special(wave) != "":
		return spec["slot"] != "weather" and id != "emp"
	return true
