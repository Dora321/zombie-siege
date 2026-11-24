extends Node
## 本地存档：排行榜（前 5 名）、设置、无尽最高波次、波次间断点续玩和行动准备，保存在 user://zombie_siege.cfg。

const MAX_SCORES := 5

## 带命令行测试参数启动时写到单独的文件，不污染玩家的排行榜和局内续玩存档。
var path := "user://zombie_siege.cfg"
var resume_path := "user://zombie_siege_resume.cfg"
var scores: Array = []
var music_on := true
var sfx_on := true
var shake_on := true
var auto_aim_on := true
var auto_fire_on := false
## 上次选的地图，再来一局和下次开局都沿用。
var map_id := "ruins"
## 上次选的危险等级和契约，同样沿用；max_danger 是已解锁的最高危险等级（通关上一级解锁）。
var danger := 0
var contracts: Array[String] = []
var hero_id := "captain"
var game_mode := "normal"
var max_danger := 0
var best_endless_wave := 0
var best_boss_rush_time := 0.0
## 点击标题界面的「继续行动」时载入，由 game.gd 在 _ready() 消费并清空。
var pending_resume: Dictionary = {}


func _ready() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		path = "user://zombie_siege_test.cfg"
		resume_path = "user://zombie_siege_resume_test.cfg"
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(resume_path)
	load_all()


func load_all() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	music_on = bool(cfg.get_value("settings", "music", true))
	sfx_on = bool(cfg.get_value("settings", "sfx", true))
	shake_on = bool(cfg.get_value("settings", "shake", true))
	auto_aim_on = bool(cfg.get_value("settings", "auto_aim", true))
	auto_fire_on = bool(cfg.get_value("settings", "auto_fire", false))
	var saved_map := String(cfg.get_value("settings", "map", "ruins"))
	map_id = saved_map if GameData.MAPS.has(saved_map) else "ruins"
	max_danger = clampi(int(cfg.get_value("records", "max_danger", 0)), 0, GameData.MAX_DANGER)
	best_endless_wave = maxi(int(cfg.get_value("records", "best_endless_wave", 0)), 0)
	best_boss_rush_time = maxf(float(cfg.get_value("records", "best_boss_rush_time", 0.0)), 0.0)
	danger = clampi(int(cfg.get_value("run", "danger", 0)), 0, max_danger)
	var saved_hero := String(cfg.get_value("run", "hero", "captain"))
	hero_id = saved_hero if GameData.HEROES.has(saved_hero) else "captain"
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
	cfg.set_value("settings", "auto_aim", auto_aim_on)
	cfg.set_value("settings", "auto_fire", auto_fire_on)
	cfg.set_value("settings", "map", map_id)
	cfg.set_value("run", "danger", danger)
	cfg.set_value("run", "contracts", contracts)
	cfg.set_value("run", "hero", hero_id)
	cfg.set_value("records", "scores", scores)
	cfg.set_value("records", "max_danger", max_danger)
	cfg.set_value("records", "best_endless_wave", best_endless_wave)
	cfg.set_value("records", "best_boss_rush_time", best_boss_rush_time)
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


func record_endless(wave: int) -> bool:
	if wave <= best_endless_wave:
		return false
	best_endless_wave = wave
	save_all()
	return true


func record_boss_rush(seconds: float) -> bool:
	if seconds <= 0.0:
		return false
	if best_boss_rush_time > 0.0 and seconds >= best_boss_rush_time:
		return false
	best_boss_rush_time = seconds
	save_all()
	return true


func clear_scores() -> void:
	scores.clear()
	best_endless_wave = 0
	best_boss_rush_time = 0.0
	save_all()


# ---------------------------------------------------------------------------
# 波次间断点续玩存档
# ---------------------------------------------------------------------------

func has_resume_run() -> bool:
	return not load_resume_summary().is_empty()


func load_resume_summary() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(resume_path) != OK:
		return {}
	if int(cfg.get_value("meta", "version", 0)) != 1:
		return {}
	var data: Variant = cfg.get_value("state", "data", {})
	if not (data is Dictionary) or (data as Dictionary).is_empty():
		return {}
	var d: Dictionary = data
	var mid := String(d.get("map_id", "ruins"))
	if not GameData.MAPS.has(mid):
		return {}
	return {
		"wave": int(d.get("wave", 1)),
		"endless": bool(d.get("endless", false)),
		"map_id": mid,
		"danger": int(d.get("danger", 0)),
		"coins": int(d.get("coins", 0)),
	}


func load_resume_run() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(resume_path) != OK:
		return {}
	if int(cfg.get_value("meta", "version", 0)) != 1:
		return {}
	var data: Variant = cfg.get_value("state", "data", {})
	return (data as Dictionary).duplicate(true) if data is Dictionary else {}


func save_resume_run(data: Dictionary) -> void:
	if data.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("state", "data", data.duplicate(true))
	cfg.save(resume_path)


func clear_resume_run() -> void:
	pending_resume = {}
	if FileAccess.file_exists(resume_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(resume_path))
