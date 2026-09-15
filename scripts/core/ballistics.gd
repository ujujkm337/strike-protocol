@tool
class_name Ballistics
extends RefCounted
## Чистая математика стрельбы. Никаких узлов — чтобы гонять юнит-тесты через
## `godot --headless -s tests/test_ballistics.gd` и чтобы КЛИЕНТ И СЕРВЕР
## считали урон абсолютно одинаково (один и тот же код = нет рассинхрона).
##
## ВАЖНО: урон считает ТОЛЬКО сервер. Клиент предсказывает визуально,
## сервер валидирует. Иначе — эим-хак за вечер.

const GRAVITY := 9.81
const MAX_ARMOR := 100.0

static func damage_base(dmg: float, dist_m: float, falloff_start: float, falloff_end: float, min_mult: float) -> float:
	## Линейный спад урона: 1.0 до falloff_start, min_mult на falloff_end и дальше.
	if dist_m <= falloff_start:
		return dmg
	if dist_m >= falloff_end:
		return dmg * min_mult
	var t := (dist_m - falloff_start) / maxf(falloff_end - falloff_start, 0.001)
	return dmg * lerpf(1.0, min_mult, t)


static func armor_damage(dmg: float, armor: float, armor_pen: float, helm_mult: float, has_helmet: bool) -> float:
	## Модификатор урона по броне. armor_pen 0..1, где 1 = полностью бронебойно.
	## При полной броне и pen=0.5 урон режется на 25% — близко к CS-модели.
	var pen := clampf(armor_pen, 0.0, 1.0)
	var armor_frac := clampf(armor / MAX_ARMOR, 0.0, 1.0)
	var ratio := 1.0 - armor_frac * (1.0 - pen) * 0.5
	var out := dmg * ratio
	if has_helmet:
		out *= helm_mult
	return out


static func hitmult(part: String) -> float:
	match part:
		"head": return 4.0
		"neck": return 1.33
		"chest": return 1.0
		"stomach": return 1.25
		"arm": return 1.0
		"leg": return 0.87
		_: return 1.0


static func spread_rad(base_spread_deg: float, movement_speed: float, max_speed: float, airborne: bool, crouching: bool, consecutive_shots: int, bloom_per_shot: float) -> float:
	## Мгновенный угловой разброс в РАДИАНАХ. base_spread_deg — «стой» в градусах.
	var base := maxf(base_spread_deg, 0.001)
	var move := base * (0.15 if crouching else 1.0)
	var mobility := movement_speed / maxf(max_speed, 0.001)
	var moving := base * mobility * (1.2 if crouching else 2.4)
	var air := base * 3.5 if airborne else 0.0
	var bloom := minf(float(consecutive_shots) * bloom_per_shot, 4.0) * base
	return deg_to_rad(move + moving + air + bloom)


static func recoil_step(pattern: PackedVector2Array, index: int, horizontal_bias: float, spray_decay: float) -> Vector2:
	## Скачок камеры на выстреле `index`. X = горизонталь, Y = вертикаль (подброс).
	## После конца паттерна спрай «дышит»: амплитуда гаснет до 0.25 — как в CS2.
	var n := pattern.size()
	if n == 0:
		return Vector2.ZERO
	var pen := 1.0
	if index >= n:
		pen = clampf(1.0 - float(index - n) * spray_decay, 0.25, 1.0)
	var v := pattern[index % n]
	return Vector2(v.x * pen * horizontal_bias, v.y * pen)


static func recover(accum: Vector2, speed: float, delta: float) -> Vector2:
	## Экспоненциальное восстановление прицела к нулю (стабильно при любом FPS).
	return accum * exp(-clampf(speed, 0.0, 1e3) * delta)


static func travel_time(dist_m: float, muzzle_velocity: float) -> float:
	if muzzle_velocity <= 0.0:
		return 0.0
	return dist_m / muzzle_velocity


static func drop_m(t: float) -> float:
	return 0.5 * GRAVITY * t * t
