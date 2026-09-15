extends Node
## Шина + генерация/импорт SFX (в т.ч. сгенерированных ElevenLabs).

const BUSES := ["Master", "Weapons", "Footsteps", "Ambience", "UI", "Voice"]

var sfx_cache := {}
## Для живого замера (tests/live_autopilot.gd): какой путь реально разрешился
## последним. Без этого шаги/выстрелы «работали» бы молча, и тест проверял бы
## заглушку, а не этот код.
var last_played: String = ""
var play_count := 0


func _ready() -> void:
	_ensure_buses()


func _ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
	if BUSES.size():
		AudioServer.set_bus_send(AudioServer.get_bus_index("Weapons"), "Master")
		AudioServer.set_bus_send(AudioServer.get_bus_index("Footsteps"), "Master")
		AudioServer.set_bus_send(AudioServer.get_bus_index("Ambience"), "Master")
		AudioServer.set_bus_send(AudioServer.get_bus_index("UI"), "Master")
		AudioServer.set_bus_send(AudioServer.get_bus_index("Voice"), "Master")


func play_sfx(path: String, bus := "Weapons", volume_db := 0.0, pitch_jitter := 0.06) -> void:
	last_played = path
	play_count += 1
	if not ResourceLoader.exists(path):
		push_warning("нет файла звука: " + path)
		return
	if not sfx_cache.has(path):
		sfx_cache[path] = load(path)
	var node := AudioStreamPlayer.new()
	node.stream = sfx_cache[path]
	node.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
	node.volume_db = volume_db
	if pitch_jitter > 0.0:
		node.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	node.finished.connect(node.queue_free)
	add_child(node)
	node.play()


func footsteps(surface: String, is_left := true, volume_db := 0.0) -> void:
	## Шаги генерировались парой l/r (step_concrete_l / _r), а для части
	## поверхностей есть только общий файл (step_gravel) — поэтому сначала пробуем
	## пару, потом одиночный файл. Раньше путь собирался с .ogg, файлов .mp3:
	## шаги были тихими всю игру, а в лог сыпалось push_warning каждый шаг.
	var side := "_l" if is_left else "_r"
	var paired := "res://assets/audio/fx/step_%s%s.mp3" % [surface, side]
	if not ResourceLoader.exists(paired):
		paired = "res://assets/audio/fx/step_%s.mp3" % surface
	if not ResourceLoader.exists(paired):
		paired = "res://assets/audio/fx/step_concrete_l.mp3"
	play_sfx(paired, "Footsteps", -6.0 + volume_db, 0.12)


func weapon_sound(weapon_id: String, kind: String) -> void:
	## id оружия != имя файла звука (m4a1s стреляет семплом guns_m4a1).
	var w := weapon_id
	if not ResourceLoader.exists("res://assets/audio/fx/guns_%s.mp3" % w):
		for alt in [w.trim_suffix("s"), "ak47"]:
			if ResourceLoader.exists("res://assets/audio/fx/guns_%s.mp3" % alt):
				w = alt
				break
	play_sfx("res://assets/audio/fx/guns_%s.mp3" % [w], "Weapons")
