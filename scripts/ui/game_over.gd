extends Control
## 结算界面：胜负原因、本局数据、是否破纪录。

var game: Node

@onready var title_label: Label = %TitleLabel
@onready var reason_label: Label = %ReasonLabel
@onready var stats_label: Label = %StatsLabel
@onready var record_label: Label = %RecordLabel
@onready var retry_button: Button = %RetryButton
@onready var title_button: Button = %BackButton


func setup(g: Node) -> void:
	game = g
	visible = false
	retry_button.pressed.connect(_retry)
	title_button.pressed.connect(_back)


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var won: bool = game.victory
	title_label.text = "胜利！" if won else "城破了"
	title_label.modulate = Color("#ffe080") if won else Color("#ff6a50")
	reason_label.text = game.end_reason
	var fired: int = game.bullets.shots_fired
	var accuracy := 0 if fired == 0 else roundi(float(game.bullets.shots_hit) / fired * 100.0)
	var minutes := int(game.time_alive) / 60
	var seconds := int(game.time_alive) % 60
	# 有危险等级或契约时写出原分和倍率
	var score_txt := str(game.score)
	if game.score_mult > 1.0:
		score_txt += "（%d %s）" % [game.raw_score, GameData.mult_text(game.score_mult)]
	var map_txt := String(GameData.MAPS[game.map.map_id]["name"])
	if game.danger > 0:
		map_txt += " 危%d" % game.danger
	stats_label.text = "最终分数  %s\n地图 %s  坚持波次  %d / %d\n击杀僵尸  %d    最高连杀  %d\n命中率  %d%%    战斗时长  %d:%02d\n累计金币  %d" % [
		score_txt, map_txt, game.wave, GameData.MAX_WAVE, game.kills, game.best_combo,
		accuracy, minutes, seconds, game.coins_earned,
	]
	if game.result_rank == 1:
		record_label.text = "新纪录！历史最高分"
		record_label.modulate = Color("#ffe080")
	elif game.result_rank > 1:
		record_label.text = "进入排行榜第 %d 名    最高分 %d" % [game.result_rank, Save.best_score()]
		record_label.modulate = Color("#c8e070")
	else:
		record_label.text = "历史最高分 %d" % Save.best_score()
		record_label.modulate = Color("#c8c4b8")
	retry_button.grab_focus()


func _retry() -> void:
	Sfx.play("ui_click")
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _back() -> void:
	Sfx.play("ui_click")
	get_tree().change_scene_to_file("res://scenes/ui/title.tscn")
