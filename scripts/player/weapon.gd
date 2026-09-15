class_name Weapon
extends Node3D
## Оружие: стрельба (hitscan + пуля), bloom, отдача, перезарядка, звук.
## Урон СЧИТАЕТСЯ НА СЕРВЕРЕ через Ballistics — тут только предсказание и FX.

signal shot_fired(origin: Vector3, dir: Vector3, weapon: WeaponData)
signal reloaded()
signal ammo_changed(mag: int, reserve: int)
signal hit_registered(target_id: int, part: String, dmg: float, killed: bool)

@export var data: WeaponData
@export var camera: Camera3D
@export var player_body: CharacterBody3D
@export var shoot_mask := 0b111
@export var tracer_path: NodePath = ^"TracerPool"

var _audio: Node = null

var mag := 0
var reserve := 0
var shot_index := 0
var bloom_shots := 0
var _next_shot_ms := 0
var _reload_until := 0
var _recoil := Vector2.ZERO
var _recoil_target := Vector2.ZERO
var _last_shot_ms := -99999


func _ready() -> void:
	# @export c NodePath в .tscn НЕ разрешается сам: `camera = NodePath("..")` и
	# `player_body = NodePath("../../..")` из bench.tscn дали null, и hitscan луч
	# не исключал стрелка (стрелял по себе). Разрешаем пути руками.
	if camera == null:
		push_warning("Weapon: camera не назначен — беру родителя")
		var pr := get_parent()
		if pr is Camera3D:
			camera = pr as Camera3D
	if player_body == null:
		var n: Node = get_parent()
		while n != null and not (n is CharacterBody3D):
			n = n.get_parent()
		if n != null:
			player_body = n as CharacterBody3D
		else:
			push_warning("Weapon: player_body не найден — разброс от скорости не учтётся")
	_audio = get_node_or_null("/root/AudioBus")
	if data == null:
		data = WeaponData.make_ak47()
	mag = data.mag_size
	reserve = data.reserve_ammo
	ammo_changed.emit(mag, reserve)


func _process(delta: float) -> void:
	# bloom остывает, если не стреляли
	var now := Time.get_ticks_msec()
	if now - _last_shot_ms > 120:
		bloom_shots = maxi(0, bloom_shots - int(data.spread_decay_rate * delta * 8))
	# отдача возвращается к нулю
	_recoil = Ballistics.recover(_recoil, data.recoil_recovery_speed, delta)
	_apply_recoil()
	if _reload_until > 0 and now >= _reload_until:
		_finish_reload()
	if Input.is_action_pressed("fire") and not _is_reloading() and camera:
		_try_shoot()
	if Input.is_action_just_pressed("reload") and not _is_reloading():
		start_reload()
	if Input.is_action_just_pressed("aim") and camera:
		camera.fov = clampf((camera.fov / data.ads_zoom) if not _aiming else camera.fov * data.ads_zoom, 55.0, 130.0)
		_aiming = not _aiming


var _aiming := false


func _is_reloading() -> bool:
	return _reload_until > 0


func start_reload() -> void:
	if mag >= data.mag_size or reserve <= 0:
		return
	_reload_until = Time.get_ticks_msec() + int(data.reload_time * 1000.0)
	_sfx("res://assets/audio/fx/reload_magin.mp3", "Weapons")


func _finish_reload() -> void:
	var need := data.mag_size - mag
	var take := mini(need, reserve)
	mag += take
	reserve -= take
	_reload_until = 0
	shot_index = 0
	bloom_shots = 0
	_sfx("res://assets/audio/fx/reload_magout.mp3", "Weapons")
	ammo_changed.emit(mag, reserve)
	reloaded.emit()


func _try_shoot() -> void:
	var now := Time.get_ticks_msec()
	var interval := 60000.0 / maxf(data.rpm, 1.0)
	if now < _next_shot_ms:
		return
	if mag <= 0:
		_sfx("res://assets/audio/fx/empty_click.mp3", "Weapons")
		start_reload()
		return
	mag -= 1
	_next_shot_ms = int(now + interval)
	_last_shot_ms = now
	shot_index += 1
	bloom_shots += 1

	_sfx("res://assets/audio/fx/guns_%s.mp3" % data.id, "Weapons", -2.0)

	var speed := 0.0
	if player_body:
		speed = Vector2(player_body.velocity.x, player_body.velocity.z).length()
	var base := data.base_spread_deg
	if _aiming:
		base *= data.ads_spread_mult
	var spread := Ballistics.spread_rad(base, speed, 6.6, not (player_body.is_on_floor() if player_body else true),
		crouching_now(), bloom_shots, data.bloom_per_shot)
	var first := 1.0 if shot_index > 1 else data.first_shot_multiplier

	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	dir = _cone_offset(dir, spread * first)

	shot_fired.emit(origin, dir, data)
	if multiplayer_has_server():
		rpc_id(1, "server_request_shot", origin, dir, int(mag), shot_index)
	else:
		_resolve(origin, dir, first)

	# отдача: тянем камеру вверх/вбок
	var step := Ballistics.recoil_step(data.recoil_pattern, shot_index - 1,
		data.recoil_horizontal_bias, data.spray_decay)
	_recoil_target += step
	if player_body and player_body.has_method("add_recoil"):
		player_body.add_recoil(step.y, step.x)
	ammo_changed.emit(mag, reserve)


func _sfx(path: String, bus := "Weapons", vol := 0.0) -> void:
	## Через /root/AudioBus, а не по имени автозагрузки: иначе скрипт не компилируется
	## в контекстах без дерева autoload (-s, headless-тулзы).
	if _audio and _audio.has_method("play_sfx"):
		_audio.play_sfx(path, bus, vol)


func crouching_now() -> bool:
	return bool(player_body.crouching) if player_body and "crouching" in player_body else false


func _apply_recoil() -> void:
	## Только сглаживание: сам тангаж принадлежит FPSController (он вызывает
	## add_recoil). Прямая запись в локальный поворот камеры конфликтовала с −90°,
	## которые ставит контроллер, и накапливалась каждый кадр (−5156° в замере).
	_recoil = _recoil.lerp(_recoil_target, 0.35)


func _cone_offset(dir: Vector3, spread_rad: float) -> Vector3:
	## Равномерное смещение внутри конуса (не гауссово — как в CS, где «разброс»
	## распределён по кругу, и это заметно в длинной очереди).
	var a := randf() * TAU
	var r := sqrt(randf()) * spread_rad
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.98:
		up = Vector3.FORWARD
	var right := dir.cross(up).normalized()
	var f := dir.cross(right).normalized()
	return (dir + right * (sin(a) * r) + f * (cos(a) * r)).normalized()


@rpc("any_peer", "call_local", "reliable")
func server_request_shot(origin: Vector3, dir: Vector3, _mag: int, _idx: int) -> void:
	## СЕРВЕРНАЯ ветка. Здесь же должна быть проверка дистанции/тайминга,
	## иначе клиент насраает выстрелов быстрее, чем позволяет RPM.
	if not multiplayer.is_server():
		return
	_resolve(origin, dir, 1.0)


func _resolve(origin: Vector3, dir: Vector3, first_mult: float) -> void:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if player_body: exclude.append(player_body.get_rid())
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 400.0, shoot_mask, exclude)
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_spawn_tracer(origin, origin + dir * 400.0)
		_sfx("res://assets/audio/fx/hit_wall.mp3", "Weapons", -12.0)
		return
	var collider: Node = hit.collider
	var part := String(collider.get_meta("hitbox_part", "chest")) if collider.has_meta("hitbox_part") else "chest"
	var dist := origin.distance_to(hit.position)
	var dmg := Ballistics.damage_base(data.damage * first_mult, dist, data.falloff_start,
		data.falloff_end, data.falloff_min_mult)
	dmg *= Ballistics.hitmult(part)
	var armor := float(collider.get_meta("armor", 100.0)) if collider.has_meta("armor") else 0.0
	var helmet := bool(collider.get_meta("helmet", true)) if collider.has_meta("helmet") else false
	dmg = Ballistics.armor_damage(dmg, armor, data.armor_penetration, data.helmet_mult, helmet)
	_spawn_tracer(origin, hit.position)
	if part == "head":
		_sfx("res://assets/audio/fx/hit_helmet.mp3", "Weapons", -6.0)
	else:
		_sfx("res://assets/audio/fx/hit_flesh.mp3", "Weapons", -8.0)
	if collider.has_method("take_damage"):
		var killed: bool = collider.take_damage(dmg, part, multiplayer.get_unique_id())
		hit_registered.emit(collider.get_instance_id(), part, dmg, killed)


func _spawn_tracer(_a: Vector3, _b: Vector3) -> void:
	var pool := get_node_or_null(tracer_path)
	if pool and pool.has_method("spawn"):
		pool.spawn(_a, _b)


func multiplayer_has_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.get_unique_id() != 1
