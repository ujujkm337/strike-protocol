#!/usr/bin/env python3
"""Генератор bench-карты из CC0-пака Quaternius Modular Sci-Fi.

Не рисует .tscn руками: читает root-тип и extents коллизии каждого префаба,
поэтому геометрия/укрытия в сцене реальные, а не выставленные на глаз.

    python3 tools/build_bench.py --report   # что вообще есть в паке
    python3 tools/build_bench.py            # собрать scenes/maps/bench.tscn
"""
import argparse
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "addons" / "quaternius-modular-scifi-pack"
OUT = ROOT / "scenes" / "maps" / "bench.tscn"

BODY_HINTS = ("wall", "column", "ramp", "platform", "stair", "crate", "container")
Q = chr(34)  # двойная кавычка, чтобы не воевать с экранированием


def prefab_meta(path: Path) -> dict:
    t = path.read_text(errors="ignore")
    m = re.search(r'\[node name="([^"]*)" type="([^"]+)"\]', t)
    ext = re.search(r"extents = Vector3\( ([^)]+)\)", t)
    if ext:
        a, b, c = (float(x) for x in ext.group(1).split(","))
        size = (2 * a, 2 * b, 2 * c)
    else:
        size = (1.0, 1.0, 1.0)
    return {
        "name": m.group(1) if m else path.stem,
        "type": m.group(2) if m else "Node3D",
        "size": size,
        "solid": "StaticBody3D" in t,
        "res": "res://addons/quaternius-modular-scifi-pack/" + path.relative_to(PACK).as_posix(),
    }


def scan() -> dict:
    out = {"bodies": [], "props": [], "details": []}
    if not PACK.exists():
        sys.exit("нет пака — сначала: python3 tools/fetch_cc0.py")
    for f in sorted(PACK.rglob("*.tscn")):
        if f.name.endswith("_mesh.tscn") or "_body" in f.name:
            continue
        rel = f.relative_to(PACK).as_posix()
        meta = prefab_meta(f)
        low = f.name.lower()
        if any(h in low for h in BODY_HINTS) and meta["solid"]:
            out["bodies"].append(meta)
        elif rel.startswith("props/"):
            out["props"].append(meta)
        elif rel.startswith("details/"):
            out["details"].append(meta)
    return out


def emit(data: dict) -> str:
    ext_ids: dict = {}
    for meta in data["used"]:
        ext_ids.setdefault(meta["res"], len(ext_ids) + 1)

    L: list = []
    n_extra = 5                      # 2 скрипта + env + HUD + 1 sub-блок
    n_sub = 4                        # floor mesh, floor shape, capsule, crouch box
    L.append(f"[gd_scene load_steps={len(ext_ids) + n_extra + n_sub + 1} format=3]")
    L.append(f'[ext_resource path="res://scripts/player/fps_controller.gd" type="Script" id="90"]')
    L.append(f'[ext_resource path="res://scripts/player/weapon.gd" type="Script" id="91"]')
    L.append(f'[ext_resource path="res://scenes/world_environment.tscn" type="PackedScene" id="99"]')
    L.append(f'[ext_resource path="res://scenes/ui/hud.tscn" type="PackedScene" id="92"]')
    for res, i in ext_ids.items():
        L.append(f'[ext_resource path="{res}" type="PackedScene" id="{i}"]')
    L.append("")
    fw, fd = data["floor"]
    L.append('[sub_resource type="PlaneMesh" id="floor_mesh"]')
    L.append(f"size = Vector2({fw}, {fd})")
    L.append("subdivide_width = 8")
    L.append("subdivide_depth = 8")
    L.append("")
    L.append('[sub_resource type="BoxShape3D" id="floor_shape"]')
    L.append(f"extents = Vector3({fw/2}, 1.0, {fd/2})")
    L.append("")
    L.append('[sub_resource type="CapsuleShape3D" id="player_cap"]')
    L.append("radius = 0.35")
    L.append("height = 1.8")
    L.append("")
    L.append('[sub_resource type="BoxShape3D" id="player_crouch"]')
    L.append("extents = Vector3(0.35, 0.55, 0.35)")
    L.append("")
    L.append('[node name="Bench" type="Node3D"]')
    L.append("")
    L.append('[node name="WorldEnvironment" parent="." instance=ExtResource("99")]')
    L.append("")
    L.append('[node name="Floor" type="StaticBody3D" parent="."]')
    L.append("")
    L.append('[node name="Mesh" type="MeshInstance3D" parent="Floor"]')
    L.append("mesh = SubResource(\"floor_mesh\")")
    L.append("")
    L.append('[node name="Col" type="CollisionShape3D" parent="Floor"]')
    L.append("shape = SubResource(\"floor_shape\")")
    L.append("")
    L.append('[node name="Lights" type="Node3D" parent="."]')
    L.append("")
    L.append('[node name="Sun" type="DirectionalLight3D" parent="Lights"]')
    L.append("transform = Transform3D(0.86, 0, 0.5, 0.43, 0.5, -0.74, -0.25, 0.75, 0.6, 0, 14, 0)")
    L.append("shadow_enabled = true")
    L.append("directional_shadow_max_distance = 80.0")
    for i, (x, y, z) in enumerate(data["lights"]):
        L.append("")
        L.append(f'[node name="Lamp{i}" type="OmniLight3D" parent="Lights"]')
        L.append(f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, {y}, {z})")
        L.append(f"light_color = Color(1, {round(0.82 + 0.04*(i % 3), 3)}, 0.6, 1)")
        L.append(f"light_energy = {2.6 + 0.4 * (i % 2)}")
        L.append("omni_attenuation = 1.6")
        L.append("omni_range = 12.0")
        # 5 теневых оммни-светей = 5 кубатурных карт на кадр: на встроенном GPU это
        # переполнение VRAM и вылет через ~10 с. Тень оставляем одному, объёмный свет
        # тоже (он всё равно требует включённого volumetric fog).
        L.append("shadow_enabled = %s" % ("true" if i == 0 else "false"))
        L.append("# atlas-size задаётся в project.godot")
        L.append("distance_fade_enabled = true")
        L.append("distance_fade_begin = 28.0")
        L.append("distance_fade_length = 10.0")
        L.append("volume_enabled = %s" % ("true" if i == 0 else "false"))
        L.append("volume_albedo = Color(0.7, 0.76, 0.86, 1)")
    L.append("")
    L.append('[node name="Geometry" type="Node3D" parent="."]')
    for idx, place in enumerate(data["places"]):
        meta = place["meta"]
        x, y, z, ry = place["pos"]
        c, s = round(math.cos(ry), 6), round(math.sin(ry), 6)
        L.append("")
        L.append(f'[node name="{meta["name"]}_{idx}" parent="Geometry" instance=ExtResource("{ext_ids[meta["res"]]}")]')
        L.append(f"transform = Transform3D({c}, 0, {-s}, 0, 1, 0, {s}, 0, {c}, {x}, {y}, {z})")
    L.append("")
    L.append('[node name="Player" type="CharacterBody3D" parent="." groups=["player"]]')
    L.append('script = ExtResource("90")')
    L.append('spawn_path = NodePath("../SpawnCT")')
    L.append(f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -16, 1.2, -8)")
    L.append("")
    L.append('[node name="Stand" type="CollisionShape3D" parent="Player"]')
    L.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)")
    L.append("shape = SubResource(\"player_cap\")")
    L.append("")
    L.append('[node name="Crouch" type="CollisionShape3D" parent="Player"]')
    L.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)")
    L.append("shape = SubResource(\"player_crouch\")")
    L.append("disabled = true")
    L.append("")
    L.append('[node name="Head" type="Node3D" parent="Player"]')
    L.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.82, 0)")
    L.append("")
    L.append('[node name="Camera3D" type="Camera3D" parent="Player/Head"]')
    L.append("fov = 90.0")
    L.append("far = 500.0")
    L.append("current = true")
    L.append("")
    L.append('[node name="Weapon" type="Node3D" parent="Player/Head/Camera3D"]')
    L.append("script = ExtResource(\"91\")")
    L.append("camera = NodePath(\"..\")")
    L.append("player_body = NodePath(\"../../..\")")
    L.append("")
    L.append("")
    L.append('[node name="SpawnCT" type="Marker3D" parent="."]')
    L.append("transform = Transform3D(-0.707107, 0, 0.707107, 0, 1, 0, -0.707107, 0, -0.707107, -16, 1.2, -8)")
    L.append("")
    L.append('[node name="SpawnT" type="Marker3D" parent="."]')
    L.append("transform = Transform3D(-0.707107, 0, -0.707107, 0, 1, 0, 0.707107, 0, -0.707107, 16, 1.2, 8)")
    L.append("")
    L.append('[node name="HUD" parent="." instance=ExtResource("92")]')
    out: list = []
    for l in L:
        if l == "" and out and out[-1] == "":
            continue
        out.append(l)
    return "\n".join([l for l in out if l != "None"]) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()
    scanned = scan()
    if a.report:
        for k, v in scanned.items():
            print(f"{k}: {len(v)}")
            for m in v[:5]:
                sz = tuple(round(x, 2) for x in m["size"])
                print(f"   {m['name']:28s} {m['type']:15s} solid={m['solid']} size={sz}")
        return

    W, D = 44.0, 28.0
    places: list = []
    solids = [m for m in scanned["bodies"] if m["solid"]]
    if not solids:
        sys.exit("нет тел с коллизией — строить не из чего")
    walls = sorted(solids, key=lambda m: -(m["size"][0] / max(m["size"][2], 0.01)))[:10]

    def put(meta, x, y, z, ry=0.0):
        places.append({"meta": meta, "pos": (round(x, 3), y, round(z, 3), round(ry, 5))})

    step = 4.0
    for i in range(int(W / step) + 1):
        x = -W / 2 + i * step
        put(walls[i % len(walls)], x, 0, -D / 2)
        put(walls[(i + 5) % len(walls)], x, 0, D / 2, math.pi)
    for i in range(int(D / step) + 1):
        z = -D / 2 + i * step
        put(walls[(i + 3) % len(walls)], -W / 2, 0, z, math.pi / 2)
        put(walls[(i + 8) % len(walls)], W / 2, 0, z, -math.pi / 2)

    cover = [m for m in scanned["props"] if m["size"][0] > 0.6] or solids
    n = 0
    for gx in range(-3, 4):
        for gz in range(-2, 3):
            if (gx + gz) % 3 == 0:
                put(cover[n % len(cover)], gx * 5.5, 0, gz * 5.5, (n * 0.7) % (2 * math.pi))
                n += 1
    # центральный бокс-укрытие и два «платформенных» пролёта
    big = max(solids, key=lambda m: m["size"][0] * m["size"][2])
    for off in ((0, 0), (-9, 0), (9, 0)):
        put(big, off[0], 0, off[1], 0.0 if off[0] == 0 else 1.5708)

    lights = [(-13, 5.4, -7), (13, 5.4, -7), (-13, 5.4, 7), (13, 5.4, 7), (0, 6.0, 0)]
    data = {"places": places, "floor": (W, D), "lights": lights,
            "used": [p["meta"] for p in places]}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(emit(data))
    uniq = len({p["meta"]["res"] for p in places})
    print(f"объектов: {len(places)} | уникальных префабов: {uniq} | свет: {len(lights)+1}")
    print(f"записано: {OUT.relative_to(ROOT.parent)} ({OUT.stat().st_size/1024:.1f} КБ)")


if __name__ == "__main__":
    main()
