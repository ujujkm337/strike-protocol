extends Control
## Меню: hover-анимация кнопок, панель подключения, настройки в ConfigFile,
## переключение вкладок. 3D-фон опционален: без него меню живёт.

const SETTINGS_PATH := "user://strike_settings.cfg"
const ACCENT := Color(0.961, 0.651, 0.137)

@onready var menu: VBoxContainer = $Menu
@onready var join_panel: PanelContainer = $JoinPanel
@onready var status: Label = $Status
@onready var addr: LineEdit = $JoinPanel/JoinBox/Addr
@onready var port: LineEdit = $JoinPanel/JoinBox/Port
@onready var nick: LineEdit = $JoinPanel/JoinBox/Nick
@onready var backdrop_viewport: SubViewport = $Backdrop/World/Viewport

var _settings := ConfigFile.new()
var _hover_tweens: Dictionary = {}


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_load_settings()
	for c in menu.get_children():
		if c is Button:
			c.mouse_entered.connect(_on_hover.bind(c, true))
			c.mouse_exited.connect(_on_hover.bind(c, false))
			match c.name:
				"Quick": c.pressed.connect(_start_bench)
				"Bench": c.pressed.connect(_start_bench)
				"Server": c.pressed.connect(func(): _toggle_join(true))
				"Options": c.pressed.connect(func(): _toggle_join(false))
				"Quit": c.pressed.connect(func(): get_tree().quit())
	$JoinPanel/JoinBox/JoinRow/DoJoin.pressed.connect(_do_join)
	$JoinPanel/JoinBox/JoinRow/DoHost.pressed.connect(_do_host)
	$JoinPanel/JoinBox/JoinRow/JoinCancel.pressed.connect(func(): _toggle_join(false))
	join_panel.visible = false
	_intro()
	if backdrop_viewport:
		backdrop_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := backdrop_viewport.get_node_or_null("Cam")
		if cam: cam.current = true


func _process(delta: float) -> void:
	var cam := backdrop_viewport.get_node_or_null("Cam") if backdrop_viewport else null
	if cam:
		cam.global_position = Vector3(cos(Time.get_ticks_msec() * 0.00008) * 4.0, 1.7,
			sin(Time.get_ticks_msec() * 0.00008) * 4.0)
		cam.look_at(Vector3(0, 0.8, 0))


func _intro() -> void:
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.45)
	var i := 0.0
	for c in menu.get_children():
		if c is Button:
			c.modulate.a = 0.0
			c.position.x -= 26.0
			tw.tween_property(c, "modulate:a", 1.0, 0.3).set_delay(0.06 * i + 0.1)
			tw.tween_property(c, "position:x", c.position.x + 26.0, 0.35).set_delay(0.06 * i + 0.1)
			i += 1


func _on_hover(b: Button, on: bool) -> void:
	_sfx("ui_hover")
	var t: Tween = _hover_tweens.get(b)
	if t and t.is_valid():
		t.kill()
	t = create_tween()
	_hover_tweens[b] = t
	t.tween_property(b, "modulate", Color(1, 1, 1, 1) if on else Color(0.78, 0.8, 0.84, 1), 0.12)
	t.parallel().tween_property(b, "scale", Vector2(1.02, 1.0) if on else Vector2.ONE, 0.12)
	b.pivot_offset = b.size * 0.5


func _on_click(name: String) -> void:
	_sfx("ui_click")
	if name == "Quit":
		get_tree().quit()


func _toggle_join(v: bool) -> void:
	join_panel.visible = v
	menu.visible = not v
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
