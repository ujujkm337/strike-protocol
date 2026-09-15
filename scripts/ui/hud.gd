extends CanvasLayer
## Минимальный боевой оверлей: прицел, патроны, подсказка про захват мыши.
## Смысл не в красоте, а в том, чтобы игрок (и headless-тест) видел: ввод живой
## или нет. Тест проверяет, что имена оружия/патронов заполнились — это значит,
## что HUD нашёл Weapon, а значит цепочка сцена→игрок→камера→оружие цела.

var _ammo: Label
var _weapon_name: Label
var _mouse_hint: Label
var _hint: Label
var _weapon: Node = null
var _flash := 0.0

const WEAPON_PATHS := [
	^"../Player/Head/Camera3D/Weapon", ^"../Player/Head/Camera/Weapon",
	^"Player/Head/Camera3D/Weapon", ^"Player/Head/Camera/Weapon",
]


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_weapon = _find(WEAPON_PATHS)
	if _weapon == null:
		_weapon = get_tree().get_first_node_in_group("weapon")
	if _weapon != null:
		if _weapon.has_signal("ammo_changed"):
			_weapon.ammo_changed.connect(_on_ammo)
		if _weapon.has_signal("shot_fired"):
			_weapon.shot_fired.connect(_on_shot)
	_refresh()


## Путь к узлу камеры differs по картам (Camera / Camera3D), поэтому перебор.
func _find(paths: Array) -> Node:
	for cand in paths:
		var n := get_node_or_null(cand)
		if n != null:
			return n
	return null


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	for i in 2:
		var bar := ColorRect.new()
		bar.color = Color(0.85, 1.0, 0.85, 0.9)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size = Vector2(2, 14) if i == 0 else Vector2(14, 2)
		bar.position = Vector2(-1, -7) if i == 0 else Vector2(-7, -1)
		bar.set_anchors_preset(Control.PRESET_CENTER)
		root.add_child(bar)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 24.0
	box.offset_bottom = -22.0
	box.offset_top = -96.0
	box.add_theme_constant_override("separation", 2)
	root.add_child(box)

	_weapon_name = Label.new()
	_weapon_name.text = "—"
	_weapon_name.add_theme_font_size_override("font_size", 22)
	_weapon_name.add_theme_color_override("font_color", Color(1, 0.82, 0.35))
	box.add_child(_weapon_name)

	_ammo = Label.new()
	_ammo.text = "— / —"
	_ammo.add_theme_font_size_override("font_size", 34)
	box.add_child(_ammo)

	_hint = Label.new()
	_hint.text = "клик по экрану — захватить мышь · WASD ход · Shift бег · Ctrl присесть · ЛКМ огонь · R перезарядка · Esc мышь"
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -124.0
	_hint.offset_bottom = -104.0
	_hint.offset_left = 24.0
	root.add_child(_hint)

	_mouse_hint = Label.new()
	_mouse_hint.add_theme_font_size_override("font_size", 14)
	_mouse_hint.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
	_mouse_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mouse_hint.offset_top = 64.0
	root.add_child(_mouse_hint)


func _process(delta: float) -> void:
	var captured: bool = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	_mouse_hint.text = "" if captured else "МЫШЬ НЕ ЗАХВАЧЕНА — кликни по игре"
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		_weapon_name.modulate.a = 0.6 + 0.4 * _flash


func _unhandled_input(e: InputEvent) -> void:
	## В браузере pointer lock теряется при любом клике мимо канваса (и при alt-tab),
	## а без захвата мышь не крутит голову. Возвращаем по клику; на WASD — тоже,
	## потому что в iframe клик иногда до канваса не доходит, а клавиши приходят.
	var left_click := e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
			and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	var moving := e is InputEventKey and (e as InputEventKey).pressed
	if (left_click or moving) and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_shot(_o: Vector3, _d: Vector3, _w: Resource) -> void:
	_flash = 1.0


func _on_ammo(mag: int, reserve: int) -> void:
	if _ammo:
		_ammo.text = "%d / %d" % [mag, reserve]


func _refresh() -> void:
	if _weapon == null:
		_weapon_name.text = "оружие не найдено"
		return
	var d = _weapon.get("data")
	if d != null:
		_weapon_name.text = String(d.display_name)
	_ammo.text = "%d / %d" % [int(_weapon.get("mag")), int(_weapon.get("reserve"))]
