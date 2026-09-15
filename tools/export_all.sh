#!/usr/bin/env bash
# Экспорт обеих сборок из корня проекта. Godot НЕ нужен пользователю для ИГРЫ —
# этот скрипт для тех, кто собирает сам (или для CI).
#
#   GODOT=/path/to/godot ./tools/export_all.sh [выходная_папка]   # по умолчанию ../build
#
# Требования:
#   1) бинарник Godot 4.7.2 (переменная GODOT или `godot4` в PATH)
#   2) экспортные шаблоны той же версии в
#      ~/.local/share/godot/export_templates/4.7.2.stable/
#      скачать: https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
#      распаковать каталог templates/ из архива в этот путь (файлы лежат плоско)
#
# Имена пресетов обязаны совпадать с export_presets.cfg 1:1 — иначе
# «Invalid export preset name» (проверено: переименованный пресет ломает экспорт).
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$PROJ/../build}"
GODOT="${GODOT:-godot4}"
[ -x "$GODOT" ] || GODOT="$(command -v godot4 || command -v godot || true)"
[ -n "$GODOT" ] || { echo "Godot не найден: задай GODOT=/путь/до/godot"; exit 1; }
cd "$PROJ" || exit 1
command -v zip >/dev/null || { echo "нет zip — архивы не соберу, сборки при этом нормальные"; }

mkdir -p "$OUT/windows" "$OUT/web"
log="$OUT/export.log"; : > "$log"
rc_all=0

echo "== Windows Desktop -> $OUT/windows/strike_protocol.exe"
"$GODOT" --headless --path . --export-release "Windows Desktop" \
    "$OUT/windows/strike_protocol.exe" >>"$log" 2>&1
echo "   rc=$?"; grep -qiE "ERROR|Invalid" "$log" && sed -n '1,40p' "$log"

echo "== Web -> $OUT/web/index.html"
"$GODOT" --headless --path . --export-release "Web" \
    "$OUT/web/index.html" >>"$log" 2>&1
echo "   rc=$?"

# ---------- самопроверка: «файл есть» ≠ «файл рабочий» ----------
exe="$OUT/windows/strike_protocol.exe"
if [ -f "$exe" ]; then
    python3 - "$exe" <<'PYCHK'
import sys, struct
d = open(sys.argv[1], 'rb').read()
off = struct.unpack_from('<I', d, 0x3c)[0]
pe = d[off:off + 4]
mach = struct.unpack_from('<H', d, off + 4)[0]
sub = struct.unpack_from('<H', d, off + 24 + 68)[0]   # OptionalHeader.Subsystem
tail = d[-4096:]
pck = b"GDPC" in tail
print("   MZ=%s PE=%r machine=0x%x(%s) subsystem=%s pck_встроен=%s  %.1f МБ" % (
    d[:2] == b"MZ", pe, mach, "x64" if mach == 0x8664 else "?",
    "GUI" if sub == 2 else sub, pck, len(d) / 1048576))
sys.exit(0 if d[:2] == b"MZ" and pe == b"PE\x00\x00" and mach == 0x8664 and pck else 1)
PYCHK
    [ $? -eq 0 ] || { echo "   !! .exe повреждён (нет MZ/PE/x64 или pck не встроен)"; rc_all=1; }
else
    echo "   !! .exe не создан"; rc_all=1
fi
for f in index.html index.js index.wasm index.pck; do
    if [ -f "$OUT/web/$f" ]; then
        sz=$(stat -c%s "$OUT/web/$f")
        printf "   web/%-11s %8.1f МБ\n" "$f" "$(awk -v s="$sz" 'BEGIN{printf "%.1f", s/1048576}')"
    else
        echo "   !! web/$f отсутствует"; rc_all=1
    fi
done
magic=$(head -c 4 "$OUT/web/index.wasm" 2>/dev/null | od -An -tx1 | tr -d ' \n')
if [ -n "$magic" ] && [ "$magic" != "0061736d" ]; then
    echo "   !! wasm-магический номер не сходится: $magic"; rc_all=1
fi

# ---------- раскладка релиза ----------
if [ $rc_all -eq 0 ]; then
    cp "$PROJ/tools/web_serve.py" "$OUT/web/serve.py"
    cp "$PROJ/tools/web_serve.bat" "$OUT/web/serve.bat"
    cat > "$OUT/windows/README.txt" <<'W1'
Strike Protocol — Windows. Ни Godot, ни установщика не нужно.

    двойной клик по strike_protocol.exe   — игра стартует сразу (окно 1920x1080)
    strike_protocol.exe --safe            — если падает или чёрный экран: отключает
                                            SDFGI/SSR/volumetric/glow, тени, MSAA
    strike_protocol.exe --high            — форсирует максимум (RT-качество)

F3 в игре — оверлей: активный рендерер, FPS, позиция, сцена (именно по нему
видно, что именно не так, если картинка пропала).
Управление: WASD, Shift бег, Ctrl присед, Space прыжок, ЛКМ огонь, ПКМ прицел,
R перезарядка, Esc отпускание мыши/пауза, Tab табло.
W1
    cat > "$OUT/web/README.txt" <<'W3'
Strike Protocol — веб-сборка. Двойным кликом по index.html НЕ откроется: file://
блокирует .wasm, а Godot требует COOP/COEP. Запусти локальный сервер:

    serve.bat                      Windows (нужен Python 3)
    python3 serve.py               -> http://127.0.0.1:8060
    python3 serve.py --public      доступ по локальной сети

Сервер отдаёт COOP/COEP и Range/206, иначе браузер не докачает pck.
Управление: WASD, Shift бег, Ctrl присед, Space прыжок, ЛКМ огонь, R перезарядка,
ПКМ прицел, Esc мышь, Tab табло, F3 отладочный оверлей.
Если тормозит или вместо картинки чёрный экран: в главном меню кнопка «ГРАФИКА»
переключает тяжёлые эффекты (SDFGI/SSR/volumetric/glow) — «Низкая» их выключает.
Аргументы командной строки в браузере не работают (в отличие от .exe), поэтому
для веб-сборки это единственный способ.
W3
    PKG="$OUT/_package/strike-protocol"
    rm -rf "$OUT/_package"; mkdir -p "$PKG/windows" "$PKG/web"
    cp "$OUT/windows/"* "$PKG/windows/" 2>/dev/null
    cp -r "$OUT/web/." "$PKG/web/"
    cp "$PROJ/README.md" "$PKG/README.md" 2>/dev/null || true
    if command -v zip >/dev/null; then
        ( cd "$OUT/_package" && rm -f ../strike-protocol-windows.zip ../strike-protocol-web.zip \
          && zip -qr ../strike-protocol-windows.zip strike-protocol/windows strike-protocol/README.md \
          && zip -qr ../strike-protocol-web.zip strike-protocol/web )
        cp "$OUT/strike-protocol-windows.zip" "$OUT/strike-protocol-web.zip" "$PROJ/../" 2>/dev/null
        python3 - <<'PY'
import zipfile, os
for f in (os.path.expanduser('~/strike-protocol-windows.zip'), os.path.expanduser('~/strike-protocol-web.zip')):
    if not os.path.exists(f):
        print("!! нет архива", f); continue
    z = zipfile.ZipFile(f)
    bad = z.testzip()
    print("%-34s %6.1f МБ  файлов %3d  %s" % (os.path.basename(f), os.path.getsize(f)/1048576,
                                              len(z.namelist()), "целостный" if bad is None else "битый: "+bad))
PY
    fi
fi

[ $rc_all -eq 0 ] && echo "ALL_DONE" || echo "ЕСТЬ ОШИБКИ — смотри $log"
exit $rc_all
