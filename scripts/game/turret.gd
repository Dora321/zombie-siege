extends Node2D
## 自动炮塔：占一格，自动打射程内最近的僵尸；可被僵尸摧毁，商店可修。

const MAX_HP_BASE := 160.0

var game: Node
var map: Node2D
var kind := "turret"
var cell := 0
var hp := MAX_HP_BASE
var max_hp := MAX_HP_BASE
var alive := true

var _cooldown := 0.0
var _scan_t := 0.0
var _target: Variant = null
var _flash_t := 0.0
var _kick := 0.0
var _white := false
var _bar_t := 0.0
var _jam_shown := false

@onready var barrel: Sprite2D = $Barrel
@onready var base_sprite: Sprite2D = $Base


func setup(g: Node, m: Node2D, cell_index: int) -> void:
	game = g
	map = m
	cell = cell_index
	position = map.cell_top_left(cell) + Vector2(8, 15)
	base_sprite.texture = Art.turret_base_tex
	base_sprite.offset = Vector2(-8, -13)
	barrel.position = Vector2(0, -9)
	barrel.offset = Vector2(-2, -3)
	map.set_structure(cell, self, map.BLOCK_PLAYER | map.BLOCK_ZOMBIE)
	refresh_level()


func refresh_level() -> void:
	var lvl := int(game.turret_level)
	barrel.texture = Art.turret_barrels[clampi(lvl - 1, 0, Art.turret_barrels.size() - 1)]
	var new_max := MAX_HP_BASE * (1.0 + 0.3 * (lvl - 1))
	hp += new_max - max_hp
	max_hp = new_max


func _range() -> float:
	return (118.0 + 16.0 * (int(game.turret_level) - 1)) * game.events.turret_range


func _physics_process(dt: float) -> void:
	_cooldown -= dt
	_scan_t -= dt
	_flash_t -= dt
	_bar_t -= dt
	_kick = move_toward(_kick, 0.0, dt * 26.0)
	if game.events.jammed():
		_tick_jam()
		return
	if _jam_shown:
		_jam_shown = false
		base_sprite.modulate = Color.WHITE
		_white = false
		queue_redraw()
	if _scan_t <= 0.0:
		_scan_t = 0.2
		_target = _find_target()
	if _target != null and is_instance_valid(_target) and not _target.dead:
		var to: Vector2 = _target.center() - (position + Vector2(0, -9))
		barrel.rotation = lerp_angle(barrel.rotation, to.angle(), clampf(dt * 14.0, 0.0, 1.0))
		if _cooldown <= 0.0 and absf(angle_difference(barrel.rotation, to.angle())) < 0.2:
			_fire(to.normalized())
	barrel.position = Vector2(0, -9) - Vector2.from_angle(barrel.rotation) * _kick
	var flashing := _flash_t > 0.0
	if flashing != _white:
		_white = flashing
		base_sprite.modulate = Color(1.7, 1.5, 1.4) if flashing else Color.WHITE
	if _bar_t > -0.1:
		queue_redraw()


## 电磁干扰：枪管耷拉，机身闪蓝光，不索敌不开火。
func _tick_jam() -> void:
	_jam_shown = true
	_target = null
	queue_redraw()
	barrel.rotation = lerp_angle(barrel.rotation, PI * 0.5, 0.08)
	barrel.position = Vector2(0, -9)
	base_sprite.modulate = Color(0.7, 0.95, 1.6) if Engine.get_physics_frames() % 16 < 8 else Color.WHITE
	if randf() < 0.04:
		game.fx.zap(position + Vector2(randf_range(-6, 6), randf_range(-14, -2)))


func _find_target() -> Variant:
	var best: Variant = null
	var best_d := _range()
	for z: Variant in game.zombies_near(position, _range()):
		if z.dead or z.cloaked():
			continue
		var d: float = position.distance_to(z.position)
		if d < best_d and map.line_clear(position + Vector2(0, -2), z.position, map.BLOCK_BULLET):
			best_d = d
			best = z
	return best


func _fire(dir: Vector2) -> void:
	var lvl := int(game.turret_level)
	_cooldown = 0.32 * pow(0.88, lvl - 1) * game.events.turret_rate()
	var muzzle: Vector2 = position + Vector2(0, -9) + dir * 13.0
	game.bullets.fire(muzzle, dir * 430.0, 10.0 * (1.0 + 0.32 * (lvl - 1)), 26.0, 0.42, 0, Color("#a0f0ff"), false)
	game.fx.muzzle_flash(muzzle, dir, false)
	_kick = 2.0
	Sfx.play("turret", -7.0)


func take_damage(amount: float, _attacker: Variant = null) -> void:
	if not alive:
		return
	hp -= amount
	_flash_t = 0.08
	_bar_t = 1.6
	Sfx.play("wall_hit", -8.0)
	if hp <= 0.0:
		alive = false
		map.clear_structure(cell)
		game.remove_turret(self)
		game.explode(position + Vector2(0, -6), 18.0, 26.0, true)
		queue_free()


func repair_full() -> void:
	hp = max_hp


func _draw() -> void:
	if _bar_t > 0.0:
		draw_rect(Rect2(-7, -22, 14, 2), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(-7, -22, 14.0 * hp / max_hp, 2), Color("#70e090"))
