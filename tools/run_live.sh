#!/usr/bin/env bash
# Живой прогон карты: Godot запускается с main_scene=bench и автопилотом, поэтому
# физика шагает по-настоящему. Так было найдено всё, что пропускал --check-only:
# отсутствующий script= на Player, спавн внутри стены, форма коллизии в обёртке,
# накопление поворота камеры и отсутствие player_body у оружия.
#
#   ./tools/run_live.sh                 # карта bench
#   ./tools/run_live.sh res://scenes/maps/other.tscn
#
# Требует godot в $GODOT (по умолчанию godot4 на PATH).
set -u
GODOT="${GODOT:-godot4}"
MAP="${1:-res://scenes/maps/bench.tscn}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ" || exit 1
[ -f project.godot ] || { echo "нет project.godot в $PROJ"; exit 1; }

cp project.godot /tmp/project.godot.livebak
trap 'cp /tmp/project.godot.livebak project.godot; rm -f /tmp/project.godot.livebak' EXIT

python3 - "$MAP" <<'PY' || exit 1
import sys
from pathlib import Path
map_path = sys.argv[1]
p = Path("project.godot")
s = p.read_text()
# main_scene -> карта
s = s.replace('run/main_scene="res://scenes/ui/main_menu.tscn"', 'run/main_scene="%s"' % map_path, 1)
# автопилот: автозагрузкой, а не узлом сцены — не правим .tscn
if "LiveAutoPilot=" not in s:
    # ВАЖНО: дописываем В КОНЕЦ секции [autoload]. Вставка перед AudioBus меняла
    # порядок _ready всех автозагрузок, и поведение сцены отличалось от реального
    # запуска (я на этом потерял цикл: «падает» vs «стоит» на одном и том же коде).
    lines = s.split("\n")
    ai = next(i for i, l in enumerate(lines) if l.strip() == "[autoload]")
    end = ai + 1
    while end < len(lines) and not lines[end].startswith("["):
        end += 1
    lines.insert(end, 'LiveAutoPilot="*res://tests/live_autopilot.gd"')
    s = "\n".join(lines)
p.write_text(s)
PY

echo "== live run: $MAP"
"$GODOT" --headless --path . 2>&1 | grep -aE "^DUMP|^  замер|^LIVE ИТОГ|^   - |^READY:|^ALIGN:|SCRIPT ERROR" | grep -av "old surface format"
code=${PIPESTATUS[0]}
exit "$code"
