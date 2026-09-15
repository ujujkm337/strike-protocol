#!/usr/bin/env python3
"""Зеркало scripts/core/ballistics.gd — 1-в-1 по формулам.

Зачем: в этой песочнице нет GPU и нельзя запустить Godot-редактор, поэтому
математику стрельбы я проверяю здесь, а в Godot она потом выполняется через
tests/test_ballistics.gd (тот же набор чисел). Если тут FAIL — в игре баг.

Запуск:  python3 tests/test_ballistics.py
"""
import math

MAX_ARMOR = 100.0
GRAVITY = 9.81


def damage_base(dmg, dist, falloff_start, falloff_end, min_mult):
    if dist <= falloff_start:
        return dmg
    if dist >= falloff_end:
        return dmg * min_mult
    t = (dist - falloff_start) / max(falloff_end - falloff_start, 0.001)
    return dmg * (1.0 + (min_mult - 1.0) * t)


def armor_damage(dmg, armor, pen, helm_mult, helmet):
    pen = min(max(pen, 0.0), 1.0)
    armor_frac = min(max(armor / MAX_ARMOR, 0.0), 1.0)
    ratio = 1.0 - armor_frac * (1.0 - pen) * 0.5
    out = dmg * ratio
    return out * helm_mult if helmet else out


def hitmult(part):
    return {"head": 4.0, "neck": 1.33, "chest": 1.0,
            "stomach": 1.25, "arm": 1.0, "leg": 0.87}.get(part, 1.0)


def spread_rad(base_deg, speed, max_speed, airborne, crouch, shots, bloom_per_shot):
    base = max(base_deg, 0.001)
    move = base * (0.15 if crouch else 1.0)
    moving = base * (speed / max(max_speed, 0.001)) * (1.2 if crouch else 2.4)
    air = base * 3.5 if airborne else 0.0
    bloom = min(shots * bloom_per_shot, 4.0) * base
    return math.radians(move + moving + air + bloom)


def recoil_step(pattern, index, h_bias, decay):
    n = len(pattern)
    if n == 0:
        return (0.0, 0.0)
    pen = 1.0
    if index >= n:
        pen = min(max(1.0 - (index - n) * decay, 0.25), 1.0)
    x, y = pattern[index % n]
    return (x * pen * h_bias, y * pen)


def recover(accum, speed, delta):
    k = min(max(speed, 0.0), 1e3)
    f = math.exp(-k * delta)
    return tuple(v * f for v in accum)


def travel_time(dist, muzzle):
    return dist / muzzle if muzzle > 0 else 0.0


def drop_m(t):
    return 0.5 * GRAVITY * t * t


# Паттерн AK (первые 10 выстрелов): X — горизонталь, Y — подброс.
AK = [(0.6, 1.8), (1.1, 2.6), (0.4, 2.2), (-0.7, 1.9), (-1.3, 1.6),
      (-0.9, 1.5), (0.2, 1.4), (1.0, 1.2), (0.8, 1.0), (-0.4, 0.9)]

ok = fail = 0


def chk(name, got, exp, eps=1e-6):
    global ok, fail
    if isinstance(exp, (list, tuple)) or isinstance(got, (list, tuple)):
        good = list(got) == list(exp)
    elif isinstance(exp, bool) or isinstance(got, bool):
        good = bool(got) == bool(exp)
    elif isinstance(exp, (int, float)) and isinstance(got, (int, float)):
        good = abs(got - exp) <= eps
    else:
        good = got == exp
    def fmt(v):
        if isinstance(v, float):
            return round(v, 4)
        if isinstance(v, (list, tuple)):
            return type(v)(round(x, 4) if isinstance(x, float) else x for x in v)
        return v
    print(f"{'PASS' if good else 'FAIL'}  {name:46s} got={fmt(got)} exp={fmt(exp)}")
    if good:
        ok += 1
    else:
        fail += 1


print("--- урон по дистанции (AK: 36 dmg, спад 10м -> 40м, пол 0.7) ---")
chk("0м == базовый", damage_base(36, 0, 10, 40, 0.7), 36)
chk("10м граница (ещё полный)", damage_base(36, 10, 10, 40, 0.7), 36)
chk("25м середина спада", damage_base(36, 25, 10, 40, 0.7), 30.6)
chk("40м пол", damage_base(36, 40, 10, 40, 0.7), 25.2)
chk("100м не проседает ниже пола", damage_base(36, 100, 10, 40, 0.7), 25.2)
chk("монотонно убывает", all(
    damage_base(36, d, 10, 40, 0.7) >= damage_base(36, d + 1, 10, 40, 0.7)
    for d in range(0, 80)), True)

print("--- броня (ratio = 1 - armor_frac*(1-pen)*0.5) ---")
chk("full armor + pen=1.0 => без реза", armor_damage(36, 100, 1.0, 4.0, False), 36.0)
chk("full armor + pen=0.5 => -25%", armor_damage(36, 100, 0.5, 4.0, False), 27.0)
chk("full armor + pen=0.0 => -50%", armor_damage(36, 100, 0.0, 4.0, False), 18.0)
chk("без брони => полный урон", armor_damage(36, 0, 0.0, 4.0, False), 36.0)
chk("armor=50, pen=0 => -25%", armor_damage(36, 50, 0.0, 4.0, False), 27.0)
chk("броня не даёт урон выше базового", armor_damage(36, 100, 0.0, 4.0, False) <= 36.0, True)
chk("pen растёт => урон растёт", armor_damage(36, 100, 0.9, 4.0, False) > armor_damage(36, 100, 0.1, 4.0, False), True)
chk("хедшот с шлемом x4", armor_damage(36, 0, 0.5, 4.0, True), 144.0)
chk("hitmult head/chest/leg", (hitmult("head"), hitmult("chest"), hitmult("leg")), (4.0, 1.0, 0.87))
chk("hitmult неизвестная часть = 1.0", hitmult("tail"), 1.0)

print("--- разброс (base 0.6 deg, max_speed 250) ---")
s_still = spread_rad(0.6, 0, 250, False, False, 0, 0.35)
s_move = spread_rad(0.6, 250, 250, False, False, 0, 0.35)
s_crouch = spread_rad(0.6, 0, 250, False, True, 0, 0.35)
s_air = spread_rad(0.6, 0, 250, True, False, 0, 0.35)
s_bloom = spread_rad(0.6, 0, 250, False, False, 5, 0.35)
d = math.degrees
chk("стой == base", d(s_still), 0.6)
chk("присед = 0.15*base", d(s_crouch), 0.09)
chk("бег = 3.4x от стойки", d(s_move), 0.6 * 3.4)
chk("прыжок = 4.5x от стойки", d(s_air), 0.6 * 4.5)
chk("bloom cap на 4*base (12 выстр.)", d(spread_rad(0.6, 0, 250, False, False, 99, 0.35)), 0.6 * 5)
chk("монотонный рост с bloom", tuple(round(d(spread_rad(0.6,0,250,False,False,i,0.35)),4) for i in range(4)), (0.6, 0.81, 1.02, 1.23))
chk("стойка в разумных 0.05..1.5 deg", 0.05 <= d(s_still) <= 1.5, True)
chk("бег в разумных 0.5..8 deg", 0.5 <= d(s_move) <= 8.0, True)
chk("никогда не отрицательный", all(spread_rad(b, sp, 250, False, False, 0, 0.35) >= 0
                                    for b in (0.0, 0.6, 3.0) for sp in (0, 125, 250)), True)

print("--- отдача ---")
chk("выстрел 0 == паттерн[0]", recoil_step(AK, 0, 1.0, 0.1), (0.6, 1.8))
chk("wrap применяет затухание", recoil_step(AK, 20, 1.0, 0.1)[1] < AK[0][1], True)
chk("затухание не ниже 0.25", recoil_step(AK, 200, 1.0, 0.1), (AK[0][0] * 0.25, AK[0][1] * 0.25))
chk("пустой паттерн = 0", recoil_step([], 5, 1.0, 0.1), (0.0, 0.0))
chk("h_bias масштабирует только X", recoil_step(AK, 0, 2.0, 0.1), (1.2, 1.8))
r = (2.0, 5.0)
_f = math.exp(-10.0 * (1/60))
chk("recover: 1 кадр (speed 10, dt 1/60)", tuple(round(v,4) for v in recover(r,10.0,1/60)), (round(2.0*_f,4), round(5.0*_f,4)))
chk("recover: асимптотически к 0", max(recover(r, 10.0, 5.0)) < 1e-2, True)
chk("recover: speed=0 не гасит", recover(r, 0.0, 1/60), r)
chk("recover: FPS-независимость (240 vs 60 за 1с)",
    abs(recover(r, 10.0, 1.0)[1] - (lambda a: [a := recover(a, 10.0, 1/240) for _ in range(240)][-1])(r)[1]) < 0.02, True)

print("--- баллистика пули ---")
chk("travel_time 100м @715м/с", travel_time(100, 715), 100/715)
chk("drop за 0.14s", drop_m(100/715), 0.5*9.81*(100/715)**2)
chk("hitscan (muzzle=0) => 0", travel_time(100, 0), 0.0)

print(f"\nИТОГ: {ok} passed, {fail} failed")
raise SystemExit(1 if fail else 0)
