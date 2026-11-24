extends Node
## 启动时按屏幕大小选一个合适的整数倍窗口；F11 或 F 切换全屏。
## 网页版的画布由导出模板铺满浏览器窗口，这里只把整数缩放改成按比例缩放，少留黑边。

const BASE := Vector2i(480, 270)
const WIDE_RATIO := Vector2i(13, 6)
const WIDE_SCALE := 90


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var window := get_window()
	if Mobile.is_mobile():
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
		return
	if OS.has_feature("web"):
		window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
		return
	if DisplayServer.get_name() == "headless":
		return
	if Mobile.use_expanded_viewport():
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	_fit_window.call_deferred()


func _fit_window() -> void:
	var usable := DisplayServer.screen_get_usable_rect()
	var window := get_window()
	if Mobile.wide_preview:
		var fit := mini(usable.size.x / WIDE_RATIO.x, usable.size.y / WIDE_RATIO.y)
		window.size = WIDE_RATIO * clampi(fit, 1, WIDE_SCALE)
	else:
		var fit := mini(usable.size.x / BASE.x, usable.size.y / BASE.y)
		# 不占满整个屏幕，留一圈边
		var scale := maxi(1, fit - 1 if fit >= 3 else fit)
		window.size = BASE * scale
	window.position = usable.position + (usable.size - window.size) / 2


func _unhandled_input(event: InputEvent) -> void:
	if not Mobile.is_mobile() and event.is_action_pressed("fullscreen") and not event.is_echo():
		var window := get_window()
		if window.mode == Window.MODE_FULLSCREEN:
			window.mode = Window.MODE_WINDOWED
		else:
			window.mode = Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
