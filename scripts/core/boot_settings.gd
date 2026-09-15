extends Node
## Автозагрузка BootSettings: подбор качества под GPU/платформу, «аварийный» режим
## и F3-оверлей. Появился после того, как сборка падала через ~10 с на Windows, а
## в браузере показывала чёрный экран при живом HUD: сцена несла SDFGI + volumetric
## fog + SSR + 4096-ю теневую карту + 6 теневых оммни-светей. На WebGL первые три
## не поддерживаются вообще, на слабом десктопном GPU тени — это таймаут драйвера.

const SETTINGS_PATH := "user://strike_gfx.cfg"

var safe_mode := false          # принудительно выключено: --safe
var high_mode := false          # принудительно включено: --high
var detected: String = "forward_plus"
var overlay: Control = null
var _overlay_on := false
var _applied_for: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a == "--safe":
			safe_mode = true
		elif a == "--high":
			high_mode = true
	detected = _detect_renderer()
	_load_pref()
	# первую попытку применяем сразу, дальше — на каждую смену сцены
	_apply_current_scene.call_deferred()
	get_tree().node_added.connect(_on_node_added)


func _detect_renderer() -> String:
	var api := RenderingServer.get_current_rendering_method()
	# web проверяем первым: в браузере DisplayServer тоже рапортует headless,
	# и проверка «headless» выше унесла бы веб в тяжёлый режим = чёрный экран.
	if OS.has_feature("web"):
		return "webgl"
	if api == "gl_compatibility":
		return "gl_compatibility"
	if DisplayServer.get_name() == "headless":
		return "headless"
	return api


## Используется и меню (переключатель), и оверлеем.
func heavy_effects_allowed() -> bool:
	if high_mode:
		return true
	if safe_mode:
		return false
	# WebGL/gl_compatibility: объёмный свет, SDFGI и SSR недоступны или убивают кадр
	return detected == "forward_plus" or detected == "mobile"


func _load_pref() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		var v: bool = cf.get_value("gfx", "safe", false)
		if v:
			safe_mode = true


func save_pref() -> void:
	var cf := ConfigFile.new()
	cf.set_value("gfx", "safe", safe_mode)
	cf.save(SETTINGS_PATH)


func toggle_heavy() -> void:
	safe_mode = heavy_effects_allowed()
	high_mode = false
	save_pref()
	_applied_for = ""     # заставим переприменить на следующем кадре
	_apply_current_scene()


func _on_node_added(n: Node) -> void:
	# WorldEnvironment приходит вместе с новой сценой
	if n is WorldEnvironment:
		_apply_environment((n as WorldEnvironment).environment)
	elif n is Node3D and n.name == "Lights":
		_apply_lights(n)


func _apply_current_scene() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var we := root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we != null:
		_apply_environment(we.environment)
	var lights := root.find_child("Lights", true, false)
	if lights != null:
		_apply_lights(lights)


func _apply_environment(env: Environment) -> void:
	if env == null:
		return
	var heavy := heavy_effects_allowed()
	env.sdfgi_enabled = heavy
	env.volumetric_fog_enabled = heavy
	env.ssr_enabled = heavy
	env.glow_enabled = heavy
	if not heavy:
		# без GI сцена иначе выглядит абсолютно чёрной: тянем засветку на прямом
		# свете + ambient, а автоэкспозицию закрываем, чтобы кадр не «слепло»
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_energy = 0.55
		env.ambient_light_color = Color(0.46, 0.5, 0.58, 1)
		# env.auto_exposure_* в 4.7 нет: экспозиция включена всегда,
		# поэтому при лёгком режиме просто не включаем glow и держим ambient.
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.075, 0.086, 0.105, 1)
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	else:
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.sdfgi_use_occlusion = false
		env.sdfgi_energy = 1.15
	env.glow_intensity = 0.35 if heavy else 0.0
	print("[gfx] renderer=%s heavy=%s sdfgi=%s fog=%s ssr=%s" % [
		detected, str(heavy), str(env.sdfgi_enabled), str(env.volumetric_fog_enabled), str(env.ssr_enabled)])


func _apply_lights(lights: Node) -> void:
	## Теневой бюджет. Раньше сцена несла 6 источников с тенями (5 кубатурных карт
	## плюс directional 4096) — на встроенном GPU это переполнение VRAM и зависание
	## драйвера через ~10 с после старта, т.е. ровно тот вылет .exe, о котором сообщал
	## пользователь. Теперь тень одна: солнце; оммни-светы остаются, но без теней.
	var heavy := heavy_effects_allowed()
	var shadowed := 0
	for c in lights.get_children():
		if not (c is Light3D):
			continue
		var l := c as Light3D
		if l is DirectionalLight3D:
			l.shadow_enabled = true
			l.directional_shadow_max_distance = 60.0 if heavy else 36.0
			l.directional_shadow_mode = 2      # ShadowParallel20Splits — стабильные границы
			continue
		var omni := l as OmniLight3D
		omni.shadow_enabled = heavy and shadowed < 1
		if omni.shadow_enabled:
			shadowed += 1
		omni.omni_range = 12.0
		# volume_enabled в рантайме read-only (объёмный свет включается только
		# в сцене/через переменные света) — назначать нельзя, будет SCRIPT ERROR.
		omni.distance_fade_enabled = true
		omni.distance_fade_begin = 26.0
		omni.distance_fade_length = 12.0
	# размер атласа позиционных теней — настройка проекта (project.godot), не узла


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).physical_keycode == KEY_F3:
		_overlay_on = not _overlay_on
		_refresh_overlay()


func _process(_d: float) -> void:
	if _overlay_on:
		_refresh_overlay()


func _refresh_overlay() -> void:
	if not _overlay_on:
		if overlay != null:
			overlay.visible = false
		return
	if overlay == null:
		_build_overlay()
	overlay.visible = true
	var info := "[gfx] renderer: %s | heavy: %s | safe: %s\n" % [detected, str(heavy_effects_allowed()), str(safe_mode)]
	info += "fps: %.1f\n" % Engine.get_frames_per_second()
	var p := get_tree().get_first_node_in_group("player")
	if p is CharacterBody3D:
		var b := p as CharacterBody3D
		info += "player y=%+.3f vel.y=%+.2f on_floor=%s crouch=%s\n" % [b.global_position.y, b.velocity.y, str(b.is_on_floor()), str(b.get("crouching"))]
		var head := b.get_node_or_null("Head")
		if head is Node3D:
			info += "eye y=%+.3f\n" % (head as Node3D).global_position.y
	var cs := get_tree().current_scene
	info += "scene: %s" % (cs.name if cs else "—")
	(overlay.get_node("Label") as Label).text = info


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.name = "GfxOverlay"
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(overlay)
	var l := Label.new()
	l.name = "Label"
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85, 0.95))
	l.set_anchors_preset(Control.PRESET_TOP_LEFT)
	l.position = Vector2(16, 12)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(l)
