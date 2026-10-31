extends Node
## 启动时按屏幕大小选一个合适的整数倍窗口；F11 或 F 切换全屏。
## 网页版的画布由导出模板铺满浏览器窗口，这里只把整数缩放改成按比例缩放，少留黑边。

const BASE := Vector2i(480, 270)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		get_window().content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
		return
	if DisplayServer.get_name() == "headless":
		return
	_fit_window.call_deferred()


func _fit_window() -> void:
	var usable := DisplayServer.screen_get_usable_rect()
	var fit := mini(usable.size.x / BASE.x, usable.size.y / BASE.y)
	# 不占满整个屏幕，留一圈边
	var scale := maxi(1, fit - 1 if fit >= 3 else fit)
	var window := get_window()
	window.size = BASE * scale
	window.position = usable.position + (usable.size - window.size) / 2


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen") and not event.is_echo():
		var window := get_window()
		if window.mode == Window.MODE_FULLSCREEN:
			window.mode = Window.MODE_WINDOWED
		else:
			window.mode = Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
