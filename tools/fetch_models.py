#!/usr/bin/env python3
"""Клиент 3D AI Studio API -> GLB-модели в assets/models/.

Ключ берётся ТОЛЬКО из .env (файл с chmod 600, в git не коммитить).
Баланс 200 кредитов, лимит 3 запроса/мин -> запросы разнесены на 21 с.

    python3 tools/fetch_models.py --test          # одна модель, проверка схемы
    python3 tools/fetch_models.py                 # батч из manifest
    python3 tools/fetch_models.py --list manifest # что собираемся качать
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV = ROOT / ".env"
OUT = ROOT / "assets" / "models"
API = "https://api.3daistudio.com"
RATE_LIMIT_S = 21.0  # 3 req/min -> держим запас

# ---- батч для FPS-прототипа: то, чего нет в CC0-паках ----
MANIFEST = [
    {"slug": "wall_grenade", "prompt": "modern military fragmentation hand grenade, M67 style, matte olive drab metal body, safety lever and pin, game prop", "pbr": True},
    {"slug": "claymore", "prompt": "plastic military Claymore anti-personnel mine with scissor stand, olive drab, game prop", "pbr": True},
    {"slug": "k_evolution", "prompt": "modern tactical folding knife with black handle, closed, game prop", "pbr": True},
    {"slug": "crate_stack", "prompt": "weathered wooden shipping crate stack with metal corners, desert tan paint, game environment prop", "pbr": True},
    {"slug": "barrel_pair", "prompt": "two rusty metal oil barrels leaning against each other, faded yellow paint, game environment prop", "pbr": True},
    {"slug": "sandbags", "prompt": "military sandbag barricade wall, burlap sacks stacked, game environment prop", "pbr": True},
    {"slug": "concrete_barrier", "prompt": "jersey concrete traffic barrier with chipped edges, game environment prop", "pbr": True},
    {"slug": "c4_bomb", "prompt": "block of C4 plastic explosive with keypad timer and red wires, game prop", "pbr": True},
]


def read_key() -> str:
    for line in ENV.read_text().splitlines():
        if line.startswith("STUDIO_API_KEY="):
            return line.split("=", 1)[1].strip()
    sys.exit("нет STUDIO_API_KEY в .env")


def req(path: str, key: str, data=None, method=None, raw=False, timeout=60):
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(
        API + path, data=body, method=method or ("POST" if body else "GET"),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            payload = resp.read()
            if raw:
                return resp.status, payload
            try:
                return resp.status, json.loads(payload)
            except json.JSONDecodeError:
                return resp.status, {"_raw": payload[:400].decode("utf8", "replace")}
    except urllib.error.HTTPError as e:
        return e.code, {"_error": e.read()[:600].decode("utf8", "replace")}


def balance(key) -> str:
    c, d = req("/account/user/wallet/", key)
    return d.get("balance", "?") if c == 200 else f"HTTP {c}"


def submit(key, prompt, pbr, engine="tencent"):
    path = f"/v1/3d-models/{engine}/generate/rapid/"
    payload = {"prompt": prompt, "enable_pbr": pbr}
    return req(path, key, payload)


def poll(key, task_id, deadline):
    """Ждём FINISHED. Возвращаем dict статуса или None по таймауту."""
    while time.time() < deadline:
        c, d = req(f"/v1/generation-request/{task_id}/status/", key)
        if c != 200:
            print(f"    ! status HTTP {c}: {d}")
            time.sleep(6)
            continue
        st = d.get("status")
        print(f"    status={st} progress={d.get('progress')}")
        if st == "FINISHED":
            return d
        if st in ("FAILED", "CANCELED", "FAILURE"):
            print(f"    !! провал: {d.get('failure_reason')}")
            return d
        time.sleep(6)
    return None


def download(url, dest: Path):
    """URL лежит на storage-хосте — заголовок авторизации там не нужен и вреден."""
    try:
        with urllib.request.urlopen(url, timeout=180) as r:
            dest.write_bytes(r.read())
            return dest.stat().st_size
    except Exception as e:
        print(f"    !! скачивание не удалось: {e}")
        return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", action="store_true", help="одна тестовая модель")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--engine", default="tencent", help="tencent | tripo | trellis")
    ap.add_argument("--wait", type=int, default=420, help="макс сек на генерацию")
    ap.add_argument("--max", type=int, default=99, help="сколько моделей из батча")
    a = ap.parse_args()

    key = read_key()
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"баланс ДО: {balance(key)} кредитов")

    if a.list:
        for i, m in enumerate(MANIFEST, 1):
            print(f"  {i}. {m['slug']}")
        return

    jobs = ([{"slug": "test_ak47", "prompt": "AK-47 assault rifle, wooden furniture, game weapon model, side view", "pbr": True}]
            if a.test else MANIFEST[: a.max])

    meta = {}
    for i, j in enumerate(jobs):
        print(f"\n[{i+1}/{len(jobs)}] {j['slug']}")
        c, d = submit(key, j["prompt"], j["pbr"], a.engine)
        print(f"  submit HTTP {c}: {json.dumps(d)[:260]}")
        if c not in (200, 201, 202):
            print("  пропускаю (не примило запрос) — проверяю код ошибки выше")
            if c == 429:
                print("  rate limit: сплю 65 с")
                time.sleep(65)
            continue
        task = d.get("task_id") or d.get("id") or (d.get("request") or {}).get("id")
        if not task:
            print("  !! не нашёл task_id в ответе — печатаю ключи:", list(d.keys()))
            continue
        res = poll(key, task, time.time() + a.wait)
        if not res or res.get("status") != "FINISHED":
            print(f"  !! не дождались. статус: {res}")
            continue
        results = res.get("results") or []
        got = []
        for item in results:
            url = item.get("asset") or item.get("url")
            typ = item.get("asset_type", "?")
            ext = ".glb" if ".glb" in (url or "") else ".bin"
            if not url:
                continue
            dest = OUT / f"{j['slug']}{ext}"
            size = download(url, dest)
            print(f"    {typ}: {dest.name} ({size/1e6:.2f} МБ)")
            if size:
                got.append({"file": dest.name, "type": typ, "bytes": size})
        meta[j["slug"]] = {"prompt": j["prompt"], "task_id": task, "files": got}
        if i + 1 < len(jobs):
            time.sleep(RATE_LIMIT_S)

    (OUT / "manifest_generated.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False))
    print(f"\nбаланс ПОСЛЕ: {balance(key)}")
    made = sum(len(m["files"]) for m in meta.values())
    print(f"готово: {made} файлов в {OUT}")


if __name__ == "__main__":
    main()
