extends Node2D
## 可破坏的格子建筑：围墙、路障、炸药桶。摧毁后节点保留（隐藏），方便修复时直接重建。

const BASE_HP := {"wall": 340.0, "barricade": 210.0, "barrel": 18.0}

var game: Node
var map: Node2D
var kind := "wall"
var cell := 0
var hp := 1.0
var max_hp := 1.0
var alive := true

var _front := true
var _bar_t := 0.0
var _flash_t := 0.0
var _tint_flash := false

@onready var sprite: Sprite2D = $Sprite


func setup(g: Node, m: Node2D, piece_kind: String, cell_index: int) -> void:
	game = g
	map = m
	kind = piece_kind
	cell = cell_index
	max_hp = BASE_HP[kind]
	hp = max_hp
	position = map.cell_top_left(cell) + Vector2(8, 16)
	map.set_structure(cell, self, _cell_flags())
	_update_sprite()


func _cell_flags() -> int:
	match kind:
		"wall":
			return map.BLOCK_PLAYER | map.BLOCK_ZOMBIE
		"barricade":
			return map.BLOCK_ZOMBIE
		_:
			return map.BLOCK_ALL


func set_front(front: bool) -> void:
	if _front != front:
		_front = front
		_update_sprite()


func apply_tier(tier: int) -> void:
	var old_ratio := hp / max_hp
	max_hp = float(BASE_HP[kind]) * (1.0 + 0.3 * tier)
	if alive:
		hp = max_hp * old_ratio
		_update_sprite()


func take_damage(amount: float, _attacker: Variant = null) -> void:
	if not alive:
		return
	hp -= amount
	_flash_t = 0.07
	_bar_t = 1.6
	set_physics_process(true)
	queue_redraw()
	if kind == "barrel":
		if hp <= 0.0:
			_die()
		return
	Sfx.play("wall_hit", -7.0)
	if randf() < 0.5:
		game.fx.dust(position + Vector2(randf_range(-6, 6), -randf_range(0, 12)), 2)
	if hp <= 0.0:
		_die()
	else:
		_update_sprite()


func repair(amount: float) -> void:
	if amount <= 0.0:
		return
	hp = minf(hp + amount, max_hp)
	if not alive and hp > 0.0:
		alive = true
		visible = true
		map.set_structure(cell, self, _cell_flags())
	_update_sprite()


func _die() -> void:
	alive = false
	hp = 0.0
	visible = false
	map.clear_structure(cell)
	map.refresh_wall_faces()
	if kind == "barrel":
		game.explode(position + Vector2(0, -4), 60.0, 46.0, true)
		return
	Sfx.play("wall_break", -2.0)
	game.add_shake(0.25)
	game.fx.dust(position + Vector2(0, -6), 12)
	game.fx.debris(position + Vector2(0, -8), kind)
	game.decals.stamp(Art.rubble[randi() % Art.rubble.size()], position + Vector2(0, -8))


func _physics_process(dt: float) -> void:
	_flash_t -= dt
	_bar_t -= dt
	if _flash_t <= 0.0 and not _tint_flash and _bar_t <= 0.0:
		set_physics_process(false)
		queue_redraw()
		return
	var flashing := _flash_t > 0.0
	if flashing != _tint_flash:
		_tint_flash = flashing
		sprite.modulate = Color(1.6, 1.5, 1.4) if flashing else Color.WHITE
	if _bar_t <= 0.0:
		queue_redraw()


func _draw() -> void:
	if _bar_t > 0.0 and alive and kind != "barrel":
		var y := -28.0 if kind == "wall" else -24.0
		draw_rect(Rect2(-7, y, 14, 2), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(-7, y, 14.0 * hp / max_hp, 2), Color("#e0c040"))


func _update_sprite() -> void:
	if sprite == null:
		sprite = $Sprite
	var ratio := hp / max_hp
	var dmg := 0
	if ratio < 0.3:
		dmg = 3
	elif ratio < 0.55:
		dmg = 2
	elif ratio < 0.8:
		dmg = 1
	match kind:
		"wall":
			sprite.texture = Art.walls[_front][dmg]
			sprite.offset = Vector2(-8, -24)
		"barricade":
			sprite.texture = Art.barricades[dmg]
			sprite.offset = Vector2(-8, -20)
		_:
			sprite.texture = Art.barrel_tex
			sprite.offset = Vector2(-7, -16)
