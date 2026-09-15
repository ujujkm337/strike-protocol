# Strike Protocol — Godot 4.7.2 competitive FPS

## Играть прямо сейчас (без установки Godot)

Сборки лежат в релизах: **https://github.com/ujujkm337/strike-protocol/releases**

| Архив | Что делать |
|---|---|
| `strike-protocol-windows.zip` | распаковать → двойной клик `strike_protocol.exe`. Ни движка, ни установщика не нужно |
| `strike-protocol-web.zip` | распаковать → `serve.bat` (или `python3 serve.py`) → http://127.0.0.1:8060 |
| `strike-protocol-godot.zip` | исходники: открыть `project.godot` в Godot 4.7.2 и F5 |

`file://` для веб-сборки не работает (браузер не грузит `.wasm` без http + нужны
COOP/COEP), поэтому и нужен `serve.py` — он отдаёт правильные заголовки и `Range/206`.

**Управление:** WASD · Shift бег · Ctrl присед · Space прыжок · ЛКМ огонь · ПКМ прицел ·
R перезарядка · колесо смена оружия · Esc отпустить мышь/пауза · Tab табло ·
**F3** — оверлей (рендерер, fps, позиция, сцена).

**Если что-то не так:** `strike_protocol.exe --safe` (гасит SDFGI/SSR/volumetric/glow,
оставляет одну теневую карту) или `--high` (форсирует максимум). В веб-сборке
аргументы недоступны — кнопка «ГРАФИКА» в главном меню.


## Собрать самому (нужен Godot 4.7.2 + экспортные шаблоны)

```bash
GODOT=/path/to/godot ./tools/export_all.sh          # → build/windows/*.exe, build/web/, два zip
GODOT=/path/to/godot ./tools/run_tests.sh           # все проверки + живой прогон физики
LIVE=0 GODOT=… ./tools/run_tests.sh                 # только юнит-проверки
```
Windows: `setup.bat` (ищет/ставит Godot) → `run_bench.bat` → `test_all.bat`.
`.env` в архив не входит: скопируйте `.env.example` → `.env` (нужен только для
генерации ассетов через API, для игры не нужен).

## Что проверено движком (не «должно скомпилироваться», а прогнано)
```
движок            Godot 4.7.2-stable.official.ed1daf0bf (headless)
раннер            ./tools/run_tests.sh → 8 сюжетов зелёные
  ballistics 27/0 · movement 22/0 · bench PASS · assets PASS · play_session PASS
  menu_runtime PASS · audio_refs PASS (21 ссылка на звук) · net_stub PASS
живой прогон      ./tools/run_live.sh → физика шагает по-настоящему:
  опора (зазор -0.001), глаза 2.72 при поле 1.00, спавн лицом к центру (dot 0.95),
  HUD «AK-47 30/90», 5.10 м за 45 кадров WASD, шаги -> step_concrete_l.mp3,
  присед 2.72 -> 1.90, SCRIPT ERROR: 0
экспорт           --export-release Windows + Web → rc=0; самовалидация: PE/x64/GUI,
                  встроенный pck (GDPC), wasm-магия 0061736d, zip целостный
Python-зеркало    python3 tests/test_ballistics.py → 37 passed, 0 failed
вес проекта       8.3 МБ без .godot
```
Что НЕ проверяется здесь и проверяется только у вас: запуск `.exe` на Windows и
картинка в браузере (нет GPU/сессии).

## Активы: реально сгенерированы и лежат в проекте
**Звук — 43 файла** (`assets/audio/fx/*.mp3`, ElevenLabs `POST /v1/sound-generation`):
шаги 4×поверхностей + left/right, прыжок/приземление, 6 стволов, 5 перезарядок,
5 попаданий, тактические (C4/дефьюз/взрыв/булава/отскок/флеш/дым/ХЭ),
`ambient_dust` 5.07 с, `menu_bed` 8.07 с, 6 UI-щелчков.
Проверено: битых 0, дисперсия байт 74–79 (не тишина), длительность совпала с
запрошенной по байтам (128 kbps) — `guns_ak47` 22.5 КБ ≈ 1.44 с при 1.4 с в запросе.

**3D — 2 модели** (`assets/models/`, Tencent Hunyuan 3D Pro через 3D AI Studio):
валидные glTF v2, 28 076 вершин / 50 000 треугольников, PBR-набор внутри
(baseColor + metallicRoughness + normal), генератор — Khronos glTF Blender I/O 4.0.43.
Затем **`/v1/tools/optimize/`**: 27.4 → 2.2 МБ и 28.8 → 2.7 МБ (−91/92%).
Godot импортирует GLB без ошибок.

## Рабочие вызовы API (схемы проверены, не угаданы)
```bash
# баланс / лимит (3 req/мин!)
curl https://api.3daistudio.com/account/user/wallet/ -H "Authorization: Bearer $KEY"
#   → {"balance":"20.00","rate_limit":3}

# генерация: 80 кредитов за Pro+PBR (Rapid ~35, но упал на стороне провайдера — кредиты НЕ списали)
curl -X POST https://api.3daistudio.com/v1/3d-models/tencent/generate/pro/ \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"3.0","prompt":"…","enable_pbr":true,"face_count":50000,"generate_type":"Normal"}'
#   → {"task_id":"…"}  ; поллить /v1/generation-request/<id>/status/ → status=FINISHED
#   results: [{asset_type:"ARCHIVE", asset:…zip}, {asset_type:"3D_MODEL", asset:…glb}]

# сжатие: 10 кредитов. ТОЛЬКО multipart, поле model_file (model_base64 — невалидно),
# preset ∈ {low, default, …} (max_compression — НЕвалидно, валидатор это и сказал)
curl -X POST https://api.3daistudio.com/v1/tools/optimize/ -H "Authorization: Bearer $KEY" \
  -F preset=low -F max_texture_size=1024 -F model_file=@model.glb;type=model/gltf-binary
```
Скрипты: `tools/gen_sfx.py` (считает бюджет символов, `--dry` — смета),
`tools/fetch_models.py` (батч, `--test`, уважает 3/мин). Ключи читаются из `.env`
(chmod 600), в git не коммитить.

## Экономика кредитов (ваш баланс 200 → 20)
| Операция | Кредиты |
|---|---|
| Pro-генерация + PBR | 80 |
| Rapid (была ошибка провайдера) | 0 — не списали |
| Optimize/сжатие | 10 |

Осталось **20**: 2 сжатия, или одна Rapid-генерация. 8 моделей из `MANIFEST`
в `tools/fetch_models.py` — это 640 кредитов Pro; реально с 200 кредитов берите
CC0-паки (Quaternius Ultimate Guns, 2×25 стволов polyyai) и генерите только то,
чего в них нет.

## Экономика ElevenLabs
`tier = free`, **10 000 симв/мес**, было 1 021 → стало 1 329 после 43 файлов
(SFX-промпты короткие, ~65 символов; `duration_seconds` жёстко 0.5–30 — 0.45
отказывается API). Резерв на пересъёмку неудачных: 600 символов.

## Структура
```
project.godot                  Forward+, MSAA4x, input map, 3 autoload
scripts/core/ballistics.gd     урон/броня/разброс/отдача/recover — чистые функции
scripts/core/movement_rules.gd Quake-трение, caps, air-control, stride/bob, античит-потолок
scripts/core/weapon_data.gd    Resource + 4 ствола (AK/M4A1-S/Deagle/AWP) с паттернами
scripts/player/fps_controller.gd  CharacterBody3D, 2 коллайдера (стой/присед), шаги
scripts/player/weapon.gd      hitscan, конусный bloom, отдача в камеру, RPC-запрос на сервер
scripts/core/game_rules.gd     раунды, buy-economy, loss bonus, 13 раундов
scripts/core/audio_manager.gd  шины, кэш, pitch-jitter
scripts/network/net_manager.gd ENet host/join (каркас под ваш домашний сервер)
scripts/ui/main_menu.gd        hover-твины, панель входа, ConfigFile-настройки
scenes/ui/main_menu.tscn       меню с 3D-подложкой через SubViewport
scenes/world_environment.tscn  SDFGI + ACES + объёмный туман + SSR + glow
tests/                          2 сюиты, гоняются headless без GPU
```

## Ключевые решения
- **`Ballistics`/`MovementRules` — `RefCounted` без узлов.** Один код на клиент
  (предсказание) и сервер (авторитет) → нет рассинхрона; тесты идут на CPU.
- **Урон считает только сервер.** Клиент шлёт `server_request_shot(origin, dir)`.
- **`limit_length(speed_cap)` обязателен.** Равновесие Quake-трения = `A/F`:
  при `accel=55, friction=9` это 6.111 м/с при капе 6.6 — игрок физически не
  разгонялся бы до максимума. Это поймали тесты, а не отладка в редакторе.
- **`Tween` нельзя вешать как узел** в 4.x (не `Node`) — сцена с `[node type="Tween"]`
  падала при импорте.
- **Автозагрузки читаются через `get_node_or_null("/root/…")`**: по имени (`Net`,
  `AudioBus`) скрипт не компилируется в контекстах без дерева (`--check-only`, `-s`).
- **`INFERENCE_ON_VARIANT` в 4.7 — ошибка**, поэтому `var t: Tween = dict.get(k)`
  и `var err: int = …` с явными типами.

## Обновление: Tripo и CC0-контент

**Tripo: ключ валиден, кредитов 0.**
```
POST https://openapi.tripo3d.ai/v3/generation/text-to-model  → 403 code 2010
     "You don't have enough credit to create this task"
GET  https://openapi.tripo3d.ai/v3/account/balance           → {"balance":0.00,"frozen":0.00}
POST https://api.tripo3d.ai/v2/openapi/task                  → тот же 2010
```
Ключ принят (не 401, валидатор выдал список моделей: `P1-20260311, P2-20260801,
v2.5-20250123, v3.0-20250812, v3.1-20260211`). Бесплатного API-гранта у Tripo нет —
`20 генераций/день` это про веб-студию Hunyuan, а 300 кредитов Basic-плана — про
веб-интерфейс, не про API. Поэтому контент берём из CC0.

**CC0: как скачалось, когда itch.io и Poly Haven недоступны**
itch.io требует API-ключ гостя (`{"errors":["invalid key"]}`), poly.pizza — за
Cloudflare (`403 Just a moment`), `files.polyhaven.com` — DNS не резолвится.
Рабочий путь — CC0-репозитории на GitHub (`raw.githubusercontent.com` отдаёт):
```
python3 tools/fetch_cc0.py     # Malcolmnixon/Quaternius-Modular-Scifi-Pack, CC0-1.0
```
195 файлов / 11.9 МБ: 27 тел с коллизиями, 14 пропов, 26 деталей, материалы, звук двери.
**Важно: пак был под Godot 3** (format=2, `Spatial`, `PoolByteArray`, `Transform`,
`.import/` в путях, `setget`). Godot конвертирует это только через GUI-редактор, а у нас
headless → написал `tools/convert_godot3_pack.py`: переименование типов, Packed*Array,
Transform3D, format=3, пересчёт `load_steps`, удаление окклюдеров и meshlib (в 4.x это
GeometryCollection, не переносится). Скрипты пака (`door.gd` на `SceneTreeTween`)
отвязаны — `SceneTreeTween` в 4.x удалён, перенос = переписать на `Tween`; оставил TODO.

**bench.tscn генерируется, а не рисуется руками** (`tools/build_bench.py`): читает root-тип
и `extents` каждого префаба и расставляет 54 объекта по периметру + укрытия.
Итог прогона: 202 узла, 56 тел с коллизией, 6 источников света, камера и оружие на месте.

**Рантайм-тест меню** (`tests/test_menu_runtime.gd`, 12 кадров) поймал то, чего парсер не видит:
`cam.pivot_offset = Vector3.ZERO` — `pivot_offset` есть у `Control`/`Node2D`, но не у
`Camera3D`; падало каждый кадр. Плюс `_process` в SceneTree обязан возвращать `false`,
иначе цикл кадров встаёт и тест «зелёный» враньём.

## Дальше (по плану)
- [ ] `ai/bot.gd` — NavigationAgent3D + state machine
- [x] `scenes/maps/bench.tscn` — собран генератором, грузится и инстанцируется
- [ ] навмеш + LightmapGI в bench (нужен запечённый свет — это уже про ваш GPU)
- [ ] `doors/` — переписать QuaterniusDoor на `create_tween()`
- [ ] `ui/hud.tscn` — прицел, киллфид, радар, счётчик патронов
- [ ] `export_presets.cfg` + `godot --headless --export-release` (запускаете у себя: экспорт-шаблоны и GPU тут недоступны)
- [ ] `tests/test_round_flow.gd` — экономика раундов как чистые функции

## Про «графику как в UE5» — честно
Godot 4.6/4.7 не имеет аппаратного рейтрейсинга, Lumen-класса GI и Nanite.
Картинка тянет SDFGI+ACES+туман+SSR, но фотореализм с трассировкой лучей —
не сюда. Упор на свет, материалы и пост-обработку.
