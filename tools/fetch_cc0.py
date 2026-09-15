#!/usr/bin/env python3
"""CC0-ассеты с GitHub ( itch.io/Poly Haven из песочницы недоступны).

Почему так: quaternius.itch.io требует API-ключ (гостю `invalid key`),
poly.pizza и polyhaven CDN — за Cloudflare/DNS-блоком. А CC0-паки, залитые в
GitHub, отдаются через raw + API без регистрации.

    python3 tools/fetch_cc0.py            # скачиваем пак в addons/
    python3 tools/fetch_cc0.py --check    # только сверить, что репо живёт

Лицензия скачанного: CC0-1.0 (Quaternius). Уважать автора — не перепродавать как есть.
"""
import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

REPOS = {
    # модульный sci-fi комплек: стены/двери/пропы/свет, УЖЕ в виде .tscn с коллизиями
    "quaternius-modular-scifi-pack": {
        "repo": "Malcolmnixon/Quaternius-Modular-Scifi-Pack",
        "branch": "main",
        "dest": "addons/quaternius-modular-scifi-pack",   # зеркалим структуру репо целиком
        "keep": (".tscn", ".tres", ".png", ".import", ".gd", ".md", ".gitattributes"),
        "strip_prefix": "",   # НЕ режем: .tscn ссылается на res://addons/quaternius-modular-scifi-pack/...
        "license": "CC0-1.0",
    },
}


def gh(url, timeout=45):
    try:
        with urllib.request.urlopen(urllib.request.Request(
                url, headers={"User-Agent": "strike-protocol-asset-fetch"}), timeout=timeout) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        sys.exit(f"GitHub API {e.code} для {url}\n{e.read()[:200].decode('utf8','replace')}")


def fetch(name: str) -> None:
    cfg = REPOS[name]
    dest = ROOT / cfg["dest"]
    tree_url = (f"https://api.github.com/repos/{cfg['repo']}"
                f"/git/trees/{cfg['branch']}?recursive=1")
    data = json.loads(gh(tree_url))
    blobs = [x for x in data["tree"]
             if x["type"] == "blob" and x["path"].endswith(tuple(cfg["keep"]))]
    big = [b for b in blobs if b.get("size", 0) > 12_000_000]
    if big:
        print(f"пропускаю {len(big)} файлов >12 МБ (лимит снэпшота воркспейса)")
    blobs = [b for b in blobs if b.get("size", 0) <= 12_000_000]
    print(f"{name}: {len(blobs)} файлов, лицензия {cfg['license']}, репо {cfg['repo']}")
    if data.get("truncated"):
        print("⚠️ GitHub обрезал дерево — часть файлов может не скачаться")

    ok = fail = 0
    total = 0
    for i, b in enumerate(blobs, 1):
        rel = b["path"]
        if rel.startswith(cfg["strip_prefix"]):
            rel = rel[len(cfg["strip_prefix"]):]
        out = dest / rel
        url = (f"https://raw.githubusercontent.com/{cfg['repo']}/{cfg['branch']}/"
               f"{b['path'].replace(' ', '%20')}")
        try:
            payload = gh(url, timeout=120)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(payload)
            total += len(payload)
            ok += 1
        except SystemExit as e:
            print(f"  ! {rel}: {e}")
            fail += 1
        if i % 40 == 0:
            print(f"  {i}/{len(blobs)} ({total/1e6:.1f} МБ)")
    print(f"готово: {ok} файлов, {fail} ошибок, {total/1e6:.1f} МБ -> {dest.relative_to(ROOT.parent)}")
    (dest / "SOURCES.md").write_text(
        f"# {name}\n\nрепо: {cfg['repo']}\nветка: {cfg['branch']}\n"
        f"лицензия: {cfg['license']}\nавтор оригинала: Quaternius (quaternius.com)\n"
        f"получено: tools/fetch_cc0.py {len(blobs)} файлов\n")


def check() -> None:
    for name, cfg in REPOS.items():
        url = f"https://api.github.com/repos/{cfg['repo']}"
        d = json.loads(gh(url))
        print(f"  {d['full_name']:46s} {(d.get('license') or {}).get('spdx_id')} | "
              f"{d.get('size')} KB | ⭐{d.get('stargazers_count')}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if a.check:
        check()
    else:
        for n in REPOS:
            fetch(n)
