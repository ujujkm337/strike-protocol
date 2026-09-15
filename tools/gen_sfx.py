#!/usr/bin/env python3
"""Генерация SFX шутера через ElevenLabs /v1/sound-generation.

Free tier = 10 000 символов/месяц. Каждый запрос тратит len(text), поэтому
скрипт считает расход и сам останавливается, когда бюджет на исходе.

    python3 tools/gen_sfx.py            # весь список, пока хватает символов
    python3 tools/gen_sfx.py --dry      # только сметать: сколько съест
    python3 tools/gen_sfx.py only=guns  # префикс имени
"""
import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio" / "fx"
RESERVED = 600  # держим запас на пересъёмку неудачных дублей

# name -> (prompt, duration_s, prompt_influence)
SFX = {
    # --- шаги: 4 поверхности x 2 ноги, в Godot рандомим left/right ---
    "step_concrete_l": ("single heavy combat boot step on dusty concrete floor, dry short impact, close mic, no reverb", 0.5, 0.7),
    "step_concrete_r": ("single heavy boot step on concrete, slightly different scuff texture, dry, no reverb", 0.5, 0.7),
    "step_metal_l": ("boot stepping on hollow metal grating, metallic clang, short, dry", 0.5, 0.7),
    "step_metal_r": ("boot on metal grate, brief squeal and clank, short, dry", 0.5, 0.7),
    "step_gravel": ("footstep crunching on gravel and small stones, short dry impact", 0.5, 0.7),
    "step_sand": ("footstep into soft sand or dust, muffled powdery crunch", 0.5, 0.7),
    "jump_takeoff": ("cloth and boot rustle, quick crouch jump takeoff effort sound", 0.6, 0.6),
    "land_heavy": ("heavy boot landing on concrete, thud with slight dust, cloth rustle", 0.6, 0.6),

    # --- оружие: коротко, зло, без хвостов ---
    "guns_ak47": ("loud sharp AK-47 assault rifle single shot, 7.62 caliber, tight indoor concrete room slap, pistol crack", 1.4, 0.8),
    "guns_m4a1": ("M4A1 rifle single shot with sound suppressor, quiet muffled thump, high tech, short", 1.2, 0.8),
    "guns_deagle": ("desert eagle .50 pistol shot, extremely loud boom, deep report, short tail", 1.4, 0.8),
    "guns_awp": ("heavy sniper rifle bolt action shot, massive sharp crack with distant echo tail", 1.8, 0.8),
    "guns_scout": ("lightweight bolt action sniper rifle shot, clean sharp crack", 1.5, 0.8),
    "guns_ump": ("compact SMG single shot, punchy dry crack, light", 1.1, 0.8),

    # --- перезарядка: металл, затвор, магазин ---
    "reload_magin": ("metal rifle magazine being pulled out of weapon, sharp metallic click", 0.7, 0.75),
    "reload_magout": ("rifle magazine slammed into well, solid metallic clunk", 0.7, 0.75),
    "reload_bolt": ("AK rifle charging handle pulled and released, metallic bolt clack with spring", 0.8, 0.75),
    "reload_pistol": ("pistol slide racked back and forward, metallic clack", 0.7, 0.75),
    "empty_click": ("dry firing click on empty rifle chamber, small sharp metallic snap", 0.5, 0.8),
    "switch": ("weapon swap whoosh with light gear rustle and equipment clink", 0.6, 0.65),

    # --- попадания ---
    "hit_flesh": ("single muffled dull impact of a bullet hitting body armor, wet thud", 0.6, 0.7),
    "hit_helmet": ("bullet striking a metal helmet, sharp high pitched metallic ping", 0.6, 0.75),
    "hit_wall": ("bullet impact on concrete wall, sharp crack and small debris sprinkle", 0.7, 0.7),
    "hit_metal": ("bullet ricochet off thin metal sheet, bright zing with ring", 0.7, 0.75),
    "hit_glass": ("rifle bullet shattering a glass window, sharp break and falling shards", 0.9, 0.7),
    "kill_confirm": ("heavy body collapse to concrete floor, muffled thud and gear clatter", 0.9, 0.6),

    # --- тактическое ---
    "bomb_plant": ("electronic bomb timer beeping twice, keypad typing click, tactical", 1.4, 0.7),
    "bomb_defuse": ("wire snipped, small click then digital confirmation beep", 1.3, 0.7),
    "bomb_explode": ("powerful C4 plastic explosion, deep boom with concrete debris and dust", 2.2, 0.8),
    "grenade_pin": ("pulling a metal pin out of a hand grenade, sharp metallic ting with ring", 0.7, 0.8),
    "nade_bounce": ("metal grenade bouncing off concrete floor, hollow clank roll", 0.7, 0.7),
    "flash_pop": ("flashbang detonation, loud pop then high ringing tinnitus tone", 2.0, 0.75),
    "smoke_ignite": ("smoke grenade canister igniting, hiss of pressurized gas and powder burn", 1.5, 0.7),
    "he_explode": ("fragmentation grenade explosion, sharp blast with distant echo and rubble", 2.2, 0.8),
    "round_start": ("short metallic bomb whistle blast, sharp and loud, round start signal", 0.8, 0.7),

    # --- ambient ---
    "ambient_dust": ("desert wind blowing through abandoned concrete structures, distant sand hiss, no music", 5.0, 0.55),
    "menu_bed": ("dark minimal cinematic low drone with soft texture, no melody, quiet, looping ambient bed for a game menu", 8.0, 0.5),

    # --- интерфейс (щелчки короткие, почти.click) ---
    "ui_hover": ("very soft short UI hover tick, subtle, digital", 0.5, 0.85),
    "ui_click": ("clean modern UI button click, short digital pop, subtle", 0.5, 0.85),
    "ui_back": ("soft low UI back click, digital, short", 0.5, 0.85),
    "ui_slider": ("small UI slider tick sound, one click, digital and tight", 0.5, 0.85),
    "ui_error": ("low short negative UI error blip, muted", 0.55, 0.85),
    "ui_confirm": ("crisp affirmative UI confirmation blip, short and bright", 0.55, 0.85),
}


def read_key() -> str:
    for line in (ROOT / ".env").read_text().splitlines():
        if line.startswith("ELEVENLABS_API_KEY="):
            return line.split("=", 1)[1].strip()
    sys.exit("нет ELEVENLABS_API_KEY в .env")


def spent(key) -> int:
    """Сколько символов уже сожжено за цикл — чтобы знать реальный остаток."""
    r = urllib.request.Request("https://api.elevenlabs.io/v1/user/subscription",
                               headers={"xi-api-key": key})
    try:
        with urllib.request.urlopen(r, timeout=25) as resp:
            d = json.loads(resp.read())
            return int(d.get("character_count", 0)), int(d.get("character_limit", 0))
    except urllib.error.HTTPError as e:
        return -1, -1


def gen(key, name, text, dur, infl, fmt="mp3_44100_128"):
    body = {"text": text, "duration_seconds": max(0.5, min(30.0, dur)), "prompt_influence": infl}
    req = urllib.request.Request("https://api.elevenlabs.io/v1/sound-generation",
        data=json.dumps(body).encode(),
        headers={"xi-api-key": key, "Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            blob = resp.read()
        dest = OUT / f"{name}.mp3"
        dest.write_bytes(blob)
        return len(blob), None
    except urllib.error.HTTPError as e:
        return 0, e.read()[:300].decode("utf8", "replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--only", default="")
    a = ap.parse_args()

    key = read_key()
    OUT.mkdir(parents=True, exist_ok=True)
    used, cap = spent(key)
    left = (cap - used - RESERVED) if cap > 0 else 999999
    print(f"бюджет: израсходовано {used}/{cap}, резерв {RESERVED}, доступно ~{left} символов")

    todo = [(n, p) for n, p in SFX.items() if (not a.only or n.startswith(a.only))]
    if a.dry:
        total = sum(len(t) for _, (t, _, _) in todo)
        print(f"\n{'файл':22s} {'dur':>5s} {'симв':>5s}")
        for n, (t, d, _) in todo:
            print(f"  {n:20s} {d:5.1f} {len(t):5d}")
        print(f"\nитого {len(todo)} файлов, ~{total} символов "
              f"({'хватит' if total <= left else 'НЕ ХВАТАЕТ'}: осталось {left})")
        return

    done = 0
    budget = left
    failed = []
    for n, (t, d, infl) in todo:
        if len(t) > budget:
            print(f"  ~ стоп: {n} требует {len(t)} символов, осталось {budget}")
            break
        size, err = gen(key, n, t, d, infl)
        budget -= len(t)
        if err:
            print(f"  FAIL {n:22s} {err[:110]}")
            failed.append(n)
        else:
            done += 1
            print(f"  ok   {n:22s} {size/1024:6.1f} КБ  (бюджет ещё {budget})")

    # Godot хочет .ogg/.wav лучше, но mp3 тоже умеет. Пишем карту для AudioStream.
    (OUT / "sfx_manifest.json").write_text(json.dumps(
        {n: {"prompt": t, "duration": d} for n, (t, d, _) in todo}, indent=2))
    used2, _ = spent(key)
    print(f"\nсгенерировано: {done}, провалено: {len(failed)} {failed or ''}")
    print(f"расход по аккаунту: {used} -> {used2} символов")


if __name__ == "__main__":
    main()
