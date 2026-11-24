extends Node
## 移动端 / 触控适配总控：平台检测、安全区换算、双摇杆与触屏按钮共享输入状态。

var _forced_touch: Variant = null
var wide_preview := false
var _safe_override: Variant = null

## 实时双摇杆与开火状态（由 TouchControls 写入，Player / Game / HUD 读取）
var move_vec := Vector2.ZERO
var aim_vec := Vector2.ZERO
var aiming := false
var firing := false

## 单次触发动作锁存（由 TouchControls / HUD 写入，Player 消费）
var latch_dash := false
var latch_reload := false
var latch_weapon_id := ""
var latch_weapon_step := 0
var latch_item_use := ""
var latch_item_select := ""
var latch_item_next := false

## 炮塔触控放置状态（State.PLACING 时由 TouchControls 写入，Game / HUD 读取）
var place_active := false
var place_world_pos := Vector2.ZERO
var place_has_target := false
var place_confirm := false
var place_cancel := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args()


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--touch":
			_forced_touch = true
		elif arg == "--notouch":
			_forced_touch = false
		elif arg == "--wide":
			wide_preview = true
		elif arg.begins_with("--safe-area="):
			var parts := arg.substr(12).split(",")
			if parts.size() == 4:
				_safe_override = {
					"left": float(parts[0]),
					"top": float(parts[1]),
					"right": float(parts[2]),
					"bottom": float(parts[3]),
				}


func is_ios() -> bool:
	return OS.has_feature("ios")


func is_mobile() -> bool:
	return OS.has_feature("ios") or OS.has_feature("android") or OS.has_feature("mobile")


func is_touch() -> bool:
	if _forced_touch != null:
		return bool(_forced_touch)
	return is_mobile() or DisplayServer.is_touchscreen_available()


func use_expanded_viewport() -> bool:
	return is_mobile() or wide_preview or (_forced_touch == true)


func set_forced_touch(value: Variant) -> void:
	_forced_touch = value
	if not is_touch():
		clear_controls()


## 返回当前视口逻辑像素下的安全区边距（left / top / right / bottom），避开灵动岛与底部横条。
func safe_insets(viewport: Viewport) -> Dictionary:
	if _safe_override is Dictionary:
		return (_safe_override as Dictionary).duplicate()
	if not is_mobile() or viewport == null or DisplayServer.get_name() == "headless":
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var screen_size := Vector2(DisplayServer.screen_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if screen_size.x <= 0.0 or screen_size.y <= 0.0 or safe.size.x <= 0 or safe.size.y <= 0:
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var vp_size := viewport.get_visible_rect().size
	var sx := vp_size.x / screen_size.x
	var sy := vp_size.y / screen_size.y
	var left := maxf(0.0, float(safe.position.x) * sx)
	var top := maxf(0.0, float(safe.position.y) * sy)
	var right := maxf(0.0, (screen_size.x - float(safe.end.x)) * sx)
	var bottom := maxf(0.0, (screen_size.y - float(safe.end.y)) * sy)
	return {"left": left, "top": top, "right": right, "bottom": bottom}


func clear_controls() -> void:
	move_vec = Vector2.ZERO
	aim_vec = Vector2.ZERO
	aiming = false
	firing = false
	latch_dash = false
	latch_reload = false
	latch_weapon_id = ""
	latch_weapon_step = 0
	latch_item_use = ""
	latch_item_select = ""
	latch_item_next = false
	place_confirm = false
	place_cancel = false


func reset_placement(world_pos := Vector2.ZERO, active := false) -> void:
	place_active = active
	place_world_pos = world_pos
	place_has_target = active
	place_confirm = false
	place_cancel = false


func trigger_haptic(duration_ms := 18, amplitude := 0.45) -> void:
	if not is_mobile() or not Save.shake_on:
		return
	if DisplayServer.get_name() == "headless":
		return
	Input.vibrate_handheld(duration_ms, amplitude)
