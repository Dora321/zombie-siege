extends Node
## 本地存档：排行榜（前 5 名）和设置，保存在 user://zombie_siege.cfg。

const MAX_SCORES := 5

## 带命令行测试参数启动时写到单独的文件，不污染玩家的排行榜。
var path := "user://zombie_siege.cfg"
var scores: Array = []
var music_on := true
var sfx_on := true
var shake_on := true
## 上次选的地图，再来一局和下次开局都沿用。
var map_id := "ruins"


func _ready() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		path = "user://zombie_siege_test.cfg"
		DirAccess.remove_absolute(path)
	load_all()


func load_all() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	music_on = bool(cfg.get_value("settings", "music", true))
	sfx_on = bool(cfg.get_value("settings", "sfx", true))
	shake_on = bool(cfg.get_value("settings", "shake", true))
	var saved_map := String(cfg.get_value("settings", "map", "ruins"))
	map_id = saved_map if GameData.MAPS.has(saved_map) else "ruins"
	var loaded: Variant = cfg.get_value("records", "scores", [])
	scores = loaded if loaded is Array else []


func save_all() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "music", music_on)
	cfg.set_value("settings", "sfx", sfx_on)
	cfg.set_value("settings", "shake", shake_on)
	cfg.set_value("settings", "map", map_id)
	cfg.set_value("records", "scores", scores)
	cfg.save(path)


func best_score() -> int:
	return int(scores[0]["score"]) if not scores.is_empty() else 0


func best_wave() -> int:
	var best := 0
	for s in scores:
		best = maxi(best, int(s["wave"]))
	return best


## 记录一局成绩，返回名次（1 起）；没进前 5 返回 0。
func submit(score: int, wave: int, kills: int, victory: bool) -> int:
	var entry := {
		"score": score, "wave": wave, "kills": kills, "victory": victory,
		"date": Time.get_date_string_from_system(),
	}
	scores.append(entry)
	scores.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	if scores.size() > MAX_SCORES:
		scores.resize(MAX_SCORES)
	save_all()
	var at := scores.find(entry)
	return at + 1


func clear_scores() -> void:
	scores.clear()
	save_all()
