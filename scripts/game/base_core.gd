extends Node2D
## 中央基地：占 4x3 格，被摧毁即失败。

const MAX_HP := 600.0

var game: Node
var kind := "base"
var hp := MAX_HP
var max_hp := MAX_HP
var alive := true

var _anim_t := 0.0
var _flash_t := 0.0
var _smoke_t := 0.0
var _bar_t := 0.0
var _stage := -1
var _white := false

@onready var body: Sprite2D = $Body
@onready var flag: Sprite2D = $Flag
@onready var radar: Sprite2D = $Radar


func setup(g: Node, map: Node2D) -> void:
	game = g
	position = Vector2((map.BASE_X0 + map.BASE_X1 + 1) * map.TILE * 0.5, (map.BASE_Y1 + 1) * map.TILE)
	for i: int in map.base_cells:
		map.structures[i] = self
	_update_stage()


func take_damage(amount: float, _attacker: Variant = null) -> void:
	if not alive:
		return
	hp -= amount * game.base_damage_scale
	_flash_t = 0.08
	_bar_t = 2.0
	game.on_base_hurt(amount)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		game.on_base_destroyed()
	_update_stage()


func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)
	_update_stage()


func _update_stage() -> void:
	var ratio := hp / max_hp
	var stage := 0
	if ratio < 0.25:
		stage = 3
	elif ratio < 0.5:
		stage = 2
	elif ratio < 0.75:
		stage = 1
	if stage != _stage:
		_stage = stage
		body.texture = Art.base_tex[stage]


func _physics_process(dt: float) -> void:
	_anim_t += dt
	_flash_t -= dt
	_bar_t -= dt
	flag.texture = Art.flag_frames[int(_anim_t * 7.0) % Art.flag_frames.size()]
	radar.texture = Art.radar_frames[int(_anim_t * 5.0) % Art.radar_frames.size()]
	var flashing := _flash_t > 0.0
	if flashing != _white:
		_white = flashing
		body.modulate = Color(1.7, 1.45, 1.4) if flashing else Color.WHITE
	# 血量越低冒烟越凶
	if hp < max_hp * 0.6:
		_smoke_t -= dt
		if _smoke_t <= 0.0:
			_smoke_t = 0.14 + (hp / max_hp) * 0.5
			var at := position + Vector2(randf_range(-26, 26), randf_range(-58, -40))
			game.fx.smoke(at, hp < max_hp * 0.3)
	queue_redraw()


func _draw() -> void:
	if _bar_t > 0.0:
		draw_rect(Rect2(-24, -76, 48, 3), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(-24, -76, 48.0 * hp / max_hp, 3), Color("#5a90d0"))
