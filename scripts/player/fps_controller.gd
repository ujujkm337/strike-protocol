class_name FPSController
extends CharacterBody3D
## Движение в духе competitive-шутера: ускорение/торможение, трение, air-control,
## присед, прыжок без авто-компенса. Вся математика — через MovementRules, чтобы
## тесты гонялись headless без сцены.

signal landed(impact_speed: float)
signal crouch_changed(crouching: bool)
signal footstep(surface: String, is_left: bool)

const MovementRules := preload("res://scripts/core/movement_rules.gd")

@export var max_speed := 6.6                # ~250 u/s в CS-терминах
@export var acceleration := 55.0
@export var air_acceleration := 12.0
@export var friction := 5.0   # при 9.0 равновесие трения/разгона = 6.02 < капа 6.6 -> недобор скорости
@export var gravity := 20.0
@export var jump_velocity := 6.4
## Высоты глаз отсчитываются ОТ ЦЕНТРА КАПСУЛЫ: при опоре движок ставит начало
## координат тела в центр активной формы (замерено: ноги=пол => y=0.95). Поэтому
## Head стоит на +0.82, а не +1.72, а формы коллизии обязаны висеть в нуле тела.
@export var eye_height_stand := 0.82
@export var eye_height_crouch := 0.20
@export var mouse_sensitivity := 0.0022
@export var min_fov := 60.0
@export var max_fov := 110.0
@export var spawn_path: NodePath  # Marker3D: если задан — встать в него на старте

@onready var head: Node3D = get_node_or_null(^"Head")
@onready var camera: Camera3D = _find_camera()


func _find_camera() -> Camera3D:
	## Ищем и по имени, и по типу: карты делают разные люди, и «Камера не нашлась»
	## из-за переименования узла — это чёрный экран, а не сообщение об ошибке.
	for cand in [^"Head/Camera", ^"Head/Camera3D"]:
		var n := get_node_or_null(cand)
		if n is Camera3D:
			return n as Camera3D
	if head:
		for ch in head.get_children():
			if ch is Camera3D:
				return ch as Camera3D
	var found := get_tree().get_first_node_in_group("player_camera")
	return found as Camera3D

var crouching := false
var aim_locked := false
var move_speed_mult := 1.0
var _input_dir := Vector2.ZERO
var _last_land_y := 0.0
var _step_acc := 0.0
var _step_left := true
var _bob_phase := 0.0
var _bob_amount := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _pitch_limit := deg_to_rad(88.0)
var _no_floor_time := 0.0
var _mouse_dx := 0.0
var _mouse_dy := 0.0
var _last_motion_rel := Vector2.INF
var _last_motion_pos := Vector2.INF


func _ready() -> void:
	# Порядок важен: сначала мышь. Если camera == null (карта без Head/Camera),
	# падение на первой строке лишало бы игрока и захвата мыши, и current-камеры.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if camera:
		camera.current = true
		camera.near = 0.02
		camera.fov = clampf(90.0, min_fov, max_fov)
	else:
		push_warning("FPSController: Camera3D не найден ни по пути, ни среди детей Head — обзора не будет")
	_align_to_spawn.call_deferred()
	_apply_look()


func _align_to_spawn() -> void:
	## Стартовая позиция в .tscn — только для редактирования. В рантайме встаём в
	## маркер: он задаёт и место, и куда смотреть (как в CS — спавн «лицом» к карте).
	## deferred, потому что вызов идёт до _ready дочерних узлов (camera/head).
	if spawn_path.is_empty():
		return
	var m := get_node_or_null(spawn_path) as Node3D
	if m == null:
		push_warning("FPSController: спавн-маркер '%s' не найден — стою где стою" % spawn_path)
		return
	global_position = m.global_position
	# направление маркера: -Z его трансформа
	var dir := -m.global_transform.basis.z
	if absf(dir.x) > 0.01 or absf(dir.z) > 0.01:
		# ЗАМЕРЕНО (run_live.sh): при yaw=45° узел смотрит на (+0.71,0,-0.71),
		# т.е. dir=(sin yaw,0,-cos yaw) => yaw = atan2(dir.x, -dir.z).
		_yaw = atan2(dir.x, -dir.z)
		rotation.y = _yaw
	_apply_look()


func _apply_look() -> void:
	## Единственный владелец ориентации. Модель закреплена замером (tests/run_live.sh):
	##   player.rotation.y = _yaw, head.rotation.x = -_pitch, камера НЕ поворачивается.
	## Проверено: yaw=45°, pitch=0 => -Z = (+0.71, 0, -0.71); pitch>0 => взгляд вверх.
	## Всё, что я здесь пробовал раньше (base -90 в камере, look_at, сложение питча),
	## давало либо взгляд в пол, либо накопление поворота до -5156°.
	rotation.y = _yaw
	if head:
		head.rotation.x = -_pitch


func _unhandled_input(e: InputEvent) -> void:
	## Событие мыши ТОЛЬКО накапливаем. Раньше поворот применялся прямо здесь, и
	## любое перепол/повтор события (в headless-прогоне — каждый кадр) умножал
	## питч: 20px давали +88° вместо +2.5°. Расход — в _physics_process, ровно раз
	## на кадр, как в нормальных шутерах.
	## Клавиши тут не читаем: e.is_action_pressed() есть только у InputEventKey.
	if e is InputEventMouseMotion and not aim_locked:
		var mm := e as InputEventMouseMotion
		# Защита от переигрывания одного и того же события (в headless-прогоне
		# viewport отдаёт его каждый кадр): тот же relative при том же position —
		# это повтор, игнорируем. В живой игре position меняется всегда.
		if mm.relative == _last_motion_rel and mm.global_position == _last_motion_pos:
			return
		_last_motion_pos = mm.global_position
		_last_motion_rel = mm.relative
		_mouse_dx += mm.relative.x
		_mouse_dy += mm.relative.y


func _read_keys() -> void:
	## Клавиши читаем в _physics_process через Input.*_just_*. В _unhandled_input
	## этого делать нельзя: там событие приходит на каждое движение мыши, и
	## «toggle» срабатывал десятки раз подряд.
	if Input.is_action_just_pressed("crouch"):
		_try_crouch(not crouching)

	if Input.is_action_just_pressed("menu"):
		toggle_pause()


func _physics_process(delta: float) -> void:
	_read_keys()
	if absf(_mouse_dx) > 0.0001 or absf(_mouse_dy) > 0.0001:
		_yaw += _mouse_dx * mouse_sensitivity
		_pitch = clampf(_pitch - _mouse_dy * mouse_sensitivity, -_pitch_limit, _pitch_limit)
		_mouse_dx = 0.0
		_mouse_dy = 0.0
		_apply_look()
	_input_dir = Input.get_vector("move_left", "move_right", "move_back", "move_forward")

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity = MovementRules.jump(velocity, jump_velocity)

	var speed_cap := MovementRules.speed_cap(max_speed, crouching, move_speed_mult, aim_locked)
	var accel := air_acceleration if not is_on_floor() else acceleration
	var friction_now := friction if is_on_floor() else 0.0
	velocity = MovementRules.accelerate(velocity, _input_dir, speed_cap, accel, friction_now, delta,
		not is_on_floor(), _move_direction_deg())

	move_and_slide()

	if is_on_floor():
		if _last_land_y < -4.0:
			landed.emit(-_last_land_y)
		_last_land_y = 0.0
		_tick_footsteps(delta, speed_cap)
	else:
		_last_land_y = velocity.y
	_bob_amount = MovementRules.bob_amount(velocity.length(), speed_cap)
	_bob_phase = MovementRules.bob_phase(_bob_phase, velocity.length(), delta, is_on_floor())
	if head:
		head.position.y = lerpf(head.position.y, _eye_height(), 1.0 - exp(-16.0 * delta)) \
			+ MovementRules.bob_offset(_bob_phase, _bob_amount)
	_guard_above_floor(delta)


func _tick_footsteps(delta: float, cap: float) -> void:
	var v := Vector2(velocity.x, velocity.z).length()
	_step_acc += v * delta
	var stride := MovementRules.stride_length(v, cap, crouching)
	if _step_acc >= stride:
		_step_acc = 0.0
		_step_left = not _step_left
		footstep.emit(current_surface, _step_left)


func _move_direction_deg() -> float:
	return rad_to_deg(atan2(_input_dir.x, -_input_dir.y)) + rad_to_deg(rotation.y)


func _eye_height() -> float:
	return lerpf(eye_height_stand, eye_height_crouch, 1.0 if crouching else 0.0)


func _set_crouch(v: bool) -> void:
	crouching = v
	# стойка и присед — две разные CollisionShape3D, включаем нужную. ОБЕ висят в
	# нуле тела: PhysicsServer позиционирует body по ЦЕНТРУ активной формы, смещение
	# же формы он приresolve игнорирует — с оффсетом игрок при вставании проваливался.
	var shape := get_node_or_null(^"Crouch")
	var shape2 := get_node_or_null(^"Stand")
	if shape: shape.disabled = not v
	if shape2: shape2.disabled = v
	move_speed_mult = 0.52 if v else 1.0
	crouch_changed.emit(crouching)


func _try_crouch(v: bool) -> void:
	## Вставать можно только если для капсулы есть место: иначе игрок застревает под
	## низкими укрытиями. Пробуем «встать» через test_move с включённой Stand-формой и
	## откатываемся, если тело вошло бы в геометрию.
	if not v:
		var stand: CollisionShape3D = get_node_or_null(^"Stand") as CollisionShape3D
		var crouch: CollisionShape3D = get_node_or_null(^"Crouch") as CollisionShape3D
		if stand != null and crouch != null:
			stand.disabled = false
			crouch.disabled = true
			var blocked := test_move(global_transform, Vector3.ZERO)
			stand.disabled = true
			crouch.disabled = false
			if blocked:
				return
	_set_crouch(v)


func toggle_pause() -> void:
	var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)
	get_tree().paused = not captured


func set_fov(v: float) -> void:
	if camera:
		camera.fov = clampf(v, min_fov, max_fov)


var current_surface: String = "concrete"


func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	## Вызывается из weapon.gd. Отдача крутит КАМЕРУ, а не луч — игрок должен
	## сам «тянуть» прицел вниз, как в CS2.
	_pitch = clampf(_pitch + deg_to_rad(pitch_deg), -_pitch_limit, _pitch_limit)
	_yaw += deg_to_rad(yaw_deg)
	rotation.y = _yaw
	_apply_look()


func jitter_spread_rad(base_deg: float, shots: int, speed: float) -> float:
	return Ballistics.spread_rad(base_deg, speed, max_speed * 100.0, not is_on_floor(),
		crouching, shots, 0.35)


func _guard_above_floor(_dt: float) -> void:
	## Страховка от «экрана нет»: если глаза оказались внутри/под полом — камера
	## видит только заднюю грань полигонов, то есть чёрный кадр. Поднимаем голову на
	## гарантированные 0.9 м над поверхностью; если под ногами вообще ничего нет
	## (провалился под карту) — возвращаем тело на спавн.
	var from := global_position + Vector3.UP * 1.2
	var to := global_position + Vector3.DOWN * 4.0
	var q := PhysicsRayQueryParameters3D.create(from, to, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_no_floor_time += _dt
		if _no_floor_time > 1.0 and not spawn_path.is_empty():
			var m := get_node_or_null(spawn_path) as Node3D
			if m != null:
				global_position = m.global_position + Vector3.UP * 1.0
				velocity = Vector3.ZERO
				push_warning("FPSController: игрока унесло под карту — возвращаю на спавн")
			_no_floor_time = 0.0
		return
	_no_floor_time = 0.0
	var floor_top: float = (hit["position"] as Vector3).y
	var eye_world := (head.global_position.y if head else global_position.y + _eye_height())
	if eye_world < floor_top + 0.9 and head:
		head.position.y = floor_top + 0.9 - global_position.y
