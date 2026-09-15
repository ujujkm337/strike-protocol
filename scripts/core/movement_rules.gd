@tool
class_name MovementRules
extends RefCounted
## Чистые правила движения — без узлов, ради тестов и единой логики клиента
## с сервером (античит сверяет скорость и «автопрыжок» по этим же формулам).

const CS_UNITS_PER_METER := 51.0   # для перевода u/s <-> м/с при сверке с CS


static func speed_cap(max_speed: float, crouch: bool, weapon_mult: float, aiming: bool) -> float:
	var v := max_speed
	if crouch:
		v *= 0.52
	if aiming:
		v *= 0.72
	return v * clampf(weapon_mult, 0.5, 1.5)


static func accelerate(velocity: Vector3, input_dir: Vector2, speed_cap: float,
		accel: float, friction: float, delta: float, in_air: bool, move_angle_deg: float) -> Vector3:
	## Модель Quake-подобного трения: сначала гасим, потом разгоняем вдоль ввода.
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if in_air:
		if input_dir.length_squared() > 0.0001:
			var wish := _wish(input_dir, move_angle_deg) * speed_cap
			var cur_dot := h.dot(wish) / maxf(wish.length(), 0.0001)
			var add := clampf(accel * delta * speed_cap, 0.0, speed_cap - cur_dot)
			h += wish.normalized() * add
	else:
		if friction > 0.0:
			var speed := h.length()
			if speed > 0.0001:
				var drop := maxf(speed, 1.0) * friction * delta
				h = h.normalized() * maxf(speed - drop, 0.0)
		if input_dir.length_squared() > 0.0001:
			var wish2 := _wish(input_dir, move_angle_deg) * speed_cap
			var dv := wish2 - h
			h += dv.limit_length(accel * delta)
			h = h.limit_length(speed_cap)   # равновесие трения не должно съедать кап
	return Vector3(h.x, velocity.y, h.z)


static func _wish(input_dir: Vector2, move_angle_deg: float) -> Vector3:
	var a := deg_to_rad(move_angle_deg)
	var fwd := Vector3(-sin(a), 0.0, -cos(a))
	var right := Vector3(cos(a), 0.0, -sin(a))
	return (fwd * -input_dir.y + right * input_dir.x).normalized()


static func jump(velocity: Vector3, jump_vel: float) -> Vector3:
	## Без сохранения горизонтального импульса — как в CS (прыжок не ускоряет сам по себе).
	return Vector3(velocity.x, jump_vel, velocity.z)


static func can_bhop(_velocity: Vector3, _on_floor: bool) -> bool:
	## Явно выключено: серво-багхоп ломает античит-сверку и matchmaking.
	return false


static func stride_length(speed: float, cap: float, crouch: bool) -> float:
	## Метров между шагами: чем быстрее — тем длиннее шаг, в присяд короче.
	var norm := clampf(speed / maxf(cap, 0.001), 0.0, 1.4)
	return lerpf(1.05, 1.85, norm) * (0.8 if crouch else 1.0)


static func bob_amount(speed: float, cap: float) -> float:
	return clampf(speed / maxf(cap, 0.001), 0.0, 1.0)


static func bob_phase(phase: float, speed: float, delta: float, on_floor: bool) -> float:
	if not on_floor:
		return phase
	return fmod(phase + speed * 2.3 * delta, TAU)


static func bob_offset(phase: float, amount: float) -> float:
	## Вертикальное покачивание камеры, ~2.5 см максимум.
	return sin(phase * 2.0) * 0.025 * amount


static func max_allowed_speed(cap: float) -> float:
	## Серверный потолок для античита: чуть выше возможного, чтобы не ловить
	## ложных срабатываний на интерполяции.
	return cap * 1.35 + 1.0
