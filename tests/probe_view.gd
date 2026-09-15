extends SceneTree
## ДИАГНОСТИКА, не тест: говорит, что реально увидит камера после «Быстрой игры».
## PhysicsServer3D в -s-режиме не шагает, поэтому «игрок стоит на полу» тут не
## проверяется — зато проверяется геометрия: что под ногами, что перед глазами и
## не торчит ли камера внутри меша. Запуск:
##   godot --headless --path . -s res://tests/probe_view.gd
##   godot --headless --path . -s res://tests/probe_view.gd -- x=-14 z=-8

const BENCH := "res://scenes/maps/bench.tscn"
const EYE := 1.72  # высота глаз в стойке (совпадает с eye_height_stand)

var _frames := 0
var _world: Node


func _initialize() -> void:
	var ps: PackedScene = load(BENCH)
	if ps == null:
		printerr("FAIL: bench не грузится")
		quit(1)
		return
	_world = ps.instantiate()
	get_root().add_child(_world)
	_override_spawn_from_args()


func _override_spawn_from_args() -> void:
	var pos := Vector3.ZERO
	var found := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("x="):
			pos.x = a.trim_prefix("x=").to_float(); found = true
		elif a.begins_with("z="):
			pos.z = a.trim_prefix("z=").to_float(); found = true
		elif a.begins_with("y="):
			pos.y = a.trim_prefix("y=").to_float(); found = true
	if not found:
		return
	var p := _world.get_node_or_null("Player")
	if p:
		p.global_position = pos


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_report()
	quit(0)
	return true


func _report() -> void:
	var w := _world
	var player := w.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		print("FAIL: нет Player")
		return
	print("\n================ ДИАГНОСТИКА СПАВНА ================")
	var sc: Script = player.get_script()
	print("script на Player      : %s" % (sc.resource_path if sc != null else "❌ ОТСУТСТВУЕТ — игрок немой"))
	var excl: Array[RID] = [player.get_rid()]
	var space: PhysicsDirectSpaceState3D = w.get_world_3d().direct_space_state

	# глаза = опора + высота глаз, как это сделает контроллер
	var probe := player.global_position + Vector3.UP * 2.0
	var g: Dictionary = space.intersect_ray(_mk(probe, probe + Vector3.DOWN * 30.0, excl))
	var ground_y := 0.05
	if not g.is_empty():
		var gp: Vector3 = g["position"]
		ground_y = gp.y
	var eye := Vector3(player.global_position.x, ground_y + EYE, player.global_position.z)
	print("позиция ног           : %s | пол y=%.2f | глаза y=%.2f" % [_v(player.global_position), ground_y, eye.y])
	_ground(space, eye)
	_wallbox(space, eye, excl)
	_forward(space, eye, player.rotation.y, excl)
	print("=====================================================\n")


func _ground(space: PhysicsDirectSpaceState3D, eye: Vector3) -> void:
	var top := eye + Vector3.UP * 1.0
	var hit: Dictionary = space.intersect_ray(_mk(top, top + Vector3.DOWN * 30.0, []))
	if hit.is_empty():
		print("опора под глазами     : ❌ НИЧЕГО в 30 м — провал в пустоту")
		return
	var hp: Vector3 = hit["position"]
	var gy: float = hp.y
	var c: Node = hit["collider"]
	var gap: float = eye.y - gy
	print("опора под глазами     : %s на y=%.2f (глаза на %.2f → зазор %.2f м)" % [c.name, gy, eye.y, gap])
	if gap < 0.2:
		print("                        ⚠ глаза почти в опоре")
	elif gap > 4.0:
		print("                        ⚠ высоко: падение %.1f м при старте" % gap)


func _wallbox(space: PhysicsDirectSpaceState3D, at: Vector3, excl: Array[RID]) -> void:
	## Камера внутри коллайдера = чёрная полоса через весь экран (видно только
	## внутреннюю сторону полигонов, она не освещена и не отрисовывается).
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = excl
	var hits := space.intersect_shape(q, 8)
	if hits.is_empty():
		print("объём у глаз (0.3 м)  : чисто")
	else:
		var names: Array[String] = []
		for h in hits:
			var c: Node = h["collider"]
			names.append(c.name if c else "?")
		print("объём у глаз (0.3 м)  : ❌ ВНУТРИ ГЕОМЕТРИИ: %s" % ", ".join(names))


func _forward(space: PhysicsDirectSpaceState3D, eye: Vector3, yaw: float, excl: Array[RID]) -> void:
	print("лучи от глаз (вперёд ±90°, шаг 22.5°, 14 м):")
	var clear := 0
	var blockers := 0
	for i in range(9):
		var dir := Basis(Vector3.UP, yaw + deg_to_rad(i * 22.5 - 90.0)) * Vector3.FORWARD
		var hit: Dictionary = space.intersect_ray(_mk(eye, eye + dir * 14.0, excl))
		if hit.is_empty():
			clear += 1
			print("   %+4.0f° : чисто" % (i * 22.5 - 90.0))
		else:
			var hp: Vector3 = hit["position"]
			var d: float = eye.distance_to(hp)
			var c: Node = hit["collider"]
			if d < 1.2:
				blockers += 1
			print("   %+4.0f° : %-30s %.2f м%s" % [i * 22.5 - 90.0, c.name if c else "?", d,
				"  ⚠ ПЕРЕД НОСОМ" if d < 1.2 else ""])
	print("секторов свободно      : %d из 9 | в упор: %d" % [clear, blockers])


func _mk(a: Vector3, b: Vector3, excl: Array[RID]) -> PhysicsRayQueryParameters3D:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = excl
	q.collide_with_areas = false
	return q


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
