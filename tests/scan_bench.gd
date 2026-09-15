extends SceneTree
## Сетка «где можно встать»: для каждой клетки меряем, есть ли опора под ногами и
## свободно ли в объёме на уровне глаз. Только печать, ничего не чинит.
##   godot --headless --path . -s res://tests/scan_bench.gd

const BENCH := "res://scenes/maps/bench.tscn"
const EYE := 1.72
const STEP := 4.0

var _frames := 0
var _world: Node


func _initialize() -> void:
	var ps: PackedScene = load(BENCH)
	assert(ps != null)
	_world = ps.instantiate()
	get_root().add_child(_world)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_scan()
	quit(0)
	return true


func _scan() -> void:
	var root := _world as Node3D
	var space := root.get_world_3d().direct_space_state
	var player := _world.get_node_or_null("Player")
	var excl: Array[RID] = []
	if player is CharacterBody3D:
		excl = [(player as CharacterBody3D).get_rid()]

	print("\nкарта опоры (S = стоится, . = нет пола, W = в глазах геометрия, цифры = дистанция взгляда вперёд):")
	var rows: Array[String] = []
	var good: Array[Vector3] = []
	var z := -12.0
	while z <= 12.001:
		var line := "  z=%+5.1f " % z
		var x := -20.0
		while x <= 20.001:
			var c := Vector3(x, 0.0, z)
			var down := space.intersect_ray(_mk(c + Vector3.UP * 4.0, c + Vector3.DOWN * 4.0, excl))
			var ch := ""
			if down.is_empty():
				ch = "."
			else:
				var ground_y: float = (down["position"] as Vector3).y
				var eye := Vector3(x, ground_y + EYE, z)
				var inball := _blocked(space, eye, excl)
				var fwd := space.intersect_ray(_mk(eye, eye + Vector3.FORWARD * 14.0, excl))
				if inball:
					ch = "W"
				elif fwd.is_empty():
					ch = "S"
					good.append(Vector3(x, ground_y, z))
				else:
					ch = "%d" % int(clampf(eye.distance_to(fwd["position"]), 0.0, 9.0))
			line += " " + ch
			x += STEP
		rows.append(line)
		z += STEP
	for r in rows:
		print(r)

	print("\nкандидатов в чистые: %d" % good.size())
	for g in good:
		var d: float = (g - Vector3(-14, g.y, -8)).length()
		var dt: float = (g - Vector3(14, g.y, 8)).length()
		print("   (%+5.1f, %+5.2f, %+5.1f)  до SpawnCT %5.1f | до SpawnT %5.1f" % [g.x, g.y, g.z, d, dt])
	# где вообще пол по высоте
	var ys := {}
	for g in good:
		ys[round(g.y * 10.0) / 10.0] = int(ys.get(round(g.y * 10.0) / 10.0, 0)) + 1
	print("высоты опоры: %s" % ys)


func _mk(a: Vector3, b: Vector3, excl: Array[RID]) -> PhysicsRayQueryParameters3D:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = excl
	q.collide_with_areas = false
	return q


func _blocked(space: PhysicsDirectSpaceState3D, at: Vector3, excl: Array[RID]) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.4
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = excl
	return not space.intersect_shape(q, 1).is_empty()
