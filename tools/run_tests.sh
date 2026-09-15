#!/usr/bin/env bash
# Полный кроссплатформенный прогон проверок (аналог test_all.bat для Linux/macOS/CI).
#   GODOT=/path/to/godot ./tools/run_tests.sh
# Выход != 0, если хоть одна проверка упала. Статус каждой строки — из ИТОГ-строки,
# а не из кода возврата Godot (он возвращает 0 и при падении скрипта).
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot4}"
[ -x "$GODOT" ] || GODOT="$(command -v godot4 || command -v godot || true)"
[ -n "$GODOT" ] || { echo "Godot не найден: GODOT=/путь/до/godot"; exit 2; }
cd "$PROJ" || exit 2
TESTS="ballistics movement bench assets play_session menu_runtime audio_refs net_stub"
fail=0
for t in $TESTS; do
    out=$(timeout 600 "$GODOT" --headless --path . -s "tests/test_$t.gd" 2>&1)
    line=$(printf '%s\n' "$out" | grep -aE "ИТОГ" | head -1)
    err=$(printf '%s\n' "$out" | grep -acE "SCRIPT ERROR")
    if printf '%s' "$line" | grep -aqE "FAIL"; then
        printf "  %-14s FAIL   %s\n" "$t" "$line"; fail=1
    elif [ -z "$line" ]; then
        printf "  %-14s ???    нет ИТОГ-строки (скрипт упал) — см. ниже\n" "$t"
        printf '%s\n' "$out" | grep -aE "SCRIPT ERROR|Parse Error" | head -3 | sed 's/^/                /'; fail=1
    elif [ "$err" != "0" ]; then
        printf "  %-14s WARN   %s | SCRIPT ERROR x%s\n" "$t" "$line" "$err"; fail=1
    else
        printf "  %-14s ok     %s\n" "$t" "$line"
    fi
done
if [ "${LIVE:-1}" = "1" ]; then
    echo "  --- live (физика по-настоящему) ---"
    if GODOT="$GODOT" bash tools/run_live.sh >/tmp/live.out 2>&1; then
        printf "  %-14s ok     %s\n" "live" "$(grep -a 'LIVE ИТОГ' /tmp/live.out | head -1)"
    else
        printf "  %-14s FAIL   %s\n" "live" "$(grep -a '^   - ' /tmp/live.out | head -4 | tr '\n' ';')"
        fail=1
    fi
fi
[ "$fail" = "0" ] && echo "=== ВСЕ ПРОВЕРКИ ЗЕЛЁНЫЕ ===" || echo "=== ЕСТЬ ПАДЕНИЯ ==="
exit "$fail"
