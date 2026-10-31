extends RefCounted
## 特殊僵尸的行为基类。普通僵尸没有 brain，走 zombie.gd 里的默认逻辑。

## 每帧都要重画叠加层（护盾、蓄力光圈）时置位。
var redraw := false


func setup(_z: Variant) -> void:
	pass


## 返回 Vector2 表示接管本帧移动，返回 null 表示继续走默认逻辑。
func decide(_z: Variant, _dt: float, _player_ok: bool) -> Variant:
	return null


## 伤害结算前过滤一次，返回实际扣血量。
func absorb(_z: Variant, amount: float) -> float:
	return amount


func on_hit(_z: Variant) -> void:
	pass


func on_stun(_z: Variant) -> void:
	pass


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


## 叠加层，画在身体之上。
func draw(_z: Variant) -> void:
	pass
