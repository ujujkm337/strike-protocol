#!/usr/bin/env python3
"""Конвертер текстовых .tscn/.tres из Godot 3 в Godot 4 формат.

Зачем: Quaternius Modular Sci-Fi Pack (CC0) на GitHub лежит в Godot 3
(format=2, Spatial/StaticBody, PoolByteArray). Godot 4 умеет конвертировать
это только через GUI-редактор, а у нас headless. Здесь — тот же набор правил.

Не tries: .blend/.fbx/.meshlib/GridMap (их конвертер не трогает, они помечены в README).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

TYPE_MAP = {
    "Spatial": "Node3D", "MeshInstance": "MeshInstance3D", "StaticBody": "StaticBody3D",
    "KinematicBody": "CharacterBody3D", "CollisionShape": "CollisionShape3D",
    "OmniLight": "OmniLight3D", "SpotLight": "SpotLight3D",
    "DirectionalLight": "DirectionalLight3D", "AudioStreamPlayer3D": "AudioStreamPlayer3D",
    "Camera": "Camera3D", "Area": "Area3D", "RigidBody": "RigidBody3D",
    "BoxShape": "BoxShape3D", "SphereShape": "SphereShape3D",
    "CylinderShape": "CylinderShape3D", "CapsuleShape": "CapsuleShape3D",
    "ConcavePolygonShape": "ConcavePolygonShape3D",
    "ConvexPolygonShape": "ConvexPolygonShape3D", "PrismShape": "PrismShape3D",
    "WorldEnvironment": "WorldEnvironment",
}
RES_MAP = {
    "StandardMaterial": "StandardMaterial3D", "SpatialMaterial": "StandardMaterial3D",
    "BoxShape": "BoxShape3D", "SphereShape": "SphereShape3D",
    "CylinderShape": "CylinderShape3D", "CapsuleShape": "CapsuleShape3D",
    "ConcavePolygonShape": "ConcavePolygonShape3D",
    "ConvexPolygonShape": "ConvexPolygonShape3D",
    "QuadMesh": "QuadMesh", "ArrayMesh": "ArrayMesh",
}
# свойство -> новое имя (Godot 4 переименовал несколько)
PROP_MAP = {
    "material/material": "material_override",
    "transform/enabled": "enabled",
    "light/bake_mode": "gi_mode",
    "normal_map/enabled": "normal_roughness_enabled",
    "metallic/textures": "specular_mode",
    "vertex_color_use_as_albedo": "vertex_color_use_as_albedo",
    "params/size": "size", "distance_fade_mode": "distance_fade_mode",
}
# Godot 3 хранил extents у форм; Godot 4 тоже extents — ок. Но у BoxShape size->extents не меняем.
DROP_KEYS = ("Occluder", "occluder/", "lightmap/", "navmesh/", "sort_with_material",
             "aabb/", "gi/lightmapper", "light_smap", "shadow_to_opacity")


def convert_text(src: str) -> str:
    s = src
    m = re.search(r"\[gd_scene ([^\]]*)\]", s)
    if m:
        hdr = m.group(1)
        if "format=3" not in hdr and "format=4" not in hdr:
            s = s.replace(hdr, hdr.replace("format=2", "format=3"))
    # --- удаление только того, чего в 4.x нет (аккуратно, блоками sub_resource) ---
    s = re.sub(r"\n\[sub_resource type=\"OccluderShapePolygon\" id=([^\]]+)\][^\[]*", "\n", s)
    # ТОЛЬКО sub_resource-блоки окклюдеров; узлы с именем "Occluder" не трогаем
    s = re.sub(r"\n\[sub_resource type=\"Occluder[A-Za-z]*\"[^\]]*\]\n(?:[^\n]\n)*?", "\n", s)
    s = re.sub(r"\n[A-Za-z_/]*occluder[A-Za-z_/]* = [^\n]*", "", s)
    s = re.sub(r"\n[A-Za-z_/]*lightmap[A-Za-z_/]* = [^\n]*", "", s)
    s = re.sub(r"\nlightmap_size_hint = [^\n]*", "", s)

    def fix_type(t: str) -> str:
        return TYPE_MAP.get(t, RES_MAP.get(t, t))

    def sub_res(m2):
        t = m2.group(2)
        return f'[sub_resource type="{fix_type(t)}" id={m2.group(3)}]'


    s = re.sub(r'\[node name="([^"]*)" type="([^"]+)"',
               lambda m2: f'[node name="{m2.group(1)}" type="{fix_type(m2.group(2))}"', s)
    # ext_resource: id=1 -> id="1"
    s = re.sub(r'(type="[^"]+" id=)(\d+)\]', r'\1"\2"]', s)
    s = re.sub(r'(path="[^"]+" type="[^"]+" id=)(\d+)\]', r'\1"\2"]', s)
    s = re.sub(r'(id=)(\d+)( type="PackedScene")', r'\1"\2"\3', s)
    # Pool*Array -> Packed*Array; конструкторы
    s = s.replace("PoolByteArray(", "PackedByteArray(").replace("PoolByteArray", "PackedByteArray")
    s = s.replace("PoolIntArray(", "PackedInt32Array(").replace("PoolRealArray(", "PackedFloat64Array(")
    s = s.replace("PoolVector2Array(", "PackedVector2Array(").replace("PoolVector3Array(", "PackedVector3Array(")
    s = s.replace("PoolStringArray(", "PackedStringArray(")
    s = s.replace("Color(", "Color(")
    s = re.sub(r'\nresource_name = ', '\nresource_name = ', s)
    s = s.replace("\t", "    ")
    # рекурсивные словари surfaces -> Godot 4 ждёт Array(...)
    return s


def fix_load_steps(s: str) -> str:
    def repl(m):
        head = m.group(0)
        body_start = s.find(head)
        return head
    return s


def recount(path: Path) -> None:
    """load_steps в Godot = 1 + число ресурсов. Считаем заново по факту."""
    t = path.read_text()
    n = len(re.findall(r"^\[(ext|sub)_resource ", t, flags=re.M))
    nm = re.search(r"\[gd_scene ([^\]]*)\]", t)
    if nm:
        new = re.sub(r"load_steps=\d+", f"load_steps={n + 1}", nm.group(1))
        if "load_steps=" not in new and n:
            new = f"load_steps={n + 1} " + new
        t = t[:nm.start(1)] + new + t[nm.end(1):]
        path.write_text(t)


def main(target: str) -> None:
    files = sorted(Path(target).rglob("*.tscn")) + sorted(Path(target).rglob("*.tres"))
    changed = 0
    for f in files:
        before = f.read_text()
        after = convert_text(before)
        if after != before:
            f.write_text(after)
            changed += 1
        recount(f)
    print(f"пройдено {len(files)} файлов, изменено {changed}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else
         "addons/quaternius-modular-scifi-pack/addons/quaternius-modular-scifi-pack")
