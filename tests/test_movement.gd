extends SceneTree
## Правила движения. Гоняются без GPU: godot --headless -s tests/test_movement.gd

const M := preload("res://scripts/core/movement_rules.gd")

var _ok := 0
var _fail := 0

func _chk(name: String, got: Variant, exp: Variant, eps := 0.0001) -> void:
	var good := false
	if (got is float or got is int) and (exp is float or exp is int):
		good = absf(float(got) - float(exp)) <= eps
	else:
		good = got == exp
	if good: _ok += 1; print("PASS  %-44s got=%s" % [name, String.num(float(got), 4)])
	else: _fail += 1; printerr("FAIL  %-44s got=%s exp=%s" % [name, got, exp])

func _sprint_at(frames: int, cap: float) -> float:
	var v := Vector3.ZERO
	for i in frames:
		v = M.accelerate(v, Vector2.UP, cap, 55.0, 5.0, 1.0/60.0, false, 0.0)
	return Vector2(v.x, v.z).length()


func _init() -> void:
	var cap: float = M.speed_cap(6.6, false, 1.0, false)
	_chk("кап стоя", cap, 6.6)
	_chk("кап присед = 0.52x", M.speed_cap(6.6, true, 1.0, false), 6.6 * 0.52)
	_chk("кап аим = 0.72x", M.speed_cap(6.6, false, 1.0, true), 6.6 * 0.72)
	_chk("присед+аим композится", M.speed_cap(6.6, true, 1.0, true), 6.6 * 0.52 * 0.72)
	_chk("тяжёлое оружие замедляет", M.speed_cap(6.6, false, 0.82, false), 6.6 * 0.82, 1e-6)

	# разгон из нуля сходится к капу и не превышает его
	var v := Vector3.ZERO
	for i in 240: v = M.accelerate(v, Vector2.UP, cap, 55.0, 5.0, 1.0/60.0, false, 0.0)
	_chk("разгон 4с -> кап", Vector2(v.x, v.z).length(), cap, 0.02)
	_chk("разгон 0.5с уже >80% капа", 1 if _sprint_at(30, cap) > cap * 0.8 else 0, 1)
	var over := 0
	for i in 600: v = M.accelerate(v, Vector2.UP, cap, 55.0, 5.0, 1.0/60.0, false, 0.0)
	_chk("не превышает кап (античит)", 1 if Vector2(v.x, v.z).length() <= cap * 1.02 else 0, 1)

	# трение гасит
	var d0 := Vector2(6.6, 0).length()
	var v2 := Vector3(6.6, 0, 0)
	for i in 60: v2 = M.accelerate(v2, Vector2.ZERO, cap, 55.0, 5.0, 1.0/60.0, false, 0.0)
	_chk("трение гасит за секунду", 1 if Vector2(v2.x, v2.z).length() < 0.05 else 0, 1)

	# air control: горизонталь не растёт сама по себе
	var va := M.accelerate(Vector3(6.6, 6.4, 0), Vector2.ZERO, cap, 12.0, 0.0, 1.0/60.0, true, 0.0)
	_chk("в воздухе без ввода скорость не растёт", 1 if Vector2(va.x, va.z).length() <= 6.6 + 1e-3 else 0, 1)
	_chk("гравитацию не трогаем", va.y, 6.4)

	# прыжок не добавляет ускорения (не bhop)
	var j := M.jump(Vector3(6.6, 0, 0), 6.4)
	_chk("jump сохраняет горизонталь", Vector2(j.x, j.z).length(), 6.6)
	_chk("jump ставит вертикаль", j.y, 6.4)
	_chk("bhop запрещён", 1 if M.can_bhop(j, false) == false else 0, 1)

	# шаг/покачивание
	_chk("stride растёт со скоростью", 1 if M.stride_length(6.6, cap, false) > M.stride_length(1.0, cap, false) else 0, 1)
	_chk("присед укорачивает шаг", M.stride_length(6.6, cap, true) / M.stride_length(6.6, cap, false), 0.8)
	_chk("bob=0 стоя", M.bob_amount(0.0, cap), 0.0)
	_chk("bob=1 на капе", M.bob_amount(6.6, cap), 1.0)
	_chk("bob амплитуда <= 2.5см", 1 if absf(M.bob_offset(1.2, 1.0)) <= 0.025001 else 0, 1)
	_chk("фаза в [0,TAU)", 1 if M.bob_phase(6.0, 6.6, 1/60.0, true) < TAU else 0, 1)
	_chk("фаза стоит в воздухе", M.bob_phase(3.0, 6.6, 1/60.0, false), 3.0)
	_chk("античит-потолок", M.max_allowed_speed(6.6), 6.6 * 1.35 + 1.0)

	print("\nИТОГ: %d passed, %d failed" % [_ok, _fail])
	quit(1 if _fail > 0 else 0)
