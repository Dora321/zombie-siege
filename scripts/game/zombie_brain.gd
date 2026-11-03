extends RefCounted
## 特殊僵尸的行为基类。普通僵尸没有 brain，走 zombie.gd 里的默认逻辑。

## 每帧都要重画叠加层（护盾、蓄力光圈）时置位。
var redraw := false


func setup(_z: Variant) -> void:
	pass


## 返回 Vector2 表示接管本帧移动，返回 null 表示继续走默认逻辑。
func decide(_z: Variant, _dt: float, _player_ok: bool) -> Variant:
	return null


## 伤害结算前过滤一次，返回实际扣血量。src 是伤害来源，见 boss_brain.gd。
func absorb(_z: Variant, amount: float, _src := "") -> float:
	return amount


## 每帧都调用，晕眩和冰冻时也不停。
func tick(_z: Variant, _dt: float) -> void:
	pass


func on_hit(_z: Variant) -> void:
	pass


func on_stun(_z: Variant) -> void:
	pass


## 被霰弹弹丸打中，knock 是没打 knock_res 折扣的原始击退。
func on_buckshot(_z: Variant, _knock: float) -> void:
	pass


## 这一下有没有打在弱点上（伤害已经结算进血量）。src 同 absorb，dir 是命中方向，火焰 tick 时为零向量。
func weak_hit(_z: Variant, _src: String, _dir: Vector2) -> bool:
	return false


func on_die(_z: Variant) -> void:
	pass


## 这一发子弹是否被挡下。dir 是子弹的飞行方向。
func blocks(_z: Variant, _dir: Vector2) -> bool:
	return false


func shield_hit(_z: Variant, _amount: float) -> void:
	pass


## 是否处于隐身状态。隐身时炮塔和小地图都看不到。
func cloaked() -> bool:
	return false


## 钻在地下：子弹、光束、电弧和回旋镖都打不到。
func underground() -> bool:
	return false


## 子弹打中前问一次是否被弹回去，返回 true 表示这一发作废。
func reflect_shot(_z: Variant, _dir: Vector2, _damage: float, _src: String, _from_player: bool) -> bool:
	return false


## 叠加层，画在身体之上。
func draw(_z: Variant) -> void:
	pass
