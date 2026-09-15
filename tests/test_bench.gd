extends SceneTree
func _init() -> void:
	var p := "res://scenes/maps/bench.tscn"
	if not ResourceLoader.exists(p):
		printerr("FAIL: нет сцены"); quit(1); return
	var ps: PackedScene = load(p)
	if ps == null:
		printerr("FAIL: не грузится"); quit(1); return
	var inst := ps.instantiate()
	if inst == null:
		printerr("FAIL: instantiate -> null"); quit(1); return
	var nodes := 0
	var solids := 0
	var stack := [inst]
	while stack:
		var n = stack.pop_back()
		nodes += 1
		if n is StaticBody3D or n is CharacterBody3D or n is RigidBody3D:
			solids += 1
		for c in n.get_children():
			stack.append(c)
	var player := inst.get_node_or_null("Player")
	var geo := inst.get_node_or_null("Geometry")
	var lamps := 0
	for l in inst.get_node_or_null("Lights").get_children():
		if l is Light3D: lamps += 1
	# заодно проверяем мои рукописные сцены — их никто не валидировал до этого
	for own in ["res://scenes/world_environment.tscn"]:
		if not ResourceLoader.exists(own):
			printerr("FAIL: нет " + own); quit(1); return
		var ow = load(own)
		if ow == null: printerr("FAIL: не грузится " + own); quit(1); return
		if ow is PackedScene:
			var oi := (ow as PackedScene).instantiate()
			if oi == null: printerr("FAIL: instantiate null " + own); quit(1); return
			var env := oi as WorldEnvironment
			print("world_environment: environment=" + str(env != null and env.environment != null)
				+ " sdfgi=" + str(env.environment.sdfgi_enabled) + " aces=" + str(env.environment.tonemap_mode == 3)
				+ " volumetric=" + str(env.environment.volumetric_fog_enabled))
			if env == null or env.environment == null: quit(1)
			oi.free()
	var ok := player != null and geo != null and nodes > 40
	print("узлов: %d | тел с коллизией: %d | укрытий: %d | источников света: %d | player: %s"
		% [nodes, solids, geo.get_child_count(), lamps, player != null])
	print("камера игрока: %s | оружие: %s" % [
		inst.find_child("Camera", true, false) != null,
		inst.find_child("Weapon", true, false) != null])
	inst.free()
	print("ИТОГ: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
