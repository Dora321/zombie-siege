extends Node2D
## 贴花层：血迹、弹壳、碎块永久印在地上。按 128 像素分块存 Image，只上传变动的分块。

const CHUNK := 128

var _images := {}
var _textures := {}
var _dirty := {}


func _chunk_image(key: Vector2i) -> Image:
	if _images.has(key):
		return _images[key]
	var img := Image.create_empty(CHUNK, CHUNK, false, Image.FORMAT_RGBA8)
	_images[key] = img
	_textures[key] = ImageTexture.create_from_image(img)
	queue_redraw()
	return img


## 把一张图居中印到世界坐标。
func stamp(src: Image, center: Vector2) -> void:
	var size := src.get_size()
	var top_left := Vector2i(center.round()) - size / 2
	var first := Vector2i(floori(float(top_left.x) / CHUNK), floori(float(top_left.y) / CHUNK))
	var last := Vector2i(floori(float(top_left.x + size.x - 1) / CHUNK), floori(float(top_left.y + size.y - 1) / CHUNK))
	for cy in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			if cx < 0 or cy < 0:
				continue
			var key := Vector2i(cx, cy)
			var dest := top_left - key * CHUNK
			_chunk_image(key).blend_rect(src, Rect2i(Vector2i.ZERO, size), dest)
			_dirty[key] = true


func stamp_pixel(pos: Vector2, color: Color) -> void:
	var p := Vector2i(pos.round())
	if p.x < 0 or p.y < 0:
		return
	var key := p / CHUNK
	var img := _chunk_image(key)
	var local := p - key * CHUNK
	img.set_pixelv(local, img.get_pixelv(local).blend(color))
	_dirty[key] = true


func stamp_pixel_group(pos: Vector2, color: Color, count: int) -> void:
	for i in count:
		stamp_pixel(pos + Vector2(randf_range(-3, 3), randf_range(-2, 2)), color)


func _physics_process(_dt: float) -> void:
	if _dirty.is_empty():
		return
	for key: Vector2i in _dirty.keys():
		_textures[key].update(_images[key])
	_dirty.clear()


func _draw() -> void:
	for key: Vector2i in _textures.keys():
		draw_texture(_textures[key], Vector2(key * CHUNK))
