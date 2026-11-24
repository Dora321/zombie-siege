extends RefCounted
## 配件目录和装配数据。用原始武器数值重新计算，便于更换、拆卸和读档。

const SLOT_ORDER: Array[String] = ["muzzle", "mag", "optic"]
const SLOT_NAMES := {"muzzle": "枪口", "mag": "弹匣", "optic": "瞄具"}
const MOD_ORDER := {
	"muzzle": ["compensator", "heavy_barrel", "pierce_choke", "incendiary_tip"],
	"mag": ["ext_mag", "quick_mag", "overcharge_cell", "hollow_point"],
	"optic": ["red_dot", "laser_sight", "tactical_grip", "cryo_core"],
}
const MODS := {
	"compensator": {
		"slot": "muzzle", "name": "制退器", "cost": 70, "color": "#80d8ff",
		"desc": "散布 -45%，后坐力 -35%，压枪极稳",
		"effects": {"spread_mult": 0.55, "recoil_mult": 0.65, "shake_mult": 0.75},
	},
	"heavy_barrel": {
		"slot": "muzzle", "name": "重型枪管", "cost": 95, "color": "#ffb860",
		"desc": "伤害 +20%，弹速与射程 +15%，射速 -8%",
		"effects": {"damage_mult": 1.20, "speed_mult": 1.15, "range_mult": 1.15, "cooldown_mult": 1.08},
	},
	"pierce_choke": {
		"slot": "muzzle", "name": "穿甲收束", "cost": 110, "color": "#ffe870",
		"desc": "穿透 +1，散布 -25%，射程 +12%",
		"effects": {"pierce_add": 1, "spread_mult": 0.75, "range_mult": 1.12},
	},
	"incendiary_tip": {
		"slot": "muzzle", "name": "燃烧枪口", "cost": 120, "color": "#ff7840",
		"desc": "攻击附带燃烧效果，持续灼烧并压制再生",
		"effects": {"burn": true, "damage_mult": 1.06},
	},
	"ext_mag": {
		"slot": "mag", "name": "扩容弹匣", "cost": 75, "color": "#90f090",
		"desc": "弹匣容量 +40%，备弹上限同步提升",
		"effects": {"mag_mult": 1.40},
	},
	"quick_mag": {
		"slot": "mag", "name": "快拔弹匣", "cost": 75, "color": "#78e8d0",
		"desc": "换弹速度加快 32%，切枪更顺畅",
		"effects": {"reload_mult": 0.68},
	},
	"overcharge_cell": {
		"slot": "mag", "name": "过载供弹", "cost": 105, "color": "#c896ff",
		"desc": "射速提升 18%，连射火力全开",
		"effects": {"cooldown_mult": 0.84},
	},
	"hollow_point": {
		"slot": "mag", "name": "空尖弹头", "cost": 115, "color": "#ff6870",
		"desc": "22% 暴击率，暴击造成 1.65 倍伤害",
		"effects": {"crit_chance": 0.22, "crit_mult": 1.65},
	},
	"red_dot": {
		"slot": "optic", "name": "红点瞄具", "cost": 80, "color": "#ff8080",
		"desc": "暴击率 +14%，基础伤害 +10%",
		"effects": {"crit_chance": 0.14, "damage_mult": 1.10},
	},
	"laser_sight": {
		"slot": "optic", "name": "激光瞄准", "cost": 90, "color": "#ff5050",
		"desc": "散布 -35%，射程 +10%，开启战术红激光",
		"effects": {"spread_mult": 0.65, "range_mult": 1.10, "laser": true},
	},
	"tactical_grip": {
		"slot": "optic", "name": "战术握把", "cost": 85, "color": "#a0d8ff",
		"desc": "击退 +35%，后坐力 -40%，控场极强",
		"effects": {"knock_mult": 1.35, "recoil_mult": 0.60},
	},
	"cryo_core": {
		"slot": "optic", "name": "冷媒核心", "cost": 125, "color": "#70ecff",
		"desc": "命中附带寒冰减速，逐步冻结目标",
		"effects": {"chill_add": 0.22},
	},
}

const MULTIPLIED_STATS: Array[String] = [
	"damage", "cooldown", "reload", "spread", "speed", "range", "knock", "recoil", "shake",
]
const DEFAULT_CRIT_MULT := 1.5


static func empty_loadout() -> Dictionary:
	return {"muzzle": "", "mag": "", "optic": ""}


static func sanitize_mods(raw: Variant) -> Dictionary:
	var cleaned := empty_loadout()
	if raw is Dictionary:
		for slot: String in SLOT_ORDER:
			var mod_id: Variant = raw.get(slot)
			if mod_id is String and MODS.get(mod_id, {}).get("slot") == slot:
				cleaned[slot] = mod_id
	return cleaned


static func apply_to_stats(base_stats: Dictionary, equipped: Dictionary) -> Dictionary:
	var stats := base_stats.duplicate(true)
	var returns := bool(stats.get("returns", false))
	var base_speed := float(stats.get("speed", 0.0))
	var base_life := float(stats.get("life", 0.0))
	var uses_lifetime_range := not stats.has("range") and base_speed > 0.0 and base_life > 0.0
	stats["range"] = float(stats.get("range", base_speed * base_life))
	stats["mag"] = maxi(int(stats.get("mag", 1)), 1)
	stats["mod_burn"] = false
	stats["mod_crit_chance"] = 0.0
	stats["mod_crit_mult"] = DEFAULT_CRIT_MULT
	stats["mod_laser"] = false

	var mods := sanitize_mods(equipped)
	for slot: String in SLOT_ORDER:
		var mod_id: String = mods[slot]
		if mod_id.is_empty():
			continue
		var effects: Dictionary = MODS[mod_id]["effects"]
		for stat: String in MULTIPLIED_STATS:
			var key := stat + "_mult"
			if effects.has(key):
				stats[stat] = float(stats.get(stat, 0.0)) * float(effects[key])
		match mod_id:
			"ext_mag":
				var capacity: int = stats["mag"]
				var mult: float = effects["mag_mult"]
				stats["mag"] = capacity + 1 if returns else maxi(roundi(capacity * mult), 1)
				# -1 表示无限备弹，保留该标记。
				if int(stats.get("reserve", -1)) >= 0:
					stats["reserve"] = roundi(float(stats["reserve"]) * mult)
			"quick_mag":
				if returns:
					stats["speed"] = float(stats.get("speed", base_speed)) * 1.15
		if effects.has("pierce_add"):
			stats["pierce"] = int(stats.get("pierce", 0)) + int(effects["pierce_add"])
		if effects.has("chill_add"):
			stats["chill"] = float(stats.get("chill", 0.0)) + float(effects["chill_add"])
		stats["mod_burn"] = bool(stats["mod_burn"]) or bool(effects.get("burn", false))
		stats["mod_laser"] = bool(stats["mod_laser"]) or bool(effects.get("laser", false))
		stats["mod_crit_chance"] = minf(1.0, float(stats["mod_crit_chance"]) + float(effects.get("crit_chance", 0.0)))
		if effects.has("crit_mult"):
			stats["mod_crit_mult"] = float(effects["crit_mult"])

	# 普通弹丸按速度 × 存活时间飞行，分别计算弹速和射程，避免两项加成重复拉长射程。
	if uses_lifetime_range and (float(stats["speed"]) != base_speed or float(stats["range"]) != base_speed * base_life):
		stats["life"] = float(stats["range"]) / float(stats["speed"])
	return stats


static func equipped_colors(equipped: Dictionary) -> Array[Color]:
	var mods := sanitize_mods(equipped)
	var colors: Array[Color] = []
	for slot: String in SLOT_ORDER:
		var spec: Dictionary = MODS.get(mods[slot], {})
		colors.append(Color.TRANSPARENT if spec.is_empty() else Color(String(spec["color"])))
	return colors


static func summary_text(equipped: Dictionary) -> String:
	var mods := sanitize_mods(equipped)
	var names := PackedStringArray()
	for slot: String in SLOT_ORDER:
		if mods[slot] != "":
			names.append(String(MODS[mods[slot]]["name"]))
	return "未装配件" if names.is_empty() else " · ".join(names)


static func mod_cost(mod_id: String, engineer_discount := false) -> int:
	var cost := int(MODS.get(mod_id, {}).get("cost", 0))
	return roundi(cost * 0.85) if engineer_discount else cost


static func mod_sell_refund(mod_id: String) -> int:
	return roundi(mod_cost(mod_id) * 0.50)


static func compatible_mods(_weapon_id: String, slot: String) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(MOD_ORDER.get(slot, []))
	return ids


## 掉落率由调用方决定。命中后等概率抽取一种配件，空串表示没有掉落。
static func roll_drop(chance: float, rng: RandomNumberGenerator = null) -> String:
	if chance <= 0.0:
		return ""
	var roll := rng.randf() if rng != null else randf()
	if chance < 1.0 and roll >= chance:
		return ""
	var ids := MODS.keys()
	var index := rng.randi_range(0, ids.size() - 1) if rng != null else randi_range(0, ids.size() - 1)
	return String(ids[index])
