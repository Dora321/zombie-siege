extends Control
## 结算界面：胜负原因、本局数据、是否破纪录。

var game: Node

@onready var title_label: Label = %TitleLabel
@onready var reason_label: Label = %ReasonLabel
@onready var stats_label: Label = %StatsLabel
@onready var record_label: Label = %RecordLabel
@onready var endless_button: Button = %EndlessButton
@onready var retry_button: Button = %RetryButton
@onready var title_button: Button = %BackButton


func setup(g: Node) -> void:
	game = g
	visible = false
	endless_button.pressed.connect(_continue_endless)
	retry_button.pressed.connect(_retry)
	title_button.pressed.connect(_back)


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var won: bool = game.victory
	endless_button.visible = won and not game.endless and not game.boss_rush and not Harness.automated()
	title_label.text = "胜利！" if won else "城破了"
	title_label.modulate = Color("#ffe080") if won else Color("#ff6a50")
	if game.endless:
		title_label.text = "无尽止步"
		title_label.modulate = Color("#ff985e")
	reason_label.text = game.end_reason
	var fired: int = game.bullets.shots_fired
	var accuracy := 0 if fired == 0 else roundi(float(game.bullets.shots_hit) / fired * 100.0)
	# 有危险等级或契约时写出原分和倍率
	var score_txt := str(game.score)
	if game.score_mult > 1.0:
		score_txt += "（%d %s）" % [game.raw_score, GameData.mult_text(game.score_mult)]
	var map_txt := String(GameData.MAPS[game.map.map_id]["name"])
	if game.danger > 0:
		map_txt += " 危%d" % game.danger
	var wave_txt := "坚持波次  %d / %d" % [game.wave, GameData.MAX_WAVE]
	if game.boss_rush:
		wave_txt = "  连战 %d / %d" % [game.wave, GameData.boss_rush_wave_count()]
	elif game.endless:
		wave_txt = "\n无尽波次  第 %d 波（最高 %d 波）" % [game.wave, Save.best_endless_wave]
	else:
		wave_txt = "  " + wave_txt
	var time_label := "通关用时" if game.boss_rush and won else "战斗时长"
	stats_label.text = "最终分数  %s\n地图 %s%s\n击杀僵尸  %d    最高连杀  %d\n命中率  %d%%    %s  %s\n累计金币  %d" % [
		score_txt, map_txt, wave_txt, game.kills, game.best_combo,
		accuracy, time_label, _format_time(game.time_alive), game.coins_earned,
	]
	if game.hero_id != "captain" or not game.perks.is_empty():
		stats_label.text += "\n%s    天赋 ×%d" % [GameData.HEROES[game.hero_id]["name"], game.perks.size()]
	if game.boss_rush:
		var best := Save.best_boss_rush_time
		record_label.text = "连战最快  %s" % (_format_time(best) if best > 0.0 else "暂无")
		record_label.modulate = Color("#ff9860")
	elif game.result_rank == 1:
		record_label.text = "新纪录！历史最高分"
		record_label.modulate = Color("#ffe080")
	elif game.result_rank > 1:
		record_label.text = "进入排行榜第 %d 名    最高分 %d" % [game.result_rank, Save.best_score()]
		record_label.modulate = Color("#c8e070")
	else:
		record_label.text = "历史最高分 %d" % Save.best_score()
		record_label.modulate = Color("#c8c4b8")
	var first := endless_button if endless_button.visible else retry_button
	first.grab_focus()


func _format_time(seconds: float) -> String:
	var elapsed := int(seconds)
	return "%d:%02d" % [elapsed / 60, elapsed % 60]


func _continue_endless() -> void:
	Sfx.play("ui_click")
	game.continue_endless()


func _retry() -> void:
	Sfx.play("ui_click")
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _back() -> void:
	Sfx.play("ui_click")
	get_tree().change_scene_to_file("res://scenes/ui/title.tscn")
