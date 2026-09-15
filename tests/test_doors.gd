extends SceneTree
## Проверка починенных дверей CC0-пака. В архиве пака лежали только .uid-файлы
## скриптов (door.gd/door_body.gd отсутствовали), а door_sound.ogg — в корне пака
## вместо doors/sounds/. Итог: обе сцену дверей не грузились.
##
## Тест не пересобирает логику, а гоняет живые сцены: инстанцирует door_single и
## door_double, подсовывает «игрока» в группу player рядом и_far'ом, и смотрит,
## что створки УЕХАЛИ на distance, а AudioStreamPlayer3D получил валидный stream.

const SINGLE := "res://addons/quaternius-modular-scifi-pack/doors/door_single.tscn"
const DOUBLE := "res://addons/quaternius-modular-scifi-pack/doors/door_double.tscn"
const NEAR := Vector3(1.0, 1.0, 0.0)
const FAR := Vector3(40.0, 1.0, 0.0)

## Тайминги — В СЕКУНДАХ, а не в кадрах: headless-прогон гонит fps «сколько
## успеет» (замерено: 70 кадров = 0.3 с вместо 1.17 с), и на кадрах тест то падал,
## то проходил в зависимости от загрузки CPU.
const T_SPAWN := 0.2
const T_CLOSED_1 := 0.6
const T_OPEN := 2.4          # open_time 0.7 + запас
const T_CLOSED_2 := 6.5      # auto_close_after 2.5 + ход назад

var _t := 0.0
var _fails: Array[String] = []
var _root: Node3D
var _player: Node3D
var _stage := 0
var _snap := {}


func _initialize() -> void:
	_root = Node3D.new()
	get_root().add_child(_root)
	_player = Node3D.new()
	_player.name = "FakePlayer"
	_player.add_to_group("player")
	_root.add_child(_player)
	# глобальные координаты НЕ ставим в _initialize: там ещё нет дерева, и даже
	# сеттер global_position читает get_global_transform ->
	# «Condition "!is_inside_tree()" ... Returning: Transform3D()» (проверено).
	# Все позиции — из _process (NEAR/FAR ниже по стадиям).


func _process(delta: float) -> bool:
	_t += delta
	match _stage:
		0:
			if _t >= T_SPAWN:
				_spawn(SINGLE, "single")
				_spawn(DOUBLE, "double")
				_player.global_position = FAR
				_stage = 1
		1:
			if _t >= T_CLOSED_1:
				_check_closed()
				_player.global_position = NEAR
				_stage = 2
		2:
			if _t >= T_OPEN:
				_check_open()
				_player.global_position = FAR
				_stage = 3
		3:
			if _t >= T_CLOSED_2:
				_check_closed()
				_report()
				_stage = 4
				return true
	return false


func _spawn(path: String, tag: String) -> void:
	var ps: PackedScene = load(path)
	if ps == null:
		_fails.append("%s: сцена не грузится (было: нет door.gd/door_body.gd)" % tag)
		return
	var inst := ps.instantiate()
	inst.name = "Door_" + tag
	_root.add_child(inst)
	# оба проёма — в радиусе срабатывания от NEAR (иначе «двойная дверь не
	# открывается» — это не баг кода, а баг теста: расстояние 8 м > 3.2 м)
	inst.global_position = Vector3(0, 0, 0) if tag == "single" else Vector3(0, 0, 2)
	_snap[tag] = {"node": inst, "home": _bodies_positions(inst)}
	var sound := inst.get_node_or_null("DoorSound") as AudioStreamPlayer3D
	if sound == null:
		_fails.append("%s: нет DoorSound (в паке он смотрел на doors/sounds/door_sound.ogg, файла там не было)" % tag)
	elif sound.stream == null:
		_fails.append("%s: DoorSound.stream == null — звук не импортирован" % tag)


func _bodies_of(inst: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in inst.get_children():
		if c.is_in_group("door"):
			out.append(c)
	return out


func _bodies_positions(inst: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for b in _bodies_of(inst):
		out.append(b.position)
	return out


func _check_closed() -> void:
	for tag in _snap.keys():
		var inst: Node = _snap[tag]["node"]
		var closed: Array[Vector3] = _snap[tag]["home"]
		var now := _bodies_positions(inst)
		for i in now.size():
			if now[i].distance_to(closed[i]) > 0.05:
				_fails.append("%s[%d]: створка смещена на %.2f в закрытом состоянии" % [
					tag, i, now[i].distance_to(closed[i])])


func _check_open() -> void:
	for tag in ["single", "double"]:
		if not _snap.has(tag):
			continue
		var inst: Node = _snap[tag]["node"]
		var bodies := _bodies_of(inst)
		if bodies.is_empty():
			_fails.append("%s: детей в группе 'door' нет - двигать нечем" % tag)
			continue
		var home: Array[Vector3] = _snap[tag]["home"]
		var now := _bodies_positions(inst)
		var total := 0.0
		for i in mini(bodies.size(), home.size()):
			total += now[i].distance_to(home[i])
		var st := "?"
		if bodies[0].has_method("is_open"):
			st = str(bodies[0].call("is_open"))
		print("  замер %s: суммарное смещение створок = %.2f м (открыты=%s)" % [tag, total, st])
		if total < 1.0:
			_fails.append("%s: игрок в 1 м, а створки не открылись (смещение %.2f)" % [tag, total])


func _report() -> void:
	if _fails.is_empty():
		print("ИТОГ: PASS — двери грузятся, открываются по подходу и закрываются")
		quit(0)
	else:
		print("ИТОГ: FAIL (%d)" % _fails.size())
		for f in _fails:
			print("   - " + f)
		quit(1)
