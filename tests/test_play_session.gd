extends SceneTree
## Статическая проверка сборки сцены. ВСЕ динамические вещи (стоит ли на полу,
## туда ли смотрит спавн, едет ли от WASD) — в tests/run_live.sh: там физика
## шагает по-настоящему. В -s-режиме я четырежды делал неверные выводы, пытаясь
## измерить их на 3-м кадре до отработки deferred/физики.

const BENCH := "res://scenes/maps/bench.tscn"
const WARMUP := 3

var _frames := 0
var _world: Node


func _initialize() -> void:
	var ps: PackedScene = load(BENCH)
	if ps == null:
		printerr("ИТОГ: FAIL — bench не грузится")
		quit(1)
		return
	_world = ps.instantiate()
	get_root().add_child(_world)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP:
		return false
	var fails: Array[String] = _check()
	if fails.is_empty():
		print("ИТОГ: PASS — сцена собрана связно")
		quit(0)
	else:
		print("ИТОГ: FAIL (%d)" % fails.size())
		for f in fails:
			print("   - " + f)
		quit(1)
	return true


func _check() -> Array[String]:
	var fails: Array[String] = []
	var w := _world
	var player := w.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		return ["нет Player"]

	# 1. контроллер обязан висеть на игроке
	if player.get_script() == null:
		fails.append("У Player нет script= (fps_controller.gd) — ни WASD, ни мыши")

	# 2. группы для поиска (HUD/автопилот ищут по ним)
	if not player.is_in_group("player"):
		fails.append("Player не в группе 'player' — автопилот/HUD его не найдут")

	# 3. формы коллизии — ПРЯМЫЕ дети тела и без смещений.
	#    Проверено движком: вложенные в узел-обёртку CollisionShape3D intersect_shape
	#    видит, а move_and_slide — нет, и игрок пролетал сквозь пол при любой высоте.
	## Формы коллизии — прямыми детьми CharacterBody3D. Проверено: вложенные в
	## узел-обёртку, они видны intersect_shape, но move_and_slide по ним не
	## останавливает тело (игрок пролетал пол при любой высоте спавна).
	var stand := player.get_node_or_null("Stand") as CollisionShape3D
	var crouch := player.get_node_or_null("Crouch") as CollisionShape3D
	if stand == null:
		fails.append("нет Stand прямым ребёнком Player")
	elif stand.shape == null:
		fails.append("у Stand нет shape")
	elif absf(stand.position.y) > 0.02:
		fails.append(("Stand на %+.2f: движок ставит начало координат тела в ЦЕНТР активной формы, а её смещение при resolve игнорирует — форма обязана висеть в нуле, иначе игрок висит или уходит под пол (пол = чёрный кадр)" % stand.position.y))
	# Head обязан быть на eye_height_stand НАД началом тела (ноги)
	var hd0 := player.get_node_or_null("Head") as Node3D
	if hd0 != null:
		print("Stand.y=%.2f | Head.y=%.2f | eye_height_stand=%.2f" % [stand.position.y, hd0.position.y, player.eye_height_stand])
		if absf(float(hd0.position.y) - float(player.eye_height_stand)) > 0.02:
			fails.append("Head на %.2f, а eye_height_stand=%.2f — контроллер каждый кадр тянет голову на своё значение, сцена с ним расходится (глаза в полу = чёрный кадр)" % [
				float(hd0.position.y), float(player.eye_height_stand)])
	elif not (stand.shape is CapsuleShape3D):
		fails.append("Stand.shape должна быть CapsuleShape3D")
	if crouch == null:
		fails.append("нет Crouch прямым ребёнком Player")
	elif not crouch.disabled:
		fails.append("Crouch обязан быть disabled в стойке")

	# 4. камера: существует, current, и НЕ повёрнута из сцены
	var cam := player.get_node_or_null("Head/Camera3D") as Camera3D
	if cam == null:
		cam = player.get_node_or_null("Head/Camera") as Camera3D
	if cam == null:
		fails.append("нет Player/Head/Camera3D — обзора не будет")
	else:
		if cam.rotation_degrees.length() > 0.01:
			fails.append("у камеры в сцене задан поворот %s — ориентацией владеет контроллер, двойная база даёт 180°" % cam.rotation_degrees)
		## Head в сцене — только начальное значение: контроллер каждый кадр лидит
		## head.position.y к eye_height_stand, поэтому проверять надо КОНСТАНТУ,
		## а не замер (замер на 3-м кадре — это и есть причина моих прошлых ошибок).
		var hd := player.get_node_or_null("Head") as Node3D
		print("Head: %.2f | eye_height_stand=%.2f (в рантайме лидится к константе)" % [
			hd.position.y if hd else -1, player.eye_height_stand])
		if player.eye_height_stand < 0.5 or player.eye_height_stand > 1.4:
			fails.append("eye_height_stand=%.2f вне разумного 0.5..1.4 (от центра капсулы)" % player.eye_height_stand)
		if absf(float(player.eye_height_stand) - float(player.eye_height_crouch)) < 0.3:
			fails.append("стоя %.2f и сидя %.2f почти равны — присед не изменит обзор" % [
				player.eye_height_stand, player.eye_height_crouch])

	# 5. спавн-маркер задан и доступен: без него игрок рождается где попало
	var spawn: Node3D = null
	if not player.spawn_path.is_empty():
		spawn = player.get_node_or_null(player.spawn_path) as Node3D
		if spawn == null:
			fails.append("spawn_path '%s' не разрешается — игрок встанет в трансформ из сцены" % player.spawn_path)
	else:
		fails.append("spawn_path пуст — стартовый трансформ из .tscn никто не поправит")
	if spawn != null and cam != null:
		# глаза не должны быть внутри геометрии: это и есть «чёрная полоса»
		var space: PhysicsDirectSpaceState3D = w.get_world_3d().direct_space_state
		var q := PhysicsShapeQueryParameters3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.3
		q.shape = sph
		q.transform = Transform3D(Basis.IDENTITY, cam.global_position)
		q.collide_with_bodies = true
		q.collide_with_areas = false
		q.exclude = [player.get_rid()]
		var inside: Array[Dictionary] = space.intersect_shape(q, 4)
		if not inside.is_empty():
			var names: Array[String] = []
			for h in inside:
				var c: Node = h["collider"]
				names.append(c.name if c else "?")
			fails.append("глаза ВНУТРИ ГЕОМЕТРИИ: %s" % ", ".join(names))

	# 6. оружие связано с игроком: @export c NodePath в .tscn сам не резолвится
	var weapon: Node = cam.get_node_or_null("Weapon") if cam != null else null
	if weapon == null:
		fails.append("нет Weapon под камерой")
	else:
		if weapon.player_body == null:
			fails.append("weapon.player_body == null — hitscan не исключит стрелка")
		elif weapon.player_body != player:
			fails.append("weapon.player_body указывает не на Player")
		if weapon.camera == null:
			fails.append("weapon.camera == null")
		if weapon.data == null:
			fails.append("weapon.data == null")
		elif weapon.mag != weapon.data.mag_size:
			fails.append("магазин не полный: %d/%d" % [weapon.mag, weapon.data.mag_size])

	# 7. HUD в карте
	if w.get_node_or_null("HUD") == null:
		fails.append("в карте нет HUD — игрок не видит ни прицела, ни патронов")

	# 8. свет/укрытия/окружение — как раньше
	var geo := w.get_node_or_null("Geometry")
	var props: int = geo.get_child_count() if geo != null else 0
	if props < 20:
		fails.append("укрытий мало: %d" % props)
	var shadowed := 0
	var lights := w.get_node_or_null("Lights")
	if lights != null:
		for l in lights.get_children():
			if l is Light3D and (l as Light3D).shadow_enabled:
				shadowed += 1
	# Теневой бюджет: ровно направленный + не больше одного оммни. Больше — VRAM и
	# вылет на ~10 с на встроенном GPU (реальный дефект сборки 4.7).
	if shadowed < 1:
		fails.append("ни один источник света не отбрасывает тень — карта будет плоской")
	elif shadowed > 2:
		fails.append("источников света с тенями: %d (> 2) — риск переполнения VRAM и вылета" % shadowed)
	var we := w.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we == null or we.environment == null:
		fails.append("нет WorldEnvironment с environment")
	elif not we.environment.sdfgi_enabled:
		fails.append("SDFGI выключен")
	return fails
