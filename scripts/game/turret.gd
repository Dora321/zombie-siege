extends Node2D
## 炮塔占一格，按兵种自动索敌；可被僵尸摧毁，商店可修。

const MAX_HP_BASE := 160.0
const BARREL_TINTS := {
	"mg": Color.WHITE, "frost": Color("#80e8ff"),
	"mortar": Color("#ffb868"), "tesla": Color("#d09cff"),
}
const NOVA_STUN_RADIUS := 72.0

## 复用榴弹弹道和落地特效，伤害只结算给僵尸。炮塔被摧毁后，已发射的炮弹继续飞行。
class MortarImpact extends Node:
	var game: Node
	var shell: Variant
	var damage: float

	func _physics_process(_dt: float) -> void:
		if shell.t >= shell.dur:
			var pos: Vector2 = shell.to
			var radius: float = shell.radius * game.events.splash_mult
			for z: Variant in game.zombies_near(pos, radius + 12.0):
				if z.dead:
					continue
				var at: Vector2 = z.center()
				var distance := pos.distance_to(at)
				if distance < radius + float(z.hit_r):
					var falloff := 1.0 - clampf(distance / (radius + 12.0), 0.0, 0.7)
					var hit := damage * falloff * 2.2
					z.shield_hit(hit)
					z.take_damage(hit, pos.direction_to(at), 160.0, true, "blast")
			queue_free()
		elif not game.ordnance.lobs.has(shell):
			# 波次结束时一并清除还未落地的炮弹。
			queue_free()

var game: Node
var map: Node2D
var kind := "turret"
var turret_type := "mg"
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


func setup(g: Node, m: Node2D, cell_index: int, t_type := "") -> void:
	game = g
	map = m
	cell = cell_index
	if t_type != "" and GameData.TURRET_TYPES.has(t_type):
		turret_type = t_type
	elif not GameData.TURRET_TYPES.has(turret_type):
		turret_type = "mg"
	position = map.cell_top_left(cell) + Vector2(8, 15)
	base_sprite.texture = Art.turret_base_tex
	base_sprite.offset = Vector2(-8, -13)
	base_sprite.show_behind_parent = true
	barrel.position = Vector2(0, -9)
	barrel.offset = Vector2(-2, -3)
	barrel.modulate = BARREL_TINTS[turret_type]
	barrel.show_behind_parent = true
	map.set_structure(cell, self, map.BLOCK_PLAYER | map.BLOCK_ZOMBIE)
	refresh_level()
	queue_redraw()


func refresh_level() -> void:
	var lvl := int(game.turret_level)
	barrel.texture = Art.turret_barrels[clampi(lvl - 1, 0, Art.turret_barrels.size() - 1)]
	var new_max := MAX_HP_BASE * (1.0 + 0.3 * (lvl - 1))
	hp += new_max - max_hp
	max_hp = new_max


func _range() -> float:
	var spec: Dictionary = GameData.TURRET_TYPES[turret_type]
	return (float(spec["range_base"]) + float(spec["range_step"]) * (int(game.turret_level) - 1)) * game.events.turret_range


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
	if is_instance_valid(_target) and not _target.dead and (turret_type == "mortar" or not _target.burrowed):
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
	var best_score := INF
	var reach := _range()
	var mortar := turret_type == "mortar"
	for z: Variant in game.zombies_near(position, reach):
		if z.dead or ((z.burrowed or z.cloaked()) and not (mortar and z.burrowed)):
			continue
		var d: float = position.distance_to(z.position)
		var score := d + (16.0 if turret_type == "frost" and z._frozen_t > 0.0 else 0.0)
		if d < reach and score < best_score and (mortar or map.line_clear(position + Vector2(0, -2), z.position, map.BLOCK_BULLET)):
			best_score = score
			best = z
	return best


func _fire(dir: Vector2) -> void:
	var lvl := int(game.turret_level)
	var sync_mult := 0.78 if (game.has_method("has_perk") and game.has_perk("turret_sync") and game.player != null and float(game.player.fired_kick) > 0.05) else 1.0
	var rate: float = game.events.turret_rate() * sync_mult
	var muzzle: Vector2 = position + Vector2(0, -9) + dir * 13.0
	match turret_type:
		"frost":
			_cooldown = 0.42 * pow(0.89, lvl - 1) * rate
			var b: Variant = game.bullets.fire(muzzle, dir * 430.0, 6.5 * (1.0 + 0.28 * (lvl - 1)), 26.0, 0.42, 0, Color("#80f0ff"), false)
			b.chill = 0.42 + 0.06 * (lvl - 1)
			Sfx.play("cryo", -8.0)
		"mortar":
			_cooldown = 1.65 * pow(0.9, lvl - 1) * rate
			game.ordnance.lob("grenade", muzzle, _target.position, 0.0, 34.0 + 4.0 * (lvl - 1))
			var impact := MortarImpact.new()
			impact.game = game
			impact.shell = game.ordnance.lobs.back()
			impact.damage = 22.0 * (1.0 + 0.35 * (lvl - 1))
			game.ordnance.add_child(impact)
			Sfx.play("launcher", -6.0)
		"tesla":
			_cooldown = 0.78 * pow(0.88, lvl - 1) * rate
			game.ordnance.arc(muzzle, dir, _range(), 14.0 * (1.0 + 0.32 * (lvl - 1)), 2 + lvl, 60.0, 10.0, false)
			Sfx.play("arc", -7.0)
		_:
			_cooldown = 0.32 * pow(0.88, lvl - 1) * rate
			game.bullets.fire(muzzle, dir * 430.0, 10.0 * (1.0 + 0.32 * (lvl - 1)), 26.0, 0.42, 0, Color("#a0f0ff"), false)
			Sfx.play("turret", -7.0)
	game.fx.muzzle_flash(muzzle, dir, false)
	_kick = 2.0


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
		var blast_pos := position + Vector2(0, -6)
		if game.has_method("has_perk") and game.has_perk("turret_nova"):
			game.explode(blast_pos, 72.0, 52.0, true)
			game.fx.ring(blast_pos, NOVA_STUN_RADIUS, 0.3, Color.WHITE)
			for z: Variant in game.zombies_near(blast_pos, NOVA_STUN_RADIUS + 12.0):
				if not z.dead and blast_pos.distance_squared_to(z.center()) <= NOVA_STUN_RADIUS * NOVA_STUN_RADIUS:
					z.stun(2.2)
		else:
			game.explode(blast_pos, 18.0, 26.0, true)
		queue_free()


func repair_full() -> void:
	hp = max_hp


func _draw() -> void:
	var spec: Dictionary = GameData.TURRET_TYPES[turret_type]
	draw_rect(Rect2(-2, -5, 4, 2), Color(spec["color"]))
	if _bar_t > 0.0:
		draw_rect(Rect2(-7, -22, 14, 2), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(-7, -22, 14.0 * hp / max_hp, 2), Color("#70e090"))
