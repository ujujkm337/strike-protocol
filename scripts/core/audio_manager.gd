extends Node
## Шина + генерация/импорт SFX (в т.ч. сгенерированных ElevenLabs).

const BUSES := ["Master", "Weapons", "Footsteps", "Ambience", "UI", "Voice"]

var sfx_cache := {}


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


func footsteps(surface: String) -> void:
	play_sfx("res://assets/audio/fx/step_%s.ogg" % surface, "Footsteps", -4.0)


func weapon_sound(weapon_id: String, kind: String) -> void:
	play_sfx("res://assets/audio/fx/%s_%s.ogg" % [weapon_id, kind], "Weapons")
