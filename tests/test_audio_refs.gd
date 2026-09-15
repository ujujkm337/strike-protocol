extends SceneTree
## Проверка ссылочной целостности звука. Появилась после того, как три вещи
## оказались битыми одновременно и молча (ни одна из них не роняла игру):
##   * audio_manager.footsteps() собирал путь с .ogg, а файлы .mp3  -> шагов не было;
##   * weapon.gd брал guns_<id>.mp3, у m4a1s файла нет               -> тишина на M4;
##   * сигнал footstep вообще никто не слушал                        -> код мёртвый.
## Тест дёргает НАСТОЯЩИЕ функции (AudioManager.new().footsteps(), Weapon.audio_id()),
## а не пересобирает пути руками — иначе он проверял бы сам себя.

const FX_DIR := "res://assets/audio/fx/"
const AudioManager := preload("res://scripts/core/audio_manager.gd")
const WeaponScript := preload("res://scripts/player/weapon.gd")
const WeaponDataRes := preload("res://scripts/core/weapon_data.gd")

const SURFACES := ["concrete", "gravel", "metal", "sand", "нет_такой_поверхности"]


func _initialize() -> void:
	var fails: Array[String] = []
	var checked := 0
	var rx := RegEx.new()
	rx.compile("res://assets/audio/fx/([A-Za-z0-9_]+\\.mp3)")

	# 1) литералы путей во всех скриптах обязаны существовать
	for p in _script_paths("res://scripts"):
		var txt := FileAccess.get_file_as_string(p)
		for m in rx.search_all(txt):
			checked += 1
			var ref := FX_DIR + m.get_string(1)
			if not ResourceLoader.exists(ref):
				fails.append("%s -> отсутствующий %s" % [p.get_file(), ref])
	if checked == 0:
		fails.append("не нашёл ни одной ссылки на звук в скриптах — тест бесполезен")

	# 2) цепочка шагов: реальный вызов, реальный резолвинг
	var am: Node = AudioManager.new()
	var calls := 0
	for surface in SURFACES:
		for left in [true, false]:
			am.call("footsteps", surface, left)
			calls += 1
			checked += 1
			var last := String(am.get("last_played"))
			if last.is_empty():
				fails.append("footsteps('%s') ничего не выбрал" % surface)
			elif not ResourceLoader.exists(last):
				fails.append("footsteps('%s') -> '%s': файла нет" % [surface, last])
	if int(am.get("play_count")) != calls:
		fails.append("play_sfx вызван %d раз, ожидалось %d (шаг не доходит до шины)" % [
			int(am.get("play_count")), calls])
	am.free()

	# 3) id оружия != имя файла: m4a1s должен маппиться на существующий сэмпл
	var w: Node = WeaponScript.new()
	for data in WeaponDataRes.default_loadout():
		w.data = data
		var aid := String(w.call("audio_id"))
		checked += 1
		if not ResourceLoader.exists(FX_DIR + "guns_%s.mp3" % aid):
			fails.append("оружие '%s' -> guns_%s.mp3 отсутствует" % [data.id, aid])
	w.free()

	if fails.is_empty():
		print("ИТОГ: PASS — проверено %d ссылок на звук" % checked)
		quit(0)
	else:
		print("ИТОГ: FAIL (%d)" % fails.size())
		for x in fails:
			print("   - " + x)
		quit(1)


## Рекурсивный обход res:// за .gd-файлами (в -s-режиме автозагрузок нет,
## поэтому обходимся DirAccess без SceneTree.get_resource_files).
func _script_paths(base: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(base)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not n.begins_with("."):
			var p := base.path_join(n)
			if d.current_is_dir():
				out.append_array(_script_paths(p))
			elif n.ends_with(".gd"):
				out.append(p)
		n = d.get_next()
	d.list_dir_end()
	return out
