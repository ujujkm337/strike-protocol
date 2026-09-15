extends SceneTree
## Грузим КАЖДЫЙ CC0-ассет настоящим загрузчиком и инстанцируем его.
## Падение = битый импорт, который иначе вылезет у пользователя в редакторе.
##
## Исключение из правила — addons/.../rooms/*_map.tscn: сцены-комнаты из пака
## битые НА ВХОДЕ (GridMap ссылается на MeshLibrary, которого в архиве нет, и на
##ExtResource id, которого в файле нет). Они не подключены ни к одной нашей карте
## и исключены из экспорта. Считаем их «известными», а падением — только всё новое.

const DIR := "res://addons/quaternius-modular-scifi-pack"

func _init() -> void:
	var scenes := _collect(DIR, ".tscn")
	var res := _collect(DIR, ".tres")
	var ok := 0
	var bad: Array[String] = []
	for p in scenes + res:
		if not ResourceLoader.exists(p):
			bad.append("нет файла: " + p); continue
		var loaded = load(p)
		if loaded == null:
			bad.append("не грузится: " + p); continue
		if loaded is PackedScene:
			var inst := (loaded as PackedScene).instantiate()
			if inst == null: bad.append("instantiate null: " + p); continue
			inst.free()
		ok += 1
	var known: Array[String] = []
	var fresh: Array[String] = []
	for b in bad:
		if b.contains("/rooms/") and b.contains("_map.tscn"):
			known.append(b)
		else:
			fresh.append(b)
	print("сцен .tscn=%d  ресурсов .tres=%d  → загружено/инстанцировано %d" % [scenes.size(), res.size(), ok])
	if known.size():
		print("известно-битых (внешний пак, из экспорта исключены): %d" % known.size())
		for b in known.slice(0, 6): print("   ", b)
	if fresh.is_empty():
		print("ИТОГ: PASS — новых битых ресурсов нет")
		quit(0)
	else:
		# quit() откладывается до конца кадра: без else печать ушла бы дважды
		# (проверено на этом же файле)
		print("ИТОГ: FAIL (%d)" % fresh.size())
		for b in fresh.slice(0, 10): print("   - " + b)
		quit(1)

func _collect(path: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(path)
	if d == null: return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var full := path.path_join(f)
		if d.current_is_dir(): out.append_array(_collect(full, ext))
		elif f.ends_with(ext): out.append(full)
		f = d.get_next()
	d.list_dir_end()
	return out
