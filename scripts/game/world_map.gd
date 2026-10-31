extends Node2D
## 世界地图：地面绘制、摆件生成、格子碰撞、流场寻路（僵尸都顺着它走向基地）。

const WallPieceScene := preload("res://scenes/entities/wall_piece.tscn")
const Layouts := preload("res://scripts/game/map_layouts.gd")

const TILE := 16
const W := 64
const H := 44
const PIXEL_W := W * TILE
const PIXEL_H := H * TILE

const BLOCK_PLAYER := 1
const BLOCK_ZOMBIE := 2
const BLOCK_BULLET := 4
const BLOCK_ALL := 7

# 废墟街区的围墙环（含边）与四个路障门，其它地图用 map_layouts.gd 的格子布局
const WALL_X0 := 23
const WALL_X1 := 40
const WALL_Y0 := 14
const WALL_Y1 := 29
const GATE_X0 := 30
const GATE_X1 := 33
const GATE_Y0 := 20
const GATE_Y1 := 23

const FLOW_INF := 1 << 30
## 停车场画车位线的行。
const STALL_ROWS: Array[int] = [7, 14, 24, 37]
## 补给箱落点：离地图边缘几格以内，并尽量离玩家多远。
const EDGE_BAND := 5
const EDGE_FAR := 220.0
const COST_WALL := 300
const COST_BARRICADE := 130
const COST_TURRET := 170
const COST_BARREL := 220

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var game: Node
var flags := PackedByteArray()
var dist := PackedInt32Array()
var next_cell := PackedInt32Array()
var structures := {}
var pieces: Array = []
var spawn_cells := {"top": [], "bottom": [], "left": [], "right": []}
var base_cells: Array[int] = []
var wall_tier := 0
var map_id := "ruins"
# 基地占地（格）
var base_x0 := 30
var base_x1 := 33
var base_y0 := 20
var base_y1 := 22
var player_start := Vector2(32 * TILE, 25 * TILE)
var minimap_tex: ImageTexture

var _grid: Array = []
var _compound := Rect2i(WALL_X0, WALL_Y0, WALL_X1 - WALL_X0 + 1, WALL_Y1 - WALL_Y0 + 1)
var _barrel_spots: Array[int] = []
var _ground: ImageTexture
var _flow_dirty := false
var _flow_wait := 0.0
var _heap: Array[int] = []
var _base_mask := PackedByteArray()
var _flow_task := -1
var _pending_dist := PackedInt32Array()
var _pending_next := PackedInt32Array()


func setup(g: Node, rng: RandomNumberGenerator) -> void:
	game = g
	flags.resize(W * H)
	flags.fill(0)
	dist.resize(W * H)
	next_cell.resize(W * H)
	_base_mask.resize(W * H)
	_base_mask.fill(0)
	map_id = Save.map_id
	_grid = Layouts.grid(map_id)
	_read_layout()
	for y in range(base_y0, base_y1 + 1):
		for x in range(base_x0, base_x1 + 1):
			var i := idx(x, y)
			flags[i] = BLOCK_PLAYER | BLOCK_ZOMBIE
			base_cells.append(i)
			_base_mask[i] = 1
	_build_ground(rng)
	if _grid.is_empty():
		_build_walls()
		_scatter_props(rng)
	else:
		_build_from_grid(rng)
	rebuild_flow()
	_collect_spawns()
	queue_redraw()


func _physics_process(dt: float) -> void:
	_flow_wait -= dt
	_flow_poll_task()
	if _flow_dirty and _flow_wait <= 0.0 and _flow_task < 0:
		_flow_start_task()
		_flow_wait = 0.2


func _exit_tree() -> void:
	_flow_finish_task()


func _draw() -> void:
	if _ground != null:
		draw_texture(_ground, Vector2.ZERO)


# ---------------------------------------------------------------------------
# 坐标工具
# ---------------------------------------------------------------------------

func idx(x: int, y: int) -> int:
	return y * W + x


func cell_of(pos: Vector2) -> int:
	return idx(clampi(int(pos.x) / TILE, 0, W - 1), clampi(int(pos.y) / TILE, 0, H - 1))


func cell_center(i: int) -> Vector2:
	return Vector2((i % W) * TILE + TILE * 0.5, (i / W) * TILE + TILE * 0.5)


func cell_top_left(i: int) -> Vector2:
	return Vector2((i % W) * TILE, (i / W) * TILE)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H


func blocks(i: int, mask: int) -> bool:
	return flags[i] & mask != 0


func structure_at(i: int) -> Variant:
	return structures.get(i)


func is_base_cell(i: int) -> bool:
	return _base_mask[i] == 1


## 点到某格矩形的距离。
func dist_to_cell(pos: Vector2, i: int) -> float:
	var tl := cell_top_left(i)
	var dx := maxf(maxf(tl.x - pos.x, 0.0), pos.x - (tl.x + TILE))
	var dy := maxf(maxf(tl.y - pos.y, 0.0), pos.y - (tl.y + TILE))
	return sqrt(dx * dx + dy * dy)


# ---------------------------------------------------------------------------
# 碰撞
# ---------------------------------------------------------------------------

func _box_hits(x: float, y: float, r: float, mask: int) -> bool:
	var ry := r * 0.7
	if x - r < 0.0 or y - ry < 0.0 or x + r >= PIXEL_W or y + ry >= PIXEL_H:
		return true
	var x0 := int(x - r) / TILE
	var x1 := int(x + r) / TILE
	var y0 := int(y - ry) / TILE
	var y1 := int(y + ry) / TILE
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if flags[cy * W + cx] & mask != 0:
				return true
	return false


## 轴分离地移动一个方盒，碰到障碍就沿边滑动。
func move_box(pos: Vector2, d: Vector2, r: float, mask: int) -> Vector2:
	var p := pos
	if d.x != 0.0:
		var nx := p.x + d.x
		if _box_hits(nx, p.y, r, mask):
			if d.x > 0.0:
				nx = floorf((nx + r) / TILE) * TILE - r - 0.01
			else:
				nx = (floorf((nx - r) / TILE) + 1.0) * TILE + r + 0.01
			if _box_hits(nx, p.y, r, mask) or absf(nx - p.x) > absf(d.x) + 0.02:
				nx = p.x
		p.x = nx
	if d.y != 0.0:
		var ny := p.y + d.y
		if _box_hits(p.x, ny, r, mask):
			var ry := r * 0.7
			if d.y > 0.0:
				ny = floorf((ny + ry) / TILE) * TILE - ry - 0.01
			else:
				ny = (floorf((ny - ry) / TILE) + 1.0) * TILE + ry + 0.01
			if _box_hits(p.x, ny, r, mask) or absf(ny - p.y) > absf(d.y) + 0.02:
				ny = p.y
		p.y = ny
	return p


func line_clear(a: Vector2, b: Vector2, mask: int) -> bool:
	var delta := b - a
	var steps := int(delta.length() / 7.0) + 1
	for i in range(1, steps + 1):
		var p := a + delta * (float(i) / steps)
		if flags[cell_of(p)] & mask != 0:
			return false
	return true


## 把卡进障碍里的角色推到最近的空地（修墙时可能发生）。
func unstick(pos: Vector2, r: float, mask: int) -> Vector2:
	if not _box_hits(pos.x, pos.y, r, mask):
		return pos
	for radius in range(1, 8):
		for k in 16:
			var p := pos + Vector2.from_angle(k * TAU / 16.0) * radius * TILE * 0.75
			if not _box_hits(p.x, p.y, r, mask):
				return p
	return pos


# ---------------------------------------------------------------------------
# 流场寻路：从基地向外跑 Dijkstra；可破坏建筑可通过但代价高，
# 所以僵尸优先走缺口，没有缺口时才啃最近的墙。
# ---------------------------------------------------------------------------

func request_flow() -> void:
	_flow_dirty = true


## 同步重建：开局和测试用。
func rebuild_flow() -> void:
	_flow_finish_task()
	_flow_dirty = false
	_flow_compute(flags.duplicate(), _snapshot_costs(), _solid_snapshot())
	dist = _pending_dist
	next_cell = _pending_next


## 战斗中在后台线程算，主线程只取快照和交换结果，墙被打破时不掉帧。
func _flow_start_task() -> void:
	_flow_dirty = false
	var f := flags.duplicate()
	var costs := _snapshot_costs()
	var solid := _solid_snapshot()
	_flow_task = WorkerThreadPool.add_task(_flow_compute.bind(f, costs, solid))


func _flow_finish_task() -> void:
	if _flow_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_flow_task)
		_flow_task = -1


func _flow_poll_task() -> void:
	if _flow_task >= 0 and WorkerThreadPool.is_task_completed(_flow_task):
		_flow_finish_task()
		dist = _pending_dist
		next_cell = _pending_next


func _snapshot_costs() -> PackedInt32Array:
	var costs := PackedInt32Array()
	costs.resize(W * H)
	for i: int in structures.keys():
		costs[i] = _enter_cost(i)
	return costs


## 标记不可破坏的实心格（树、石头、车）。
func _solid_snapshot() -> PackedByteArray:
	var solid := PackedByteArray()
	solid.resize(W * H)
	for i in W * H:
		if flags[i] & BLOCK_ZOMBIE != 0 and not structures.has(i):
			solid[i] = 1
	return solid


## 纯数据计算，可在工作线程执行，不访问节点。
func _flow_compute(f: PackedByteArray, costs: PackedInt32Array, solid: PackedByteArray) -> void:
	var d := PackedInt32Array()
	d.resize(W * H)
	d.fill(FLOW_INF)
	var nxt := PackedInt32Array()
	nxt.resize(W * H)
	nxt.fill(-1)
	_heap.clear()
	for i in base_cells:
		d[i] = 0
		_heap_push_cost(0, i)
	var block := BLOCK_ZOMBIE
	while not _heap.is_empty():
		var v := _heap_pop()
		var cost := v >> 16
		var i := v & 0xFFFF
		if cost > d[i]:
			continue
		var x := i % W
		var y := i / W
		var here_blocked := f[i] & block != 0
		var nd_base := cost + costs[i]
		for k in 8:
			var nx := x + DIRS[k].x
			var ny := y + DIRS[k].y
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := ny * W + nx
			if _base_mask[j] == 1 or solid[j] == 1:
				continue
			var step := 10
			if k >= 4:
				step = 14
				# 不允许斜穿墙角
				if here_blocked or f[y * W + nx] & block != 0 or f[ny * W + x] & block != 0:
					continue
			var nd := nd_base + step
			if nd < d[j]:
				d[j] = nd
				nxt[j] = i
				_heap_push_cost(nd, j)
	_pending_dist = d
	_pending_next = nxt


func _enter_cost(i: int) -> int:
	if not structures.has(i) or _base_mask[i] == 1:
		return 0
	var s: Variant = structures[i]
	match String(s.kind):
		"wall":
			return COST_WALL
		"barricade":
			return COST_BARRICADE
		"barrel":
			return COST_BARREL
		_:
			return COST_TURRET


func _heap_push_cost(cost: int, i: int) -> void:
	_heap.append((cost << 16) | i)
	var c := _heap.size() - 1
	while c > 0:
		var p := (c - 1) / 2
		if _heap[p] <= _heap[c]:
			break
		var t := _heap[p]
		_heap[p] = _heap[c]
		_heap[c] = t
		c = p


func _heap_pop() -> int:
	var top := _heap[0]
	var last: int = _heap.pop_back()
	var n := _heap.size()
	if n > 0:
		_heap[0] = last
		var c := 0
		while true:
			var l := c * 2 + 1
			var r := l + 1
			var m := c
			if l < n and _heap[l] < _heap[m]:
				m = l
			if r < n and _heap[r] < _heap[m]:
				m = r
			if m == c:
				break
			var t := _heap[m]
			_heap[m] = _heap[c]
			_heap[c] = t
			c = m
	return top


func _collect_spawns() -> void:
	for x in W:
		if dist[idx(x, 0)] < FLOW_INF:
			spawn_cells["top"].append(idx(x, 0))
		if dist[idx(x, H - 1)] < FLOW_INF:
			spawn_cells["bottom"].append(idx(x, H - 1))
	for y in H:
		if dist[idx(0, y)] < FLOW_INF:
			spawn_cells["left"].append(idx(0, y))
		if dist[idx(W - 1, y)] < FLOW_INF:
			spawn_cells["right"].append(idx(W - 1, y))


# ---------------------------------------------------------------------------
# 建筑管理
# ---------------------------------------------------------------------------

func set_structure(i: int, node: Variant, cell_flags: int) -> void:
	structures[i] = node
	flags[i] = cell_flags
	request_flow()


func clear_structure(i: int) -> void:
	structures.erase(i)
	flags[i] = 0
	request_flow()


func _build_walls() -> void:
	for y in range(WALL_Y0, WALL_Y1 + 1):
		for x in range(WALL_X0, WALL_X1 + 1):
			var edge_h := y == WALL_Y0 or y == WALL_Y1
			var edge_v := x == WALL_X0 or x == WALL_X1
			if not edge_h and not edge_v:
				continue
			var gate := (edge_h and x >= GATE_X0 and x <= GATE_X1) or (edge_v and y >= GATE_Y0 and y <= GATE_Y1)
			_add_piece(x, y, "barricade" if gate else "wall")
	refresh_wall_faces()


func _add_piece(x: int, y: int, kind: String) -> Node2D:
	var piece: Node2D = WallPieceScene.instantiate()
	game.entities.add_child(piece)
	piece.setup(game, self, kind, idx(x, y))
	pieces.append(piece)
	return piece


## 墙体下方没有墙时才露出砖面。
func refresh_wall_faces() -> void:
	for piece in pieces:
		if piece.kind != "wall":
			continue
		var below := int(piece.cell) + W
		var has_below := structures.has(below) and String(structures[below].kind) == "wall"
		piece.set_front(not has_below)


func missing_wall_hp() -> float:
	var total := 0.0
	for piece in pieces:
		if piece.kind == "wall" or piece.kind == "barricade":
			total += piece.max_hp - piece.hp
	return total


## 用 ratio（0~1）比例修复所有围墙和路障，已摧毁的也能重建。
func repair_walls(ratio: float) -> void:
	for piece in pieces:
		if piece.kind == "wall" or piece.kind == "barricade":
			piece.repair((piece.max_hp - piece.hp) * ratio)
	refresh_wall_faces()


func raise_wall_tier() -> void:
	wall_tier += 1
	for piece in pieces:
		if piece.kind == "wall" or piece.kind == "barricade":
			piece.apply_tier(wall_tier)


func alive_barrels() -> int:
	var n := 0
	for piece in pieces:
		if piece.kind == "barrel" and piece.alive:
			n += 1
	return n


## 波次之间补充炸药桶，让爆炸玩法贯穿全局。
func respawn_barrels(rng: RandomNumberGenerator, count: int) -> void:
	if not _grid.is_empty():
		_respawn_barrels_at_spots(rng, count)
		return
	for attempt in count * 12:
		if count <= 0:
			return
		var x := rng.randi_range(3, W - 4)
		var y := rng.randi_range(3, H - 4)
		if x >= WALL_X0 - 2 and x <= WALL_X1 + 2 and y >= WALL_Y0 - 2 and y <= WALL_Y1 + 2:
			continue
		var i := idx(x, y)
		if flags[i] != 0 or _on_road(x, y):
			continue
		if game.player != null and game.player.position.distance_to(cell_center(i)) < 32.0:
			continue
		_add_piece(x, y, "barrel")
		count -= 1


## 手工地图只在标好的点补桶，免得把窄巷堵死。
func _respawn_barrels_at_spots(rng: RandomNumberGenerator, count: int) -> void:
	var spots := _barrel_spots.duplicate()
	while count > 0 and not spots.is_empty():
		var i: int = spots.pop_at(rng.randi() % spots.size())
		if flags[i] != 0:
			continue
		if game.player != null and game.player.position.distance_to(cell_center(i)) < 32.0:
			continue
		_add_piece(i % W, i / W, "barrel")
		count -= 1


func can_place_turret(i: int) -> bool:
	if flags[i] != 0 or structures.has(i):
		return false
	if game.player != null:
		var p: Vector2 = game.player.position
		if dist_to_cell(p, i) < 6.0:
			return false
	return true


# ---------------------------------------------------------------------------
# 地图生成
# ---------------------------------------------------------------------------

## 从格子布局读出基地、出生点和大院范围。
func _read_layout() -> void:
	if _grid.is_empty():
		return
	var base_rect := Rect2i()
	var yard := Rect2i()
	for y in H:
		var row: String = _grid[y]
		for x in W:
			var at := Rect2i(x, y, 1, 1)
			match row[x]:
				"H":
					base_rect = at if base_rect.size == Vector2i.ZERO else base_rect.merge(at)
				"P":
					player_start = Vector2(x * TILE + TILE * 0.5, y * TILE + TILE * 0.5)
				"W", "B":
					yard = at if yard.size == Vector2i.ZERO else yard.merge(at)
	base_x0 = base_rect.position.x
	base_y0 = base_rect.position.y
	base_x1 = base_rect.end.x - 1
	base_y1 = base_rect.end.y - 1
	_compound = yard


## 按格子布局摆出楼房、围墙和摆件。
func _build_from_grid(rng: RandomNumberGenerator) -> void:
	var mini := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		var row: String = _grid[y]
		for x in W:
			match row[x]:
				"#":
					flags[idx(x, y)] = BLOCK_ALL
					mini.set_pixel(x, y, Color(0.5, 0.48, 0.55, 0.75))
				"W":
					_add_piece(x, y, "wall")
				"B":
					_add_piece(x, y, "barricade")
				"C":
					_add_prop(x, y, Art.cars[rng.randi() % Art.cars.size()], 2)
				"L":
					_add_prop(x, y, Art.lamp_tex, 1)
				"D":
					_add_prop(x, y, Art.dumpster_tex, 1)
				"R":
					_barrel_spots.append(idx(x, y))
	minimap_tex = ImageTexture.create_from_image(mini)
	refresh_wall_faces()
	respawn_barrels(rng, 8)


## 从 start 向外跑一遍广度优先，返回每格的步数（到不了是 -1）。
func reach_field(start: int, mask: int) -> PackedInt32Array:
	var d := PackedInt32Array()
	d.resize(W * H)
	d.fill(-1)
	d[start] = 0
	var frontier: Array[int] = [start]
	var head := 0
	while head < frontier.size():
		var i: int = frontier[head]
		head += 1
		var x := i % W
		var y := i / W
		for k in 4:
			var nx := x + DIRS[k].x
			var ny := y + DIRS[k].y
			if not in_bounds(nx, ny):
				continue
			var j := ny * W + nx
			if d[j] < 0 and flags[j] & mask == 0:
				d[j] = d[i] + 1
				frontier.append(j)
	return d


## 地图边缘一圈里，玩家走得到的空地上随便挑一格放补给箱，尽量离玩家远一点。
func edge_spot(rng: RandomNumberGenerator, from: Vector2) -> Vector2:
	var reach := reach_field(cell_of(from), BLOCK_PLAYER)
	var near: Array[int] = []
	var far: Array[int] = []
	for y in H:
		for x in W:
			var margin := mini(mini(x, W - 1 - x), mini(y, H - 1 - y))
			var i := idx(x, y)
			if margin < 1 or margin > EDGE_BAND or flags[i] != 0 or reach[i] < 0:
				continue
			near.append(i)
			if cell_center(i).distance_to(from) > EDGE_FAR:
				far.append(i)
	var pool: Array[int] = far if not far.is_empty() else near
	if pool.is_empty():
		return from
	return cell_center(pool[rng.randi() % pool.size()])


func _on_road(x: int, y: int) -> bool:
	return (y >= GATE_Y0 and y <= GATE_Y1) or (x >= GATE_X0 and x <= GATE_X1)


func _inside_compound(x: int, y: int) -> bool:
	return x > WALL_X0 and x < WALL_X1 and y > WALL_Y0 and y < WALL_Y1


func _build_ground(rng: RandomNumberGenerator) -> void:
	if not _grid.is_empty():
		_build_grid_ground(rng)
		return
	var img := Image.create_empty(PIXEL_W, PIXEL_H, false, Image.FORMAT_RGBA8)
	var patches := FastNoiseLite.new()
	patches.seed = rng.randi()
	patches.frequency = 0.09
	var dirt_noise := FastNoiseLite.new()
	dirt_noise.seed = rng.randi()
	dirt_noise.frequency = 0.14
	var full := Rect2i(0, 0, TILE, TILE)
	for y in H:
		for x in W:
			var set_name := "grass"
			if _inside_compound(x, y) or (x >= WALL_X0 and x <= WALL_X1 and y >= WALL_Y0 and y <= WALL_Y1):
				set_name = "concrete"
			elif _on_road(x, y):
				set_name = "road"
			elif dirt_noise.get_noise_2d(x, y) > 0.42:
				set_name = "dirt"
			elif patches.get_noise_2d(x, y) > 0.05:
				set_name = "grass_dark"
			var set_tiles: Array = Art.tiles[set_name]
			var tile: Image = set_tiles[rng.randi() % set_tiles.size()]
			img.blit_rect(tile, full, Vector2i(x * TILE, y * TILE))
	_paint_road_marks(img)
	_ground = ImageTexture.create_from_image(img)


func _paint_road_marks(img: Image) -> void:
	var curb := Color("#8a887e")
	var curb_d := Color("#5e5c54")
	var dash := Color("#d8c860")
	var road_y0 := GATE_Y0 * TILE
	var road_y1 := (GATE_Y1 + 1) * TILE
	var road_x0 := GATE_X0 * TILE
	var road_x1 := (GATE_X1 + 1) * TILE
	var cx0 := (WALL_X0) * TILE
	var cx1 := (WALL_X1 + 1) * TILE
	var cy0 := (WALL_Y0) * TILE
	var cy1 := (WALL_Y1 + 1) * TILE
	# 路缘石
	for x in range(0, PIXEL_W, 2):
		if (x >= road_x0 and x < road_x1) or (x >= cx0 and x < cx1):
			continue
		img.fill_rect(Rect2i(x, road_y0 - 1, 2, 2), curb if x % 8 else curb_d)
		img.fill_rect(Rect2i(x, road_y1 - 1, 2, 2), curb if x % 8 else curb_d)
	for y in range(0, PIXEL_H, 2):
		if (y >= road_y0 and y < road_y1) or (y >= cy0 and y < cy1):
			continue
		img.fill_rect(Rect2i(road_x0 - 1, y, 2, 2), curb if y % 8 else curb_d)
		img.fill_rect(Rect2i(road_x1 - 1, y, 2, 2), curb if y % 8 else curb_d)
	# 中心虚线
	var mid_y := (GATE_Y0 + GATE_Y1 + 1) * TILE / 2
	var mid_x := (GATE_X0 + GATE_X1 + 1) * TILE / 2
	for x in range(4, PIXEL_W, 24):
		if x + 12 > road_x0 - 4 and x < road_x1 + 4:
			continue
		if x + 12 > cx0 and x < cx1:
			continue
		img.fill_rect(Rect2i(x, mid_y - 1, 12, 2), dash)
	for y in range(4, PIXEL_H, 24):
		if y + 12 > road_y0 - 4 and y < road_y1 + 4:
			continue
		if y + 12 > cy0 and y < cy1:
			continue
		img.fill_rect(Rect2i(mid_x - 1, y, 2, 12), dash)
	# 院内围绕基地的停机坪标线
	_paint_base_pad(img)


func _paint_base_pad(img: Image) -> void:
	var pad := Rect2i((base_x0 - 2) * TILE, (base_y0 - 2) * TILE, (base_x1 - base_x0 + 5) * TILE, (base_y1 - base_y0 + 5) * TILE)
	for x in range(pad.position.x, pad.end.x, 8):
		var c := Color("#c8a030") if (x / 8) % 2 == 0 else Color("#2c2c28")
		img.fill_rect(Rect2i(x, pad.position.y, 8, 2), c)
		img.fill_rect(Rect2i(x, pad.end.y - 2, 8, 2), c)
	for y in range(pad.position.y, pad.end.y, 8):
		var c := Color("#c8a030") if (y / 8) % 2 == 0 else Color("#2c2c28")
		img.fill_rect(Rect2i(pad.position.x, y, 2, 8), c)
		img.fill_rect(Rect2i(pad.end.x - 2, y, 2, 8), c)


## 手工地图的地面：沥青或石板，楼房直接画进地面里。
func _build_grid_ground(rng: RandomNumberGenerator) -> void:
	var img := Image.create_empty(PIXEL_W, PIXEL_H, false, Image.FORMAT_RGBA8)
	var style := String(GameData.MAPS[map_id]["ground"])
	var patches := FastNoiseLite.new()
	patches.seed = rng.randi()
	patches.frequency = 0.11
	var full := Rect2i(0, 0, TILE, TILE)
	for y in H:
		for x in W:
			var set_name := style
			if _compound.has_point(Vector2i(x, y)):
				set_name = "concrete"
			elif patches.get_noise_2d(x, y) > 0.2:
				set_name = style + "_alt"
			if _grid_is_solid(x, y):
				set_name = "roof" if _grid_is_solid(x, y + 1) or y == H - 1 else "brick"
			var set_tiles: Array = Art.tiles[set_name]
			img.blit_rect(set_tiles[rng.randi() % set_tiles.size()], full, Vector2i(x * TILE, y * TILE))
	if style == "asphalt":
		_paint_stalls(img)
	_paint_building_edges(img)
	_paint_base_pad(img)
	_ground = ImageTexture.create_from_image(img)


func _grid_is_solid(x: int, y: int) -> bool:
	return in_bounds(x, y) and String(_grid[y])[x] == "#"


## 车位线：每排车上下各一道短白线，中间露出通道。
func _paint_stalls(img: Image) -> void:
	var line := Color("#b8b4a0")
	for row: int in STALL_ROWS:
		for x in range(3, W - 2, 3):
			if _compound.has_point(Vector2i(x, row)):
				continue
			img.fill_rect(Rect2i(x * TILE - 1, (row - 1) * TILE + 6, 2, TILE * 2), line)
	# 通道方向箭头
	for x in range(6, W, 14):
		for y: int in [3, 18, 33]:
			if _compound.grow(1).has_point(Vector2i(x, y)):
				continue
			var at := Vector2i(x * TILE, y * TILE)
			img.fill_rect(Rect2i(at, Vector2i(14, 2)), line)
			img.fill_rect(Rect2i(at + Vector2i(10, -2), Vector2i(2, 6)), line)
			img.fill_rect(Rect2i(at + Vector2i(12, -1), Vector2i(2, 4)), line)


## 楼顶的亮边和暗边，楼脚投一点阴影，看着才有高度。
func _paint_building_edges(img: Image) -> void:
	var shade := Image.create_empty(TILE, 5, false, Image.FORMAT_RGBA8)
	shade.fill(Color(0, 0, 0, 0.32))
	var light := Color("#4c4a58")
	var dark := Color("#1a1820")
	for y in H:
		for x in W:
			var at := Vector2i(x * TILE, y * TILE)
			if not _grid_is_solid(x, y):
				if _grid_is_solid(x, y - 1):
					img.blend_rect(shade, Rect2i(0, 0, TILE, 5), at)
				continue
			if y > 0 and not _grid_is_solid(x, y - 1):
				img.fill_rect(Rect2i(at, Vector2i(TILE, 2)), light)
			if x > 0 and not _grid_is_solid(x - 1, y):
				img.fill_rect(Rect2i(at, Vector2i(1, TILE)), dark)
			if x < W - 1 and not _grid_is_solid(x + 1, y):
				img.fill_rect(Rect2i(at + Vector2i(TILE - 1, 0), Vector2i(1, TILE)), dark)


func _prop_cell_ok(x: int, y: int) -> bool:
	if x < 2 or y < 2 or x >= W - 2 or y >= H - 2:
		return false
	if x >= WALL_X0 - 3 and x <= WALL_X1 + 3 and y >= WALL_Y0 - 3 and y <= WALL_Y1 + 3:
		return false
	return flags[idx(x, y)] == 0


func _add_prop(x: int, y: int, tex: Texture2D, cells: int) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height())
	s.position = Vector2(x * TILE + cells * TILE * 0.5, (y + 1) * TILE)
	game.entities.add_child(s)
	for c in cells:
		flags[idx(x + c, y)] = BLOCK_ALL


func _scatter_props(rng: RandomNumberGenerator) -> void:
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 600:
		tries += 1
		var x := rng.randi_range(2, W - 3)
		var y := rng.randi_range(2, H - 3)
		if not _prop_cell_ok(x, y) or _on_road(x, y):
			continue
		# 树和石头之间留出空隙，防止把路堵死
		var crowded := false
		for d in DIRS:
			if in_bounds(x + d.x, y + d.y) and flags[idx(x + d.x, y + d.y)] != 0:
				crowded = true
		if crowded:
			continue
		var roll := rng.randf()
		if roll < 0.62:
			_add_prop(x, y, Art.trees[rng.randi() % Art.trees.size()], 1)
		elif roll < 0.84:
			_add_prop(x, y, Art.rocks[rng.randi() % Art.rocks.size()], 1)
		else:
			_add_prop(x, y, Art.crate_tex, 1)
		placed += 1
	# 废弃车辆（可以挡在路上）
	var cars_left := 7
	tries = 0
	while cars_left > 0 and tries < 200:
		tries += 1
		var x := rng.randi_range(2, W - 4)
		var y := rng.randi_range(2, H - 3)
		if not _prop_cell_ok(x, y) or not _prop_cell_ok(x + 1, y):
			continue
		if y == GATE_Y0 or y == GATE_Y1 or x == GATE_X0 or x + 1 == GATE_X1:
			pass
		_add_prop(x, y, Art.cars[rng.randi() % Art.cars.size()], 2)
		cars_left -= 1
	respawn_barrels(rng, 8)
