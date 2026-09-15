extends Control
## Меню: hover-анимация кнопок, панель подключения, настройки в ConfigFile,
## переключатель качества графики, живой 3D-фон.
##
## Вёрстка специально на якорях + фикс. отступах, а не на «всё в VBox до
## offset_right = -420»: прошлая версия прижимала бренд и кнопки к нижнему краю
## во всю ширину экрана, и на 16:9 это выглядело сломанным (скриншот пользователя).

const SETTINGS_PATH := "user://strike_settings.cfg"
const ACCENT := Color(0.961, 0.651, 0.137)

@onready var menu: VBoxContainer = $MenuPanel/Menu
@onready var menu_panel: PanelContainer = $MenuPanel
@onready var join_panel: PanelContainer = $JoinPanel
@onready var status: Label = $Status
@onready var addr: LineEdit = $JoinPanel/JoinBox/Addr
@onready var port: LineEdit = $JoinPanel/JoinBox/Port
@onready var nick: LineEdit = $JoinPanel/JoinBox/Nick
@onready var gfx_button: Button = $MenuPanel/Menu/GfxMode
@onready var backdrop_viewport: SubViewport = $Backdrop/World/Viewport

var _settings := ConfigFile.new()
var _hover_tweens: Dictionary = {}


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_load_settings()
	for c in menu.get_children():
		if not (c is Button):
			continue
		var b := c as Button
		b.mouse_entered.connect(_on_hover.bind(b, true))
		b.mouse_exited.connect(_on_hover.bind(b, false))
		b.focus_mode = Control.FOCUS_NONE
		match b.name:
			"Quick": b.pressed.connect(_start_bench)
			"Bench": b.pressed.connect(_start_bench)
			"Server": b.pressed.connect(func(): _toggle_join(true))
			"Options": b.pressed.connect(func(): _toggle_join(false))
			"GfxMode": b.pressed.connect(_toggle_gfx)
			"Quit": b.pressed.connect(func(): get_tree().quit())
	$JoinPanel/JoinBox/JoinRow/DoJoin.pressed.connect(_do_join)
	$JoinPanel/JoinBox/JoinRow/DoHost.pressed.connect(_do_host)
	$JoinPanel/JoinBox/JoinRow/JoinCancel.pressed.connect(func(): _toggle_join(false))
	join_panel.visible = false
	_refresh_gfx_button()
	_intro()
	if backdrop_viewport:
		backdrop_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := backdrop_viewport.get_node_or_null("Cam") as Camera3D
		if cam:
			cam.current = true
			cam.environment = null


func _process(delta: float) -> void:
	if backdrop_viewport == null:
		return
	var cam := backdrop_viewport.get_node_or_null("Cam") as Camera3D
	if cam:
		var t := Time.get_ticks_msec() * 0.00008
		cam.global_position = Vector3(cos(t) * 3.4, 1.55 + sin(t * 2.0) * 0.12, sin(t) * 3.4)
		cam.look_at(Vector3(0, 0.75, 0), Vector3.UP)


func _intro() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.4)
	# Только прозрачность. раньше здесь ещё двигался position.x кнопок внутри
	# VBoxContainer — контейнер каждый кадр возвращает их на место, и строки дрожали.
	var i := 0.0
	for c in menu.get_children():
		if not (c is Control):
			continue
		var ctl := c as Control
		ctl.modulate.a = 0.0
		create_tween().tween_property(ctl, "modulate:a", 1.0, 0.28) \
			.set_delay(0.05 * i + 0.08)
		i += 1


func _on_hover(b: Button, on: bool) -> void:
	_sfx("ui_hover")
	b.pivot_offset = b.size * 0.5
	var t: Tween = _hover_tweens.get(b)
	if t and t.is_valid():
		t.kill()
	t = create_tween()
	_hover_tweens[b] = t
	t.tween_property(b, "modulate", Color(1, 1, 1, 1) if on else Color(0.82, 0.84, 0.88, 1), 0.12)
	t.parallel().tween_property(b, "scale", Vector2(1.015, 1.0) if on else Vector2.ONE, 0.12)


func _toggle_gfx() -> void:
	_sfx("ui_click")
	var boot := get_node_or_null("/root/Boot")
	if boot and boot.has_method("toggle_heavy"):
		boot.toggle_heavy()
	_refresh_gfx_button()
	status.text = "графика применится к текущей и следующей сцене"


func _refresh_gfx_button() -> void:
	if gfx_button == null:
		return
	var boot := get_node_or_null("/root/Boot")
	var heavy: bool = boot.heavy_effects_allowed() if boot else true
	gfx_button.text = "ГРАФИКА: ВЫСОКАЯ (SDFGI)" if heavy else "ГРАФИКА: СОВМЕСТИМАЯ"
	gfx_button.add_theme_color_override("font_color", ACCENT if not heavy else Color(0.86, 0.88, 0.92))


func _toggle_join(v: bool) -> void:
	join_panel.visible = v
	menu_panel.visible = not v
	if v:
		addr.grab_focus()


func _do_join() -> void:
	var a := addr.text.strip_edges()
	var p := port.text.strip_edges()
	if a.is_empty():
		status.text = "введите адрес сервера"
		_sfx("ui_error")
		return
	var net := get_node_or_null("/root/Net")
	var err: int = ERR_UNCONFIGURED
	if net: err = net.join(a, int(p) if p.is_valid_int() else 7777)
	if err == OK:
		status.text = "подключение к %s:%s…" % [a, p]
	else:
		status.text = "ошибка: %s" % error_string(err)
	_toggle_join(false)


func _do_host() -> void:
	var net := get_node_or_null("/root/Net")
	var err: int = ERR_UNCONFIGURED
	if net: err = net.host(7777, 16)
	status.text = "сервер поднят на :7777 (16 слотов)" if err == OK else "не удалось: %s" % error_string(err)
	_toggle_join(false)


func _start_bench() -> void:
	_save_settings()
	if ResourceLoader.exists("res://scenes/maps/bench.tscn"):
		get_tree().change_scene_to_file("res://scenes/maps/bench.tscn")
	else:
		status.text = "bench.tscn ещё не собран — шаг 4 плана"
		_sfx("ui_error")


func _load_settings() -> void:
	if _settings.load(SETTINGS_PATH) != OK:
		_settings.set_value("mouse", "sensitivity", 0.0022)
		_settings.set_value("view", "fov", 90.0)
		_settings.set_value("audio", "master_db", 0.0)


func _save_settings() -> void:
	_settings.save(SETTINGS_PATH)


func _sfx(sfx_name: String) -> void:
	var a := get_node_or_null("/root/AudioBus")
	if a and a.has_method("play_sfx"):
		a.play_sfx("res://assets/audio/fx/%s.mp3" % sfx_name, "UI", -10.0)
