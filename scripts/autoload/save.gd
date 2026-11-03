extends Node
## 本地存档：排行榜（前 5 名）、设置和上次的行动准备（危险等级、契约），保存在 user://zombie_siege.cfg。

const MAX_SCORES := 5

## 带命令行测试参数启动时写到单独的文件，不污染玩家的排行榜。
var path := "user://zombie_siege.cfg"
var scores: Array = []
var music_on := true
var sfx_on := true
var shake_on := true
## 上次选的地图，再来一局和下次开局都沿用。
var map_id := "ruins"
## 上次选的危险等级和契约，同样沿用；max_danger 是已解锁的最高危险等级（通关上一级解锁）。
var danger := 0
var contracts: Array[String] = []
var max_danger := 0


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
	max_danger = clampi(int(cfg.get_value("records", "max_danger", 0)), 0, GameData.MAX_DANGER)
	danger = clampi(int(cfg.get_value("run", "danger", 0)), 0, max_danger)
	contracts.clear()
	var saved_contracts: Variant = cfg.get_value("run", "contracts", [])
	if saved_contracts is Array:
		for id: Variant in saved_contracts:
			if GameData.CONTRACTS.has(String(id)) and not contracts.has(String(id)):
				contracts.append(String(id))
	var loaded: Variant = cfg.get_value("records", "scores", [])
	scores = loaded if loaded is Array else []


func save_all() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "music", music_on)
	cfg.set_value("settings", "sfx", sfx_on)
	cfg.set_value("settings", "shake", shake_on)
	cfg.set_value("settings", "map", map_id)
	cfg.set_value("run", "danger", danger)
	cfg.set_value("run", "contracts", contracts)
	cfg.set_value("records", "scores", scores)
	cfg.set_value("records", "max_danger", max_danger)
	cfg.save(path)


func best_score() -> int:
	return int(scores[0]["score"]) if not scores.is_empty() else 0


func best_wave() -> int:
	var best := 0
	for s in scores:
		best = maxi(best, int(s["wave"]))
	return best


## 记录一局成绩，返回名次（1 起）；没进前 5 返回 0。score 已乘过 mult；旧存档没有 danger/contracts/mult，读的时候当 0、空、1。
func submit(score: int, wave: int, kills: int, victory: bool, run_danger := 0, run_contracts: Array = [], mult := 1.0) -> int:
	var entry := {
		"score": score, "wave": wave, "kills": kills, "victory": victory,
		"date": Time.get_date_string_from_system(),
		"danger": run_danger, "contracts": run_contracts.duplicate(), "mult": mult,
	}
	scores.append(entry)
	scores.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	if scores.size() > MAX_SCORES:
		scores.resize(MAX_SCORES)
	save_all()
	var at := scores.find(entry)
	return at + 1


## 通关后解锁下一级危险。真的解锁了返回 true。
func unlock_danger(level: int) -> bool:
	level = mini(level, GameData.MAX_DANGER)
	if level <= max_danger:
		return false
	max_danger = level
	save_all()
	return true


func clear_scores() -> void:
	scores.clear()
	save_all()
