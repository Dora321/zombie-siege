extends RefCounted
## 商店商品表：UI 只管显示，买东西的规则都在这里，测试也走同一套逻辑。

const TABS: Array[String] = ["武器", "弹药", "防御", "补给", "道具"]
const TAB_WEAPON := 0
const TAB_AMMO := 1
const TAB_DEFENSE := 2
const TAB_SUPPLY := 3
const TAB_ITEM := 4
const MAX_TURRETS := 8
const MAX_TURRET_LEVEL := 4
const MAX_WALL_TIER := 4
const TURRET_COST_STEP := 50


static func turret_cost(g: Node) -> int:
	return 110 + g.turrets.size() * TURRET_COST_STEP


static func _scaled_turret_cost(g: Node, kind: String, base_cost: int) -> int:
	var spec: Dictionary = GameData.TURRET_TYPES[kind]
	var discount := 0.75 if g.get("hero_id") == "engineer" else 1.0
	return roundi(base_cost * float(spec["cost_mult"]) * discount)


static func _turret_refund(g: Node) -> int:
	if g.has_method("last_turret_refund"):
		return g.last_turret_refund()
	if g.turrets.is_empty():
		return 0
	var t: Variant = g.turrets.back()
	var kind: String = t.turret_type if "turret_type" in t else "mg"
	return floori(_scaled_turret_cost(g, kind, turret_cost(g) - TURRET_COST_STEP) * 0.6)


static func items(g: Node) -> Array:
	var p: Variant = g.player
	var out: Array = []
	var no_smg: bool = g.has_contract("no_smg")
	# 武器：解锁要枪袋有空位；已解锁的可以卸下或装备（swap 是行里的第二个按钮），没带的枪照样能升级
	for id: String in GameData.WEAPON_ORDER:
		var state: Dictionary = p.weapon_state[id]
		var spec: Dictionary = GameData.WEAPONS[id]
		var level: int = state["level"]
		var maxed := level >= GameData.MAX_WEAPON_LEVEL
		var key := GameData.WEAPON_ORDER.find(id) + 1
		# 自带的三把枪没有 desc（只有禁冲锋枪契约下冲锋枪才会是 0 级）
		var desc := String(spec.get("desc", spec["hint"])) if level == 0 else ("已满级" if maxed else String(spec["hint"]))
		var bag_full: bool = level == 0 and p.loadout_full()
		if bag_full:
			desc = "枪袋已满，先卸下一把或扩容枪袋"
		elif level > 0 and not p.carries(id):
			desc = "没带在身上 · " + desc
		var item := {
			"id": "up_" + id, "tab": TAB_WEAPON,
			"name": "[%d] 解锁%s" % [key, spec["name"]] if level == 0 else "[%d] %s Lv%d" % [key, p.weapon_name(id), level],
			"desc": desc,
			"cost": 0 if maxed else GameData.upgrade_cost(id, level),
			"locked": maxed or bag_full,
		}
		# 满级后这一行变成进化：条件够了花一点钱原地进化，不够就写还差什么
		var evo := GameData.evolution_of(id)
		var banned := id == "smg" and no_smg
		if maxed and evo != "" and not banned:
			var spec_evo: Dictionary = GameData.EVOLUTIONS[evo]
			if p.evolution(id) != "":
				item["desc"] = "已进化 · " + String(spec_evo["desc"])
				item["locked_text"] = "已进化"
			else:
				var check: Dictionary = p.evolve_check(id)
				item["id"] = "evo_" + id
				item["cost"] = GameData.EVOLVE_COST
				item["locked"] = not bool(check["ok"])
				item["button"] = "进化 %d" % GameData.EVOLVE_COST
				if bool(check["ok"]):
					item["desc"] = "进化成%s：%s" % [spec_evo["name"], spec_evo["desc"]]
				else:
					item["desc"] = "进化%s%s" % [spec_evo["name"], check["reason"]]
			if not p.carries(id):
				item["desc"] = "没带在身上 · " + String(item["desc"])
		# 禁冲锋枪契约：冲锋枪这一行整行禁用
		if banned:
			item["locked"] = true
			item["desc"] = "契约：本局禁用冲锋枪"
			item["locked_text"] = "禁用"
		elif level > 0 and id != "pistol":
			if p.carries(id):
				item["swap"] = {"id": "unequip_" + id, "text": "卸下", "ok": p.can_unequip(id)}
			else:
				item["swap"] = {"id": "equip_" + id, "text": "装备", "ok": not p.loadout_full()}
		out.append(item)
	# 弹药：只列已解锁且需要备弹的枪
	for id: String in p.owned_weapons():
		if id == "smg" and no_smg:
			continue
		var spec: Dictionary = GameData.WEAPONS[id]
		if not spec.has("ammo_pack"):
			continue
		out.append({
			"id": "ammo_" + id, "tab": TAB_AMMO,
			"name": "%s +%d" % [spec["name"], spec["ammo_pack"]],
			"desc": "备弹 %d" % p.weapon_state[id]["reserve"],
			"cost": spec["ammo_cost"], "locked": false,
		})
	# 防御
	var repair_cost := _repair_full_cost(g)
	out.append({
		"id": "repair", "tab": TAB_DEFENSE, "name": "修复围墙路障",
		"desc": "无需修理" if repair_cost == 0 else "钱不够时按比例修",
		"cost": repair_cost, "locked": repair_cost == 0, "partial": true,
	})
	var tier: int = g.map.wall_tier
	out.append({
		"id": "reinforce", "tab": TAB_DEFENSE, "name": "加固围墙 Lv%d" % (tier + 1),
		"desc": "已满级" if tier >= MAX_WALL_TIER else "围墙耐久 +30%",
		"cost": 0 if tier >= MAX_WALL_TIER else 100 * (tier + 1), "locked": tier >= MAX_WALL_TIER,
	})
	var base_missing: float = g.base.max_hp - g.base.hp
	out.append({
		"id": "base_repair", "tab": TAB_DEFENSE, "name": "抢修基地 +150",
		"desc": "基地 %d/%d" % [roundi(g.base.hp), roundi(g.base.max_hp)],
		"cost": 75, "locked": base_missing < 1.0,
	})
	var max_turrets := int(g.turret_max_count()) if g.has_method("turret_max_count") else MAX_TURRETS
	var turret_count: int = g.turrets.size()
	var maxed_turrets := turret_count >= max_turrets
	var no_turret: bool = g.has_contract("no_turret")
	var base_cost := turret_cost(g)
	for kind: String in GameData.TURRET_ORDER:
		# 旧的放置流程只会造机枪炮塔。
		if kind != "mg" and not ("placing_turret_kind" in g):
			continue
		var spec: Dictionary = GameData.TURRET_TYPES[kind]
		var cost := int(g.turret_cost_for(kind)) if g.has_method("turret_cost_for") else _scaled_turret_cost(g, kind, base_cost)
		out.append({
			"id": "turret" if kind == "mg" else "turret_" + kind, "tab": TAB_DEFENSE,
			"name": "%s %d/%d" % [spec["name"], turret_count, max_turrets],
			"desc": "契约：本局不能放炮塔" if no_turret else ("已达上限" if maxed_turrets else String(spec["desc"])),
			"cost": 0 if maxed_turrets else cost, "locked": no_turret or maxed_turrets,
			"locked_text": "禁用" if no_turret else "--", "turret_kind": kind,
		})
	if turret_count > 0 and not no_turret:
		var refund := _turret_refund(g)
		out.append({
			"id": "turret_sell", "tab": TAB_DEFENSE, "name": "拆除最新炮塔",
			"desc": "+%d 金币" % refund, "cost": 0, "locked": false, "button": "拆除 +%d" % refund,
		})
	var tlvl: int = g.turret_level
	out.append({
		"id": "turret_up", "tab": TAB_DEFENSE, "name": "升级炮塔 Lv%d" % tlvl,
		"desc": "契约：本局不能放炮塔" if no_turret else ("已满级" if tlvl >= MAX_TURRET_LEVEL else "伤害射速射程提升"),
		"cost": 0 if tlvl >= MAX_TURRET_LEVEL else 140 * tlvl,
		"locked": no_turret or tlvl >= MAX_TURRET_LEVEL, "locked_text": "禁用" if no_turret else "--",
	})
	# 补给
	out.append({
		"id": "heal", "tab": TAB_SUPPLY, "name": "急救包 +50",
		"desc": "生命 %d/%d" % [roundi(p.hp), roundi(p.max_hp)],
		"cost": 45, "locked": p.hp >= p.max_hp,
	})
	var hp_ups: int = g.purchases.get("max_hp", 0)
	out.append({
		"id": "max_hp", "tab": TAB_SUPPLY, "name": "防弹衣 Lv%d" % hp_ups,
		"desc": "已满级" if hp_ups >= 4 else "生命上限 +25",
		"cost": 0 if hp_ups >= 4 else 80 * (hp_ups + 1), "locked": hp_ups >= 4,
	})
	var boots: int = g.purchases.get("boots", 0)
	out.append({
		"id": "boots", "tab": TAB_SUPPLY, "name": "跑鞋 Lv%d" % boots,
		"desc": "已满级" if boots >= 3 else "移速 +8%",
		"cost": 0 if boots >= 3 else 70 * (boots + 1), "locked": boots >= 3,
	})
	var dash: int = g.purchases.get("dash", 0)
	out.append({
		"id": "dash", "tab": TAB_SUPPLY, "name": "冲刺训练 Lv%d" % dash,
		"desc": "已满级" if dash >= 3 else "冲刺冷却 -20%",
		"cost": 0 if dash >= 3 else 70 * (dash + 1), "locked": dash >= 3,
	})
	var slots: int = p.weapon_slots
	out.append({
		"id": "slots", "tab": TAB_SUPPLY, "name": "扩容枪袋 %d/%d" % [slots, GameData.MAX_WEAPON_SLOTS],
		"desc": "已扩容" if slots >= GameData.MAX_WEAPON_SLOTS else "随身多带一把枪",
		"cost": 0 if slots >= GameData.MAX_WEAPON_SLOTS else GameData.SLOT_COST, "locked": slots >= GameData.MAX_WEAPON_SLOTS,
	})
	var magnet: int = g.purchases.get("magnet", 0)
	out.append({
		"id": "magnet", "tab": TAB_SUPPLY, "name": "磁铁 Lv%d" % magnet,
		"desc": "已满级" if magnet >= 3 else "拾取范围 +40%",
		"cost": 0 if magnet >= 3 else 50 * (magnet + 1), "locked": magnet >= 3,
	})
	# 道具：带进战斗，用快捷键使用
	for id: String in GameData.ITEM_ORDER:
		var spec: Dictionary = GameData.ITEMS[id]
		var count: int = p.items[id]
		var pack: int = spec["pack"]
		out.append({
			"id": "item_" + id, "tab": TAB_ITEM,
			"name": "%s%s %d/%d" % [spec["name"], "x%d" % pack if pack > 1 else "", count, spec["max"]],
			"desc": "已带满" if count >= int(spec["max"]) else String(spec["desc"]),
			"cost": spec["cost"], "locked": count >= int(spec["max"]),
		})
	return out


static func _repair_full_cost(g: Node) -> int:
	var missing: float = g.map.missing_wall_hp()
	var rate := 0.18 if g.get("hero_id") == "engineer" else 0.3
	return ceili(missing * rate) if missing >= 1.0 else 0


static func can_buy(g: Node, item: Dictionary) -> bool:
	if bool(item["locked"]):
		return false
	if bool(item.get("partial", false)):
		return g.coins > 0
	return g.coins >= int(item["cost"])


## 购买：成功返回 true。放炮塔不在这里扣钱，落地时才扣。装备和卸下不花钱。
static func buy(g: Node, id: String) -> bool:
	if id.begins_with("equip_"):
		var weapon := id.trim_prefix("equip_")
		return not (weapon == "smg" and g.has_contract("no_smg")) and g.player.equip(weapon)
	if id.begins_with("unequip_"):
		return g.player.unequip(id.trim_prefix("unequip_"))
	var item: Dictionary = {}
	for it: Dictionary in items(g):
		if it["id"] == id:
			item = it
	if item.is_empty() or not can_buy(g, item):
		return false
	if item.has("turret_kind"):
		if "placing_turret_kind" in g:
			g.placing_turret_kind = String(item["turret_kind"])
		g.begin_turret_placement()
		return true
	var cost: int = item["cost"]
	var p: Variant = g.player
	if id.begins_with("up_"):
		p.upgrade_weapon(id.trim_prefix("up_"))
	elif id.begins_with("evo_"):
		if not p.try_evolve(id.trim_prefix("evo_")):
			return false
	elif id.begins_with("ammo_"):
		var weapon := id.trim_prefix("ammo_")
		p.weapon_state[weapon]["reserve"] += int(GameData.WEAPONS[weapon]["ammo_pack"])
	elif id.begins_with("item_"):
		var item_id := id.trim_prefix("item_")
		p.add_item(item_id, int(GameData.ITEMS[item_id]["pack"]))
	else:
		match id:
			"repair":
				var ratio := minf(1.0, float(g.coins) / maxf(float(cost), 1.0))
				cost = mini(cost, g.coins)
				g.map.repair_walls(ratio)
				g.after_repair()
			"reinforce":
				g.map.raise_wall_tier()
			"base_repair":
				g.base.heal(150.0)
			"turret_sell":
				if g.has_method("sell_last_turret"):
					return g.sell_last_turret()
				var refund := _turret_refund(g)
				var t: Variant = g.turrets.pop_back()
				g.map.clear_structure(t.cell)
				t.alive = false
				t.set_physics_process(false)
				t.queue_free()
				g.coins += refund
				return true
			"turret_up":
				g.turret_level += 1
				for t: Variant in g.turrets:
					t.refresh_level()
			"heal":
				p.heal(50.0)
			"max_hp":
				g.purchases["max_hp"] = int(g.purchases.get("max_hp", 0)) + 1
				p.max_hp += 25.0
				p.hp += 25.0
			"boots":
				g.purchases["boots"] = int(g.purchases.get("boots", 0)) + 1
				p.speed_mult += 0.08
			"dash":
				g.purchases["dash"] = int(g.purchases.get("dash", 0)) + 1
				p.dash_cd_base *= 0.8
			"magnet":
				g.purchases["magnet"] = int(g.purchases.get("magnet", 0)) + 1
				p.magnet_range *= 1.4
			"slots":
				p.weapon_slots += 1
			_:
				return false
	g.spend_coins(cost)
	return true
