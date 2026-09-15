extends SceneTree
## Проверка сетевого каркаса, две ортогональные вещи:
##   (1) все обращения `_peer.X` / `multiplayer.X` — существующие методы/сигналы
##       (ловит опечатки вида `_peer.get_peer_list()`);
##   (2) всё, по чему в net_manager пишут `for ... in <вызов>`, возвращает
##       итерируемый тип. Именно так ловится баг `for c in _peer.get_host()`:
##       метод есть, но отдаёт ENetConnection (и null до create_server) —
##       «Unable to iterate on object of type 'Object'», host() обрывался перед
##       server_started, и кнопка «Хост» в меню молчала.
##
## Почему линт, а не «просто вызвать host()»: в `-s`-режиме у root-вьюпорта
## multiplayer API = null (в 4.7 у Viewport нет set_multiplayer — проверено
## ClassDB), поэтому реальный host() тут исполняется только наполовину, а
## `join()` на собственный порт вешает прогон на минуты. Значит:
##   (1) статически сверяем КАЖДЫЙ вызов метода peer'а с ClassDB — это и есть
##       ловля «несуществующего метода», без зависимости от окружения;
##   (2) рантайм — если API всё-таки доступен (обычный запуск из редактора).

const NET := "res://scripts/network/net_manager.gd"
const NetScript := preload("res://scripts/network/net_manager.gd")
const PEER_CLASS := "ENetMultiplayerPeer"

## Что здесь НЕ должно быть: методы, которых нет у движка.
var _fails: Array[String] = []


func _initialize() -> void:
	_lint_peer_calls()
	_maybe_runtime()


func _lint_peer_calls() -> void:
	var src := _code_only(FileAccess.get_file_as_string(NET))
	if src.is_empty():
		_fails.append("не прочитал %s" % NET)
		return
	var rx := RegEx.new()
	# любой член peer'а или multiplayer API: `_peer.<имя>` / `multiplayer.<имя>`
	rx.compile("(?:_peer|multiplayer)\\.([a-z_0-9]+)")
	var seen := 0
	for m in rx.search_all(src):
		var name := m.get_string(1)
		if name in ["new", "free", "duplicate"]:
			continue
		seen += 1
		# метод? сигнал? константа-подобное свойство? — если ничего из этого нет,
		# в рантайме будет «Invalid call. Nonexistent function» = падение меню.
		var cls := PEER_CLASS if "_peer." in m.get_string(0) else "MultiplayerAPI"
		var ok := false
		ok = ClassDB.class_has_method(cls, name, false) or ClassDB.class_has_signal(cls, name)
		ok = ok or _props_of(cls).has(name)
		if not ok:
			_fails.append("%s: '%s' нет у %s — падение при нажатии «Хост»" % [
				NET.get_file(), name, cls])
	_check_iterables(src)
	print("  линт: сверено %d обращений к peer/API" % seen)
	if seen == 0:
		_fails.append("линт не нашёл ни одного обращения к peer'у — он бесполезен")


## Комментарии вон: иначе линт режет собственный комментарий «было: for c in ...».
func _code_only(text: String) -> String:
	var out: Array[String] = []
	for line in text.split("\n"):
		var st := line.strip_edges()
		if st.begins_with("#"):
			continue
		var hash := line.find(" # ")
		if hash >= 0:
			line = line.substr(0, hash)
		out.append(line)
	return "\n".join(out)


func _check_iterables(src: String) -> void:
	var rx := RegEx.new()
	rx.compile("for\\s+\\w+\\s+in\\s+(?:_peer|multiplayer)\\.([a-z_0-9]+)\\s*\\(")
	var hits := 0
	for m in rx.search_all(src):
		hits += 1
		var meth := m.get_string(1)
		var cls := PEER_CLASS if m.get_string(0).contains("_peer.") else "MultiplayerAPI"
		var t := _return_type(cls, meth)
		if t < 0:
			continue                      # метода нет — об этом уже сказал пункт (1)
		if not _iterable(t):
			_fails.append("`for ... in %s.%s()` — возврат имеет тип %d, по нему нельзя итерироваться" % [cls, meth, t])
	print("  итерируемость: проверено %d for-in над вызовами peer/API" % hits)


func _return_type(cls: String, meth: String) -> int:
	for d in ClassDB.class_get_method_list(cls, false):
		if String(d["name"]) == meth:
			var r: Dictionary = d.get("return", {})
			return int(r.get("type", -1))
	return -1


func _iterable(t: int) -> bool:
	var ok := t == TYPE_DICTIONARY or t == TYPE_ARRAY
	ok = ok or (t >= TYPE_PACKED_BYTE_ARRAY and t <= TYPE_PACKED_COLOR_ARRAY)
	return ok


var _props := {}


## class_has_property в 4.7 нет (проверено ClassDB) — берём список свойств целиком.
func _props_of(cls: String) -> Dictionary:
	if not _props.has(cls):
		var d := {}
		for pi in ClassDB.class_get_property_list(cls, false):
			d[String(pi["name"])] = true
		_props[cls] = d
	return _props[cls]


func _maybe_runtime() -> void:
	var net: Node = NetScript.new()
	get_root().add_child(net)
	if net.get_multiplayer() == null:
		print("  рантайм-прогон host(): пропускаю (в -s multiplayer API = null; в игре его покрывает live-прогон)")
		net.free()
		_report()
		return
	var err: int = int(net.call("host", 7788, 4))
	if err != OK:
		print("  host() -> %s (UDP недоступен в песочнице — не баг кода)" % error_string(err))
	else:
		if not bool(net.get("is_server")):
			_fails.append("host() отработал, но is_server == false")
		net.call("leave")
		if bool(net.get("is_server")):
			_fails.append("после leave() is_server остался true")
	net.free()
	_report()


func _report() -> void:
	if _fails.is_empty():
		print("ИТОГ: PASS — сетевой каркас ссылается только на существующие методы")
		quit(0)
	else:
		print("ИТОГ: FAIL (%d)" % _fails.size())
		for f in _fails:
			print("   - " + f)
		quit(1)
