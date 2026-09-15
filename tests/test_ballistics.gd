extends SceneTree
## Тот же набор чисел, что и tests/test_ballistics.py (зеркало формул).
## Запуск без монитора и без GPU:
##   godot --headless --path . -s tests/test_ballistics.gd
## В CI:  godot --headless --path . -s tests/test_ballistics.gd && echo OK

const BallisticsScript := preload("res://scripts/core/ballistics.gd")

var _ok := 0
var _fail := 0


func _chk(name: String, got: Variant, exp: Variant, eps := 0.0001) -> void:
	var good := false
	if got is float and exp is float:
		good = absf(got - exp) <= eps
	elif got is Array and exp is Array:
		# Godot типизирует литералы ([s0.x, s0.y] -> Array[float]), а эталон
		# может быть Array[int]. Сравниваем поэлементно с допуском.
		good = got.size() == exp.size()
		if good:
			for i in got.size():
				var a: Variant = got[i]
				var b: Variant = exp[i]
				if a is float or b is float:
					if absf(float(a) - float(b)) > eps:
						good = false
						break
				elif a != b:
					good = false
					break
	else:
		good = got == exp
	if good:
		_ok += 1
		print("PASS  %-46s got=%s" % [name, _fmt(got)])
	else:
		_fail += 1
		printerr("FAIL  %-46s got=%s exp=%s" % [name, _fmt(got), _fmt(exp)])


func _fmt(v: Variant) -> String:
	if v is float:
		return String.num(v, 4)
	if v is Array:
		var parts: Array[String] = []
		for x in v:
			parts.append(_fmt(x))
		return "[" + ", ".join(parts) + "]"
	return str(v)


func _init() -> void:
	var B := BallisticsScript

	# ---- урон по дистанции ----
	_chk("0м == базовый", B.damage_base(36.0, 0.0, 10.0, 40.0, 0.7), 36.0)
	_chk("25м середина спада", B.damage_base(36.0, 25.0, 10.0, 40.0, 0.7), 30.6)
	_chk("40м пол", B.damage_base(36.0, 40.0, 10.0, 40.0, 0.7), 25.2)
	_chk("100м не ниже пола", B.damage_base(36.0, 100.0, 10.0, 40.0, 0.7), 25.2)

	# ---- броня ----
	_chk("full armor + pen=1.0 => без реза", B.armor_damage(36.0, 100.0, 1.0, 4.0, false), 36.0)
	_chk("full armor + pen=0.5 => -25%", B.armor_damage(36.0, 100.0, 0.5, 4.0, false), 27.0)
	_chk("full armor + pen=0.0 => -50%", B.armor_damage(36.0, 100.0, 0.0, 4.0, false), 18.0)
	_chk("без брони => полный", B.armor_damage(36.0, 0.0, 0.0, 4.0, false), 36.0)
	_chk("хедшот x4", B.armor_damage(36.0, 0.0, 0.5, 4.0, true), 144.0)
	_chk("hitmult head", B.hitmult("head"), 4.0)
	_chk("hitmult leg", B.hitmult("leg"), 0.87)
	_chk("hitmult unknown", B.hitmult("tail"), 1.0)

	# ---- разброс ----
	_chk("стой == base (deg)", rad_to_deg(B.spread_rad(0.6, 0.0, 250.0, false, false, 0, 0.35)), 0.6)
	_chk("присед = 0.15*base", rad_to_deg(B.spread_rad(0.6, 0.0, 250.0, false, true, 0, 0.35)), 0.09)
	_chk("бег = 3.4x", rad_to_deg(B.spread_rad(0.6, 250.0, 250.0, false, false, 0, 0.35)), 2.04)
	_chk("прыжок = 4.5x", rad_to_deg(B.spread_rad(0.6, 0.0, 250.0, true, false, 0, 0.35)), 2.7)
	_chk("bloom cap", rad_to_deg(B.spread_rad(0.6, 0.0, 250.0, false, false, 99, 0.35)), 3.0)

	# ---- отдача ----
	var pat := PackedVector2Array([Vector2(0.6, 1.8), Vector2(1.1, 2.6), Vector2(0.4, 2.2),
		Vector2(-0.7, 1.9), Vector2(-1.3, 1.6), Vector2(-0.9, 1.5), Vector2(0.2, 1.4),
		Vector2(1.0, 1.2), Vector2(0.8, 1.0), Vector2(-0.4, 0.9)])
	var s0 := B.recoil_step(pat, 0, 1.0, 0.1)
	_chk("выстрел 0 == паттерн[0]", [s0.x, s0.y], [0.6, 1.8])
	var s200 := B.recoil_step(pat, 200, 1.0, 0.1)
	_chk("затухание не ниже 0.25", [s200.x, s200.y], [0.15, 0.45])
	var s2 := B.recoil_step(pat, 0, 2.0, 0.1)
	_chk("h_bias только по X", [s2.x, s2.y], [1.2, 1.8])
	_chk("пустой паттерн", B.recoil_step(PackedVector2Array(), 5, 1.0, 0.1), Vector2.ZERO)

	# ---- восстановление прицела ----
	var f := exp(-10.0 * (1.0 / 60.0))
	var rec := B.recover(Vector2(2.0, 5.0), 10.0, 1.0 / 60.0)
	_chk("recover 1 кадр X", rec.x, 2.0 * f)
	_chk("recover 1 кадр Y", rec.y, 5.0 * f)
	_chk("recover speed=0", B.recover(Vector2(2.0, 5.0), 0.0, 1.0 / 60.0), Vector2(2.0, 5.0))

	# ---- пуля ----
	_chk("travel 100м@715", B.travel_time(100.0, 715.0), 0.1399, 0.001)
	_chk("hitscan muzzle=0", B.travel_time(100.0, 0.0), 0.0)
	_chk("drop_m", B.drop_m(100.0 / 715.0), 0.0959, 0.001)

	print("\nИТОГ: %d passed, %d failed" % [_ok, _fail])
	quit(1 if _fail > 0 else 0)
