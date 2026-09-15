extends Node3D
## Контроллер дверного проёма: объединяет створки (группа "door") и открывает их,
## когда игрок подошёл ближе trigger_radius. Скрипта не было в архиве пака
## (только door.gd.uid) — поэтому двери были статичными декорациями.

@export var trigger_radius := 3.2
@export var auto_close_after := 2.5      # 0 = остаются открытыми
@export var stay_open := false

var _bodies: Array[Node] = []
var _sound: AudioStreamPlayer3D = null
var _was_open := false
var _since_player_left := -1.0


func _ready() -> void:
	for c in get_children():
		if c.is_in_group("door"):
			_bodies.append(c)
	_sound = get_node_or_null("DoorSound") as AudioStreamPlayer3D
	if _bodies.is_empty():
		push_warning("door.gd: под контроллером нет детей в группе 'door' — дверь нечем двигать")


func _physics_process(delta: float) -> void:
	var near := _player_near()
	if near:
		_since_player_left = -1.0
		_set_all(true)
	elif _since_player_left >= 0.0:
		_since_player_left += delta
		if auto_close_after > 0.0 and _since_player_left >= auto_close_after:
			_set_all(false)
	else:
		# игрок никогда не подходил: держим закрытыми (иначе дверь «помнит» открытое
		# состояние после reload сцены)
		if not stay_open:
			_since_player_left = 0.0
			_set_all(false)


func _set_all(v: bool) -> void:
	for b in _bodies:
		if b.has_method("set_open"):
			b.set_open(v)
	if v != _was_open:
		_was_open = v
		if _sound and _sound.stream != null:
			# один сэмп на цикл «открыть/закрыть», как в исходном паке
			_sound.pitch_scale = 1.0 if v else 0.92
			_sound.play()


func toggle() -> void:
	_set_all(not (_bodies.size() > 0 and _bodies[0].has_method("is_open") and _bodies[0].is_open()))


func _player_near() -> bool:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return false
	return p.global_position.distance_to(global_position) <= trigger_radius
