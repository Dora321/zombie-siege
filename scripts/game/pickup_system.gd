extends Node2D
## 掉落物：金币、弹药箱、医疗包、道具、Boss 战利品。弹一下落地，靠近会被吸过来，波次结束全部飞向玩家。

class Item:
	var pos: Vector2
	var vel: Vector2
	var z: float
	var vz: float
	var kind: String
	var value: int
	var id: String
	var age: float
	var pulled: bool


var game: Node
var items: Array[Item] = []
var magnet_all := false
## 自测场地里关掉掉落，捡到的东西会干扰数量断言。
var enabled := true


func setup(g: Node) -> void:
	game = g


func drop(pos: Vector2, kind: String, value: int, id := "") -> void:
	if not enabled:
		return
	var it := Item.new()
	it.pos = pos
	var a := randf() * TAU
	it.vel = Vector2(cos(a), sin(a)) * randf_range(10, 38)
	it.z = 4.0
	it.vz = randf_range(40, 70)
	it.kind = kind
	it.value = value
	it.id = id
	it.age = randf() * 2.0
	it.pulled = false
	items.append(it)


func _physics_process(dt: float) -> void:
	var player: Variant = game.player
	var i := items.size() - 1
	while i >= 0:
		var it := items[i]
		it.age += dt
		if it.z > 0.0 or it.vz > 0.0:
			it.z += it.vz * dt
			it.vz -= 200.0 * dt
			it.pos += it.vel * dt
			if it.z <= 0.0:
				it.z = 0.0
				it.vz = 0.0
		elif player != null and player.alive:
			var to: Vector2 = player.position + Vector2(0, -4) - it.pos
			var d := to.length()
			var range_now: float = player.magnet_range
			if magnet_all or it.pulled or d < range_now:
				it.pulled = true
				var pull := 70.0 + it.age * 26.0 if not magnet_all else 260.0
				it.pos += to.normalized() * minf(pull * dt * (1.0 + 40.0 / maxf(d, 8.0)), d)
				if d < 7.0:
					_collect(it)
					items[i] = items[items.size() - 1]
					items.pop_back()
		i -= 1
	queue_redraw()


## 通关时立刻结算，地上的战利品不能因为游戏结束就丢了。
func collect_all() -> void:
	for it in items:
		_collect(it)
	items.clear()


func _collect(it: Item) -> void:
	match it.kind:
		"coin":
			game.add_coins(it.value)
			game.fx.coin_text(it.pos + Vector2(0, -6), it.value)
			Sfx.play("coin", -8.0, 0.1)
		"ammo":
			game.grant_ammo_box()
			Sfx.play("reload_done")
		"med":
			game.player.heal(float(it.value))
			game.fx.text(it.pos + Vector2(0, -8), "生命 +%d" % it.value, Color("#ff8080"))
			Sfx.play("buy", -3.0)
		"trophy":
			var spec: Dictionary = GameData.TROPHIES[it.id]
			game.player.apply_trophy(it.id)
			game.fx.text(it.pos + Vector2(0, -8), "%s：%s" % [spec["name"], spec["desc"]], Color("#ffe080"))
			Sfx.play("victory", -6.0)
		"item":
			if game.player.add_item(it.id, it.value):
				game.fx.text(it.pos + Vector2(0, -8), "捡到%s" % GameData.ITEMS[it.id]["name"], Color("#a0e0ff"))
				Sfx.play("buy", -3.0)
			else:
				game.add_coins(GameData.ITEM_OVERFLOW_COINS)
				game.fx.coin_text(it.pos + Vector2(0, -6), GameData.ITEM_OVERFLOW_COINS)
				Sfx.play("coin", -8.0, 0.1)


func _draw() -> void:
	for it in items:
		var at := Vector2(roundf(it.pos.x), roundf(it.pos.y - it.z))
		match it.kind:
			"coin":
				var frames: Array[Texture2D] = Art.coin_big_frames if it.value >= 10 else Art.coin_frames
				var tex: Texture2D = frames[int(it.age * 9.0) % frames.size()]
				draw_texture(tex, at - tex.get_size() * 0.5)
			"ammo":
				draw_texture(Art.ammo_tex, at - Art.ammo_tex.get_size() * 0.5 + Vector2(0, sin(it.age * 5.0)))
			"med":
				draw_texture(Art.medkit_tex, at - Art.medkit_tex.get_size() * 0.5 + Vector2(0, sin(it.age * 5.0)))
			"trophy":
				var tex: Texture2D = Art.trophy_tex[it.id]
				# 战利品带一圈金光，隔着尸堆也能看见
				draw_arc(at, 8.0 + sin(it.age * 6.0), 0.0, TAU, 16, Color(1.0, 0.85, 0.3, 0.8), 1.0)
				draw_texture(tex, at - tex.get_size() * 0.5 + Vector2(0, sin(it.age * 5.0)))
			"item":
				var tex: Texture2D = Art.item_tex[it.id]
				draw_texture(tex, at - tex.get_size() * 0.5 + Vector2(0, sin(it.age * 5.0)))
