@tool
class_name WeaponData
extends Resource
## Описание оружия. Один ресурс = один ствол. Паттерны отдачи — в градусах
## смещения камеры, X вправо / Y вверх. Числа стартовые, балансим по ощущениям.

@export var id: StringName = &"ak47"
@export var display_name: String = "AK-47"
@export var category: Category = Category.RIFLE
@export var model_scene: PackedScene
@export var muzzle_marker: NodePath = ^"Muzzle"

enum Category { RIFLE, SMG, PISTOL, SNIPER, SHOTGUN, KNIFE }

@export_group("Урон (сверено с Ballistics)")
@export var damage: float = 36.0
@export var armor_penetration: float = 0.5      # 0..1
@export var falloff_start: float = 10.0
@export var falloff_end: float = 40.0
@export var falloff_min_mult: float = 0.70
@export var helmet_mult: float = 4.0
@export var legs_mult: float = 0.87

@export_group("Стрельба")
@export var rpm: float = 600.0                  # выстрелов в минуту
@export var mag_size: int = 30
@export var reserve_ammo: int = 90
@export var reload_time: float = 2.5
@export var first_shot_multiplier: float = 1.25 # 1-й выстрел точнее
@export var base_spread_deg: float = 0.6
@export var bloom_per_shot: float = 0.35
@export var spread_decay_rate: float = 8.0      # скорость остывания ствола
@export var ads_spread_mult: float = 0.55
@export var ads_zoom: float = 1.35
@export var recoil_pattern: PackedVector2Array = PackedVector2Array()
@export var recoil_horizontal_bias: float = 1.0
@export var spray_decay: float = 0.10
@export var recoil_recovery_speed: float = 9.0
@export var muzzle_velocity: float = 715.0      # 0 => hitscan
@export var move_speed_mult: float = 1.0        # как тяжело носить
@export var price: int = 2700
@export var kill_reward: int = 300


static func make_ak47() -> WeaponData:
	var w := WeaponData.new()
	w.id = &"ak47"; w.display_name = "AK-47"; w.damage = 36.0
	w.rpm = 600.0; w.mag_size = 30; w.reserve_ammo = 90; w.reload_time = 2.5
	w.base_spread_deg = 0.6; w.armor_penetration = 0.7; w.price = 2700
	w.recoil_pattern = PackedVector2Array([
		Vector2(0.6, 1.8), Vector2(1.1, 2.6), Vector2(0.4, 2.2), Vector2(-0.7, 1.9),
		Vector2(-1.3, 1.6), Vector2(-0.9, 1.5), Vector2(0.2, 1.4), Vector2(1.0, 1.2),
		Vector2(0.8, 1.0), Vector2(-0.4, 0.9), Vector2(-0.8, 0.8), Vector2(0.1, 0.7),
		Vector2(0.7, 0.6), Vector2(-0.3, 0.6), Vector2(-0.6, 0.5), Vector2(0.4, 0.5)])
	return w


static func make_m4a1s() -> WeaponData:
	var w := WeaponData.new()
	w.id = &"m4a1s"; w.display_name = "M4A1-S"; w.damage = 33.0
	w.rpm = 666.0; w.mag_size = 20; w.reserve_ammo = 80; w.reload_time = 3.1
	w.base_spread_deg = 0.45; w.armor_penetration = 0.4; w.price = 2900
	w.ads_spread_mult = 0.45; w.ads_zoom = 1.5
	w.recoil_pattern = PackedVector2Array([
		Vector2(0.2, 1.4), Vector2(-0.3, 1.9), Vector2(0.4, 1.6), Vector2(0.1, 1.3),
		Vector2(-0.4, 1.2), Vector2(0.2, 1.0), Vector2(0.5, 0.9), Vector2(-0.2, 0.8)])
	return w


static func make_deagle() -> WeaponData:
	var w := WeaponData.new()
	w.id = &"deagle"; w.display_name = "Desert Eagle"; w.damage = 63.0
	w.rpm = 267.0; w.mag_size = 7; w.reserve_ammo = 35; w.reload_time = 2.2
	w.base_spread_deg = 0.9; w.armor_penetration = 0.9; w.price = 700
	w.first_shot_multiplier = 1.0; w.move_speed_mult = 1.1
	w.recoil_pattern = PackedVector2Array([Vector2(0.0, 5.5), Vector2(0.0, 6.2), Vector2(0.0, 6.8)])
	return w


static func make_awp() -> WeaponData:
	var w := WeaponData.new()
	w.id = &"awp"; w.display_name = "AWP"; w.category = WeaponData.Category.SNIPER
	w.damage = 115.0; w.rpm = 41.0; w.mag_size = 5; w.reserve_ammo = 30; w.reload_time = 3.7
	w.base_spread_deg = 4.2; w.armor_penetration = 0.92; w.price = 4750
	w.ads_spread_mult = 0.02; w.ads_zoom = 5.0
	w.muzzle_velocity = 890.0
	w.move_speed_mult = 0.82
	w.recoil_pattern = PackedVector2Array([Vector2(0.0, 9.0)])
	return w


static func default_loadout() -> Array[WeaponData]:
	var out: Array[WeaponData] = [make_deagle(), make_awp(), make_ak47(), make_m4a1s()]
	return out
