extends SceneTree
## Грузим КАЖДЫЙ CC0-ассет настоящим загрузчиком и инстанцируем его.
## Падение = битый импорт, который иначе вылезет у пользователя в редакторе.

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
	print("сцен .tscn=%d  ресурсов .tres=%d  → загружено/инстанцировано %d" % [scenes.size(), res.size(), ok])
	if bad.size():
		print("битых: %d" % bad.size())
		for b in bad.slice(0, 6): print("   ", b)
	else:
		print("битых: 0")
	quit(1 if bad.size() else 0)

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
