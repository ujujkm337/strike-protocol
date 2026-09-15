extends Node
## АВТОПИЛОТ ЖИВОГО ЗАМЕРА. Запускается только вместе с map-сценой как main_scene
## (см. tools/run_live.sh) — только там физика шагает по-настоящему и отработали
## все call_deferred.
##
## ВАЖНО ПРО ХАРНЕС: в headless-прогоне global_position детей обновляется с лагом
## на кадр (замерено: при Head.position.y=0.82 camera.global_position показывал
## координаты ТЕЛА). Поэтому позиции глаз считаем явно через to_global(), а не
## читаем global_position — иначе тест «видит» то, чего движок ещё не пересчитал.

const SETTLE := 110     # ~1.8 с: спавн 1.2 + падение + stabilized
const WALK := 45

var _phase := 0
var _f := 0
var _p: CharacterBody3D
var _fails: Array[String] = []
var _before := Vector3.ZERO
var _eye_before := 0.0


func _ready() -> void:
	await get_tree().physics_frame
	_p = get_tree().get_first_node_in_group("player")
	if _p == null:
		_die(["группа player пуста — на Player нет скрипта/группы"])
		return
	_phase = 1


func _physics_process(_d: float) -> void:
	_f += 1
	match _phase:
		1:
			if _f >= SETTLE:
				_measure_start()
		2:
			Input.action_press("move_forward")
			if _f >= SETTLE + WALK:
				Input.action_release("move_forward")
				_phase = 3
		3:
			if _f >= SETTLE + WALK + 10:
				_measure_walk()
				_phase = 4
		4:
			Input.action_press("crouch")
			if _f >= SETTLE + WALK + 16:
				Input.action_release("crouch")
				_phase = 5
		5:
			if _f >= SETTLE + WALK + 26:
				_measure_crouch()
				_report()


func _cam() -> Camera3D:
	var head := _p.get_node_or_null("Head") as Node3D
	if head == null:
		return null
	return head.get_node_or_null("Camera3D") as Camera3D


## Позиция глаз БЕЗ лага обновления global_position.
func _eye_pos() -> Vector3:
	var head := _p.get_node_or_null("Head") as Node3D
	if head == null:
		return _p.global_position
	return head.to_global(Vector3.ZERO)


func _measure_start() -> void:
	if _p.get_script() == null:
		_fails.append("на Player нет script= — игрок немой")
	var cam := _cam()
	if cam == null:
		_fails.append("нет Head/Camera3D — обзора нет")
		_phase = 99
		return
	if not _p.is_on_floor():
		_fails.append("через %.1f с игрок не на полу (vel.y=%.2f) — провал сквозь пол" % [SETTLE / 60.0, _p.velocity.y])
	if absf(_p.velocity.y) > 0.8:
		_fails.append("вертикальная скорость не погашена: %.2f" % _p.velocity.y)
	if cam.rotation_degrees.length() > 0.01:
		_fails.append("у камеры ненулевой локальный поворот: %s (им владеет контроллер)" % cam.rotation_degrees)

	# ноги против опоры: низ капсулы = origin + shape.y - height/2
	var space: PhysicsDirectSpaceState3D = _p.get_world_3d().direct_space_state
	var stand := _p.get_node_or_null("Stand") as CollisionShape3D
	if stand == null:
		_fails.append("нет Stand прямым ребёнком Player")
		_phase = 99
		return
	var half: float = (stand.shape as CapsuleShape3D).height * 0.5
	var from := _p.global_position + Vector3.UP * 3.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0)
	q.exclude = [_p.get_rid()]
	q.collide_with_areas = false
	var g: Dictionary = space.intersect_ray(q)
	if g.is_empty():
		_fails.append("под игроком нет опоры в 12 м")
	else:
		var gp: Vector3 = g["position"]
		var gap: float = (_p.global_position.y + stand.position.y - half) - float(gp.y)
		print("  замер: опора y=%.2f | низ капсулы y=%.2f | зазор %+.3f | глаза y=%.2f | origin y=%.3f" % [
			gp.y, _p.global_position.y + stand.position.y - half, gap, _eye_pos().y, _p.global_position.y])
		if absf(gap) > 0.2:
			_fails.append("зазор ног %+.3f м — провал или подвешивание" % gap)

	# глаза: высота над полом = 1.72 по спецификации
	var eye_above_origin: float = _eye_pos().y - _p.global_position.y
	if absf(eye_above_origin - float(_p.eye_height_stand)) > 0.08:
		_fails.append("Head на %.2f над началом тела, eye_height_stand=%.2f — конвенции разъехались" % [
			eye_above_origin, _p.eye_height_stand])

	# ориентация спавна: лицом к центру карты
	var fwd: Vector3 = -_p.global_transform.basis.z
	var to_c := Vector3.ZERO - _p.global_position
	var horiz := Vector3(to_c.x, 0.0, to_c.z).normalized()
	var dotf: float = fwd.normalized().dot(horiz)
	print("  замер: dot(взгляд, к центру)=%.2f | yaw=%.1f°" % [dotf, rad_to_deg(_p.rotation.y)])
	if dotf < 0.6:
		_fails.append("спавн смотрит от центра (dot=%.2f) — перед игроком стена" % dotf)

	# объём у глаз свободен (иначе — чёрная полоса через экран)
	var qs := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	qs.shape = sph
	qs.transform = Transform3D(Basis.IDENTITY, _eye_pos())
	qs.collide_with_bodies = true
	qs.collide_with_areas = false
	qs.exclude = [_p.get_rid()]
	var inside: Array[Dictionary] = space.intersect_shape(qs, 4)
	if not inside.is_empty():
		var names: Array[String] = []
		for h in inside:
			var c: Node = h["collider"]
			names.append(c.name if c else "?")
		_fails.append("глаза ВНУТРИ ГЕОМЕТРИИ: %s" % ", ".join(names))

	# оружие связано со стрелком
	var weapon: Node = cam.get_node_or_null("Weapon")
	if weapon == null:
		_fails.append("нет Weapon под камерой")
	else:
		if weapon.player_body == null:
			_fails.append("weapon.player_body == null — hitscan не исключит стрелка")
		if weapon.camera == null:
			_fails.append("weapon.camera == null")

	# HUD показывает оружие
	var hud := _p.get_parent().get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		_fails.append("в карте нет HUD")
	else:
		var wn: Label = hud._weapon_name
		if wn.text == "—" or wn.text == "":
			_fails.append("HUD не знает оружие — цепочка HUD→Weapon порвана")
		else:
			print("  замер: HUD оружие='%s' патроны='%s'" % [wn.text, hud._ammo.text])
	_before = _p.global_position
	_eye_before = _eye_pos().y
	_phase = 2


func _measure_walk() -> void:
	var moved: float = _p.global_position.distance_to(_before)
	print("  замер: сдвиг за %d кадров вперёд = %.2f м" % [WALK, moved])
	if moved < 1.0:
		_fails.append("WASD не двигает игрока (сдвиг %.2f м)" % moved)
	if not _p.is_on_floor():
		_fails.append("после ходьбы игрок не на полу")


func _measure_crouch() -> void:
	if not _p.crouching:
		_fails.append("Ctrl не включает присед")
	else:
		var e := _eye_pos().y
		print("  замер: присед, глаза %.2f -> %.2f" % [_eye_before, e])
		if e > _eye_before - 0.15:
			_fails.append("в приседе глаза не опустились: %.2f -> %.2f" % [_eye_before, e])


func _report() -> void:
	if _fails.is_empty():
		print("LIVE ИТОГ: PASS — стоит на полу, ходит, смотрит к центру, HUD живой")
	else:
		print("LIVE ИТОГ: FAIL (%d)" % _fails.size())
		for f in _fails:
			print("   - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _die(msgs: Array[String]) -> void:
	print("LIVE ИТОГ: FAIL")
	for m in msgs:
		print("   - " + m)
	get_tree().quit(1)
