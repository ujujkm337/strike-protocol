extends CharacterBody3D
## Одна створка двери из пака Quaternius (CC0). В архиве пака этот скрипт
## отсутствовал (лежал только door_body.gd.uid), и обе сцены дверей
## (doors/door_single.tscn, doors/door_double.tscn) не грузились:
## «Parse Error: referenced non-existent resource door_body.gd».
##
## Створка — CharacterBody3D (в паке так), поэтому двигается position'ом, а не
## move_and_slide: нам нужно точное смещение на `distance`, а не физика.

@export var distance := Vector3(1.4, 0.0, 0.0)   # куда уезжает открытая створка
@export var open_time := 0.7                      # секунд на полный ход
@export var locked := false                       # true — не открывается никогда

var opened := 0.0                                 # 0 = закрыта, 1 = открыта
var _target := 0.0
var _home := Vector3.ZERO
var _tween: Tween = null


func _ready() -> void:
	# Слой коллизии НЕ трогаем: у пака он свой, и hitscan оружия (mask 0b111)
	# должен вести себя одинаково для дверей и стен карты.
	_home = position


func set_open(v: bool) -> void:
	if locked:
		v = false
	_target = 1.0 if v else 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# анимируем только долю открытия; позиция — следствие (см. _process),
	# иначе tween и _process тягали бы position в разные стороны.
	var span := maxf(absf(_target - opened), 0.05)
	_tween.tween_property(self, "opened", _target, open_time * span)


func is_open() -> bool:
	return opened > 0.85


## Вызывается из door.gd при входе игрока в радиус.
func toggle() -> void:
	set_open(not is_open())


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	var want := _home + distance * opened
	if position.distance_to(want) > 0.0005:
		position = position.lerp(want, minf(1.0, delta * 12.0))
